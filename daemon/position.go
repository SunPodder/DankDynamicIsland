package main

const (
	// positionSnapBandUs: for microsecond-precise reporters, re-anchor when
	// |sample - estimate| exceeds this band. Below it the interpolation clock
	// is more accurate than any single sample.
	positionSnapBandUs = 250_000 // 250ms

	// quantizedMarginUs: slack beyond one second-quantum before a
	// second-quantized reporter's sample forces a back-anchor.
	quantizedMarginUs = 250_000 // 250ms

	// driftMinErrUs: sample error below this is bus/player jitter, not drift.
	driftMinErrUs = 40_000 // 40ms

	// driftStreakLen: consecutive same-sign drift observations required before
	// nudging the clock (~1.9s at the 120ms poll cadence).
	driftStreakLen = 16

	// quantumSampleWindow: consecutive samples inspected to classify a reporter
	// as second-quantized.
	quantumSampleWindow = 3

	// quantumEpsilonUs: how far a sample may sit from an exact second
	// boundary and still count as second-quantized (some reporters are a
	// few µs sloppy around the boundary).
	quantumEpsilonUs = 2_000

	// secondQuantumUs: quantum of reporters that truncate Position to whole
	// seconds (Firefox does this), i.e. one second in microseconds.
	secondQuantumUs = 1_000_000
)

// positionReconciler folds fresh MPRIS Position samples into the daemon's
// free-running interpolation clock.
//
// Some players (notably Firefox) report Position quantized to whole seconds:
// a floor of the true value that lags audible playback by up to one second.
// Anchoring the clock to every raw sample drags lyrics behind by exactly that
// lag, and the clock sawtooths across lyric boundaries (visible as flicker).
// The reconciler instead classifies the reporter and re-anchors only when a
// sample carries real information:
//
//   - Second-quantized reporters: samples are floor bounds. The clock
//     free-runs and re-anchors when a one-second step is witnessed (the true
//     position crossed the new value within the last poll interval), when the
//     estimate falls behind the floor, or when it runs ahead by over a
//     quantum. Worst-case error stays at one poll interval.
//   - Precise reporters: snap on any error beyond positionSnapBandUs, and
//     nudge once small same-sign error persists (slow drift, e.g. a wrong
//     Rate), which transient jitter never accumulates.
type positionReconciler struct {
	samples     [quantumSampleWindow]int64
	sampleCount int
	sampleIdx   int
	lastSample  int64
	hasLast     bool
	streakSign  int
	streakLen   int
}

// reconcile records sampleUs and decides whether to re-anchor the
// interpolation base. Returns (baseUs, true) to re-anchor at baseUs, or
// (0, false) to keep free-running. estUs is the interpolated estimate at
// sampling time; gapUs is the elapsed time since the previous sample.
func (r *positionReconciler) reconcile(estUs, sampleUs, gapUs int64) (int64, bool) {
	prevUs, hadLast := r.lastSample, r.hasLast
	r.lastSample = sampleUs
	r.hasLast = true

	r.samples[r.sampleIdx] = sampleUs
	r.sampleIdx = (r.sampleIdx + 1) % len(r.samples)
	if r.sampleCount < len(r.samples) {
		r.sampleCount++
	}

	if r.quantized() {
		r.streakLen = 0
		// Snap the sample to its nearest second boundary: quantized
		// reporters may be a few µs sloppy, and every comparison below
		// works on whole seconds.
		snapped := (sampleUs + secondQuantumUs/2) / secondQuantumUs * secondQuantumUs
		prevSnapped := (prevUs + secondQuantumUs/2) / secondQuantumUs * secondQuantumUs
		switch {
		case hadLast && snapped == prevSnapped+secondQuantumUs:
			// Witnessed a one-second step: the true position crossed
			// this boundary somewhere within the last poll gap. Anchoring
			// at the midpoint of that window centers the residual error
			// instead of leaving the clock a full gap behind.
			boost := gapUs / 2
			if boost > quantizedMarginUs {
				boost = quantizedMarginUs
			}
			return snapped + boost, true
		case snapped > estUs:
			// Estimate is behind even the floored sample: lagging after
			// startup or resume.
			return snapped, true
		case estUs-snapped > secondQuantumUs+2*gapUs+quantizedMarginUs:
			// Estimate ran more than a quantum plus two poll gaps ahead:
			// missed steps or forward drift. The two-gap slack keeps normal
			// scheduling jitter from masquerading as drift.
			return snapped, true
		}
		return 0, false
	}

	diff := sampleUs - estUs
	if diff > positionSnapBandUs || diff < -positionSnapBandUs {
		r.streakLen = 0
		return sampleUs, true
	}

	// Slow-drift integrator: sustained small same-sign error means the clock
	// crept away from the player. Jitter flips sign and never accumulates.
	sign := 0
	switch {
	case diff >= driftMinErrUs:
		sign = 1
	case diff <= -driftMinErrUs:
		sign = -1
	}
	if sign != r.streakSign {
		r.streakSign = sign
		r.streakLen = 0
	}
	if sign != 0 {
		r.streakLen++
		if r.streakLen >= driftStreakLen {
			r.streakLen = 0
			return sampleUs, true
		}
	}
	return 0, false
}

// quantized reports whether every recent sample sits on a one-second
// boundary (within quantumEpsilonUs), i.e. the reporter truncates Position
// to whole seconds.
func (r *positionReconciler) quantized() bool {
	if r.sampleCount < len(r.samples) {
		return false
	}
	for _, s := range r.samples {
		rem := s % secondQuantumUs
		if rem > quantumEpsilonUs && rem < secondQuantumUs-quantumEpsilonUs {
			return false
		}
	}
	return true
}

// positionUsFromVariant coerces a D-Bus Position property value to
// microseconds. Players are supposed to send int64, but some send other
// numeric types.
func positionUsFromVariant(v any) (int64, bool) {
	switch v := v.(type) {
	case int64:
		return v, true
	case uint64:
		return int64(v), true
	case int32:
		return int64(v), true
	case int:
		return int64(v), true
	case float64:
		return int64(v), true
	}
	return 0, false
}
