package domain

import "testing"

func TestSituationForMissingRepo(t *testing.T) {
	if got := SituationForMissingRepo(); got != SituationError {
		t.Errorf("got %q, want error", got)
	}
}

func TestSituationFromVersionProbe(t *testing.T) {
	cases := []struct {
		name    string
		outcome VersionProbeOutcome
		want    Situation
		wantOK  bool
	}{
		{"spawn failed", VersionProbeOutcome{SpawnOrExitFailed: true}, SituationCliMissing, false},
		{"nonzero exit reported as spawn/exit failed", VersionProbeOutcome{SpawnOrExitFailed: true, Version: "0.1.0"}, SituationCliMissing, false},
		{"timed out", VersionProbeOutcome{TimedOut: true}, SituationError, false},
		{"timed out beats spawn failed", VersionProbeOutcome{TimedOut: true, SpawnOrExitFailed: true}, SituationError, false},
		{"outdated", VersionProbeOutcome{Version: "0.1.0"}, SituationCliOutdated, false},
		{"current", VersionProbeOutcome{Version: "0.8.0"}, "", true},
		{"newer than floor", VersionProbeOutcome{Version: "9.9.9"}, "", true},
		{"empty version defers to status, not treated as outdated", VersionProbeOutcome{Version: ""}, "", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := SituationFromVersionProbe(c.outcome, "0.8.0")
			if got != c.want || ok != c.wantOK {
				t.Errorf("SituationFromVersionProbe(%+v) = (%q, %v), want (%q, %v)", c.outcome, got, ok, c.want, c.wantOK)
			}
		})
	}
}

// Edge case of the spec, User Story 2 scenario 5: a version probe that is
// merely slow must never be reported as an absent CLI.
func TestVersionProbeTimeoutIsNeverCliMissing(t *testing.T) {
	got, ok := SituationFromVersionProbe(VersionProbeOutcome{TimedOut: true, SpawnOrExitFailed: true}, "0.8.0")
	if got == SituationCliMissing {
		t.Fatal("a timed-out probe must never resolve to cli-missing")
	}
	if got != SituationError || ok {
		t.Errorf("got (%q, %v), want (error, false)", got, ok)
	}
}

func TestSituationFromStatus(t *testing.T) {
	cases := []struct {
		name    string
		outcome StatusOutcome
		want    Situation
	}{
		{"exit 0 plain review", StatusOutcome{ExitCode: 0}, SituationReview},
		{"exit 0 with finish conflict", StatusOutcome{ExitCode: 0, HasFinishConflict: true}, SituationFinishConflict},
		{"exit 2 plain no-review", StatusOutcome{ExitCode: 2}, SituationNoReview},
		{"exit 2 with pending finish", StatusOutcome{ExitCode: 2, ListFinishPending: true}, SituationFinishPending},
		{"exit 3 out of range", StatusOutcome{ExitCode: 3}, SituationOutOfRange},
		{"exit 1 is error, not review", StatusOutcome{ExitCode: 1}, SituationError},
		{"unknown exit code is error", StatusOutcome{ExitCode: 42}, SituationError},
		{"timed out is error", StatusOutcome{TimedOut: true, ExitCode: 0}, SituationError},
		{"spawn failed is error", StatusOutcome{SpawnFailed: true}, SituationError},
		// A pending finish only matters on exit 2; a finish conflict only on
		// exit 0. Neither field is consulted at all outside its own exit code.
		{"finish conflict flag ignored on exit 2", StatusOutcome{ExitCode: 2, HasFinishConflict: true}, SituationNoReview},
		{"pending flag ignored on exit 0", StatusOutcome{ExitCode: 0, ListFinishPending: true}, SituationReview},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := SituationFromStatus(c.outcome); got != c.want {
				t.Errorf("SituationFromStatus(%+v) = %q, want %q", c.outcome, got, c.want)
			}
		})
	}
}

// A status timeout must resolve to error, and specifically never to
// cli-missing — that CLI-absence-vs-slowness distinction is not just a
// version-probe concern.
func TestStatusTimeoutIsNeverCliMissing(t *testing.T) {
	if got := SituationFromStatus(StatusOutcome{TimedOut: true}); got == SituationCliMissing {
		t.Fatal("a timed-out status read must never resolve to cli-missing")
	}
}

// contracts/tui-surface.md: cli-missing, cli-outdated and error "no se
// repintan de memoria" — each read derives its own independent verdict.
// Neither derivation function takes a previous situation as input, so a
// fresh, healthy read right after a failing one must not carry anything
// over from it.
func TestSituationsAreNeverRepaintedFromMemory(t *testing.T) {
	_, _ = SituationFromVersionProbe(VersionProbeOutcome{SpawnOrExitFailed: true}, "0.8.0")
	// A brand-new read with no relation to the call above.
	fresh, ok := SituationFromVersionProbe(VersionProbeOutcome{Version: "0.8.0"}, "0.8.0")
	if !ok {
		t.Fatal("a fresh, current probe must clear the way to status, regardless of any earlier verdict")
	}
	if fresh == SituationCliMissing {
		t.Fatal("a fresh verdict must not inherit a previous cli-missing")
	}

	_ = SituationFromStatus(StatusOutcome{TimedOut: true})
	freshStatus := SituationFromStatus(StatusOutcome{ExitCode: 0})
	if freshStatus != SituationReview {
		t.Fatalf("a fresh status read must not inherit a previous error, got %q", freshStatus)
	}
}

func TestIsReviewReadable(t *testing.T) {
	for _, s := range []Situation{SituationReview, SituationFinishConflict} {
		if !IsReviewReadable(s) {
			t.Errorf("%q should be review-readable", s)
		}
	}
	for _, s := range []Situation{SituationWaiting, SituationCliMissing, SituationCliOutdated, SituationNoReview, SituationFinishPending, SituationOutOfRange, SituationError} {
		if IsReviewReadable(s) {
			t.Errorf("%q should not be review-readable", s)
		}
	}
}
