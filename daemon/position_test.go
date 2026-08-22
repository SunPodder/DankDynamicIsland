package main

import (
	"math"
	"testing"
)

func TestReconcileQuantizedStepAnchors(t *testing.T) {
	r := &positionReconciler{}
	// Warm up on second-aligned samples within one second (realistic 120ms
	// poll cadence), then witness the reporter step to the next second: the
	// true position crossed sampleUs somewhere inside the last poll gap, so
	// the anchor lands at the midpoint of that window.
	r.reconcile(19_400_000, 19_000_000, 120_000)
	r.reconcile(19_520_000, 19_000_000, 120_000)
	r.reconcile(19_640_000, 19_000_000, 120_000)
	base, anchor := r.reconcile(19_950_000, 20_000_000, 120_000)
	if !anchor || base != 20_060_000 {
		t.Fatalf("step should anchor to %d, got anchor=%v base=%d", 20_060_000, anchor, base)
	}
}

func TestReconcileQuantizedFreeRunsBetweenSteps(t *testing.T) {
	r := &positionReconciler{}
	for range 3 {
		r.reconcile(19_400_000, 19_000_000, 120_000)
	}
	// Estimate ahead of the floored sample but within one quantum: the
	// sample carries no information, keep free-running.
	if _, anchor := r.reconcile(19_900_000, 19_000_000, 120_000); anchor {
		t.Fatal("estimate within one quantum of floored sample must not anchor")
	}
}

func TestReconcileQuantizedBehindFloorAnchors(t *testing.T) {
	r := &positionReconciler{}
	for range 3 {
		r.reconcile(21_800_000, 22_000_000, 120_000)
	}
	// Estimate fell behind the floor (resume race): snap forward.
	base, anchor := r.reconcile(21_900_000, 22_000_000, 120_000)
	if !anchor || base != 22_000_000 {
		t.Fatalf("sample ahead of estimate should anchor, got anchor=%v base=%d", anchor, base)
	}
}

func TestReconcileQuantizedAheadBeyondQuantumAnchors(t *testing.T) {
	r := &positionReconciler{}
	for range 3 {
		r.reconcile(19_500_000, 19_000_000, 120_000)
	}
	// Estimate ran more than a quantum plus two poll gaps past the floored
	// sample: missed steps or forward drift.
	base, anchor := r.reconcile(20_600_000, 19_000_000, 120_000)
	if !anchor || base != 19_000_000 {
		t.Fatalf("estimate beyond quantum+2*gap+margin should anchor, got anchor=%v base=%d", anchor, base)
	}
	// Within that envelope (e.g. one delayed poll): tolerated.
	if _, anchor := r.reconcile(20_400_000, 19_000_000, 120_000); anchor {
		t.Fatal("estimate within quantum+2*gap+margin must not anchor")
	}
}

// TestReconcileQuantizedNoisyFloorAnchors covers reporters that sit a few µs
// off the exact second boundary: they must still be classified as
// second-quantized and step-anchor on the snapped value.
func TestReconcileQuantizedNoisyFloorAnchors(t *testing.T) {
	r := &positionReconciler{}
	noise := []int64{-5, -6, -3}
	for i := range 3 {
		r.reconcile(19_400_000, 19_000_000+noise[i], 120_000)
	}
	base, anchor := r.reconcile(19_950_000, 20_000_000-4, 120_000)
	if !anchor || base != 20_060_000 {
		t.Fatalf("noisy step should anchor to %d, got anchor=%v base=%d", 20_060_000, anchor, base)
	}
}

// TestReconcileQuantizedJitteredPolls verifies that scheduling jitter in the
// poll loop (delayed samples, varied gaps) never makes the clock jump
// backwards or sawtooth across a lyric boundary.
func TestReconcileQuantizedJitteredPolls(t *testing.T) {
	gaps := []int64{120_000, 300_000, 120_000, 180_000, 120_000, 240_000}
	const (
		startTrueUs = 149_600_000
		lineAtUs    = 153_820_000
		runTimeUs   = 30_000_000
	)

	r := &positionReconciler{}
	truePos := int64(startTrueUs)
	baseUs, baseAt := int64(startTrueUs), int64(0)
	crossings := 0
	wasBehindLine := true
	maxBackward := int64(0)
	prevE := baseUs
	gi := 0

	for tUs := int64(0); tUs <= runTimeUs; {
		truePos = startTrueUs + tUs
		sample := truePos - truePos%secondQuantumUs
		est := baseUs + (tUs - baseAt)

		if newBase, anchor := r.reconcile(est, sample, gaps[gi]); anchor {
			baseUs, baseAt = newBase, tUs
		}
		curE := baseUs + (tUs - baseAt)
		if tUs > 2_000_000 && prevE-curE > maxBackward {
			maxBackward = prevE - curE
		}
		prevE = curE

		behindLine := curE < lineAtUs

		if wasBehindLine && !behindLine {
			crossings++
		}
		wasBehindLine = behindLine

		tUs += gaps[gi]
		gi = (gi + 1) % len(gaps)
	}

	if maxBackward > 5_000 {
		t.Fatalf("clock jumped backwards by %d us", maxBackward)
	}
	if crossings != 1 {
		t.Fatalf("lyric boundary crossed %d times (sawtooth/flap)", crossings)
	}
}

func TestReconcilePreciseSnapsOnLargeError(t *testing.T) {
	r := &positionReconciler{}
	// Microsecond-precise samples leave the window immediately.
	r.reconcile(10_000_000, 10_012_345, 120_000)
	base, anchor := r.reconcile(10_024_690, 11_500_000, 120_000)
	if !anchor || base != 11_500_000 {
		t.Fatalf("large error should anchor, got anchor=%v base=%d", anchor, base)
	}
}

func TestReconcilePreciseIgnoresJitter(t *testing.T) {
	r := &positionReconciler{}
	est := int64(50_000_000)
	// Alternating ±50ms jitter flips streak sign and must never anchor.
	for i := range 100 {
		sample := est
		if i%2 == 0 {
			sample += 50_000
		} else {
			sample -= 50_000
		}
		if _, anchor := r.reconcile(est, sample, 120_000); anchor {
			t.Fatalf("jitter anchored at iteration %d", i)
		}
	}
}

func TestReconcilePreciseNudgesOnSustainedDrift(t *testing.T) {
	r := &positionReconciler{}
	// Clock creeps 60ms behind the player and stays there: after
	// driftStreakLen consecutive observations the nudge fires, not earlier.
	anchors := 0
	for range driftStreakLen - 1 {
		if _, anchor := r.reconcile(60_000_000, 60_060_000, 120_000); anchor {
			anchors++
		}
	}
	if anchors != 0 {
		t.Fatalf("anchored before streak threshold (%d times)", anchors)
	}
	base, anchor := r.reconcile(60_000_000, 60_060_000, 120_000)
	if !anchor || base != 60_060_000 {
		t.Fatalf("sustained drift should anchor on observation %d, got anchor=%v base=%d", driftStreakLen, anchor, base)
	}
	// Streak resets after nudging: identical error needs a full streak again.
	for range driftStreakLen - 1 {
		if _, anchor := r.reconcile(60_060_000, 60_120_000, 120_000); anchor {
			t.Fatal("streak did not reset after nudge")
		}
	}
}

// TestReconcileFirefoxPlayback is the regression test for the measured bug:
// Firefox reports Position truncated to whole seconds (a floor of the true
// value). Anchoring every raw sample dragged lyrics up to a second behind and
// made the clock sawtooth across lyric boundaries. With the reconciler the
// clock stays within half a poll interval of true playback and crosses each
// lyric boundary exactly once.
func TestReconcileFirefoxPlayback(t *testing.T) {
	const (
		pollIntervalUs = 120_000 // daemon polls Position every ~120ms
		runTimeUs      = 30_000_000
		startTrueUs    = 149_600_000 // mid-song, arbitrary phase within the second
		lineAtUs       = 153_820_000 // an LRC line timestamp
	)

	r := &positionReconciler{}
	truePos := int64(startTrueUs)
	baseUs, baseAt := int64(startTrueUs), int64(0) // interpolation anchor
	maxErr, minErr := int64(math.MinInt64), int64(math.MaxInt64)
	crossings := 0
	wasBehindLine := true

	for tUs := int64(0); tUs <= runTimeUs; tUs += pollIntervalUs {
		truePos = startTrueUs + tUs
		sample := truePos - truePos%secondQuantumUs // Firefox's floor
		est := baseUs + (tUs - baseAt)

		if newBase, anchor := r.reconcile(est, sample, pollIntervalUs); anchor {
			baseUs, baseAt = newBase, tUs
		}

		e := baseUs + (tUs - baseAt) - truePos
		if tUs > 2_000_000 { // skip warm-up: reporter classification takes 3 samples
			if e > maxErr {
				maxErr = e
			}
			if e < minErr {
				minErr = e
			}
		}

		behindLine := baseUs+(tUs-baseAt) < lineAtUs
		if wasBehindLine && !behindLine {
			crossings++
		}
		wasBehindLine = behindLine
	}

	// Error stays within half a poll interval of true playback (the midpoint
	// anchor centers the witness delay).
	halfPoll := int64(pollIntervalUs) / 2
	if minErr < -halfPoll-10_000 || maxErr > halfPoll+10_000 {
		t.Fatalf("estimate error out of bounds: min=%d max=%d us", minErr, maxErr)
	}
	// No sawtooth: the lyric boundary is crossed exactly once.
	if crossings != 1 {
		t.Fatalf("lyric boundary crossed %d times (sawtooth/flap)", crossings)
	}
}
