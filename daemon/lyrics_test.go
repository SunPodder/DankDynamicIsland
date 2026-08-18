package main

import (
	"testing"
)

func TestParseLRC(t *testing.T) {
	sampleLRC := `[00:09.65] The club isn't the best place to find a lover
[00:12.10] So the bar is where I go
[00:14.81] Me and my friends at the table doing shots
[00:16.89] Drinking fast, and then we talk slow
[01:05.123] And now I'm singing like`

	lines := ParseLRC(sampleLRC)
	if len(lines) != 5 {
		t.Fatalf("expected 5 lines, got %d", len(lines))
	}

	if lines[0].TimeMs != 9650 {
		t.Errorf("line 0 expected 9650 ms, got %d", lines[0].TimeMs)
	}
	if lines[0].Text != "The club isn't the best place to find a lover" {
		t.Errorf("line 0 unexpected text: %s", lines[0].Text)
	}

	if lines[1].TimeMs != 12100 {
		t.Errorf("line 1 expected 12100 ms, got %d", lines[1].TimeMs)
	}

	if lines[4].TimeMs != 65123 {
		t.Errorf("line 4 expected 65123 ms, got %d", lines[4].TimeMs)
	}
}

func TestGetCurrentLyric(t *testing.T) {
	lm := NewLyricsManager()
	lines := []LyricLine{
		{TimeMs: 1000, Text: "Line 1"},
		{TimeMs: 5000, Text: "Line 2"},
		{TimeMs: 10000, Text: "Line 3"},
	}

	// Before line 1
	curr, next, idx, total := lm.GetCurrentLyric(lines, 500)
	if curr != "" || next != "Line 1" || idx != -1 || total != 3 {
		t.Errorf("before line 1 failed: curr=%q next=%q idx=%d total=%d", curr, next, idx, total)
	}

	// During line 1
	curr, next, idx, total = lm.GetCurrentLyric(lines, 2000)
	if curr != "Line 1" || next != "Line 2" || idx != 0 {
		t.Errorf("during line 1 failed: curr=%q next=%q idx=%d", curr, next, idx)
	}

	// During line 2
	curr, next, idx, total = lm.GetCurrentLyric(lines, 7000)
	if curr != "Line 2" || next != "Line 3" || idx != 1 {
		t.Errorf("during line 2 failed: curr=%q next=%q idx=%d", curr, next, idx)
	}

	// During line 3 (last line)
	curr, next, idx, total = lm.GetCurrentLyric(lines, 12000)
	if curr != "Line 3" || next != "" || idx != 2 {
		t.Errorf("during line 3 failed: curr=%q next=%q idx=%d", curr, next, idx)
	}
}
