package host

import (
	"context"
	"testing"
	"testing/synctest"
	"time"
)

func TestPollSecondsConfigAbsentIsOff(t *testing.T) {
	dir := initRepo(t)
	t.Chdir(dir)
	if _, ok := PollSecondsConfig(); ok {
		t.Fatal("expected ok=false when reviewui.pollseconds is unset — FR-039 has no default")
	}
}

func TestPollSecondsConfigParsesAPositiveValue(t *testing.T) {
	dir := initRepo(t)
	t.Chdir(dir)
	runGit(t, dir, "config", "reviewui.pollseconds", "45")
	got, ok := PollSecondsConfig()
	if !ok || got != 45*time.Second {
		t.Fatalf("PollSecondsConfig() = %v, %v; want 45s, true", got, ok)
	}
}

func TestPollSecondsConfigRejectsNonPositive(t *testing.T) {
	dir := initRepo(t)
	t.Chdir(dir)
	runGit(t, dir, "config", "reviewui.pollseconds", "0")
	if _, ok := PollSecondsConfig(); ok {
		t.Fatal("expected ok=false for a non-positive value")
	}
}

// T060's gate: a floor being reset more often than its Interval must never
// come due — this is what "con la vigilancia funcionando, no agrega ni una
// invocación" means, checked as a number, not as a description.
func TestPollFloorNeverDuesWithFrequentReads(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		floor := NewPollFloor(50 * time.Millisecond)
		for range 6 {
			time.Sleep(40 * time.Millisecond)
			if floor.Due(time.Now()) {
				t.Fatal("floor must never be due while reads keep arriving faster than Interval")
			}
			floor.Reset()
		}
	})
}

// The same property, measured against the REAL invocation log (host.go's
// in-memory record of every process this client spawned): as long as
// something else keeps calling Reset() faster than Interval, the floor
// contributes exactly zero of the invocations in the log.
func TestPollFloorAddsNoInvocationsWhileReadsStayFrequent(t *testing.T) {
	dir := initRepo(t)
	t.Chdir(dir)
	ResetInvocationLogForTest()

	synctest.Test(t, func(t *testing.T) {
		floor := NewPollFloor(50 * time.Millisecond)
		const reads = 5
		for range reads {
			time.Sleep(40 * time.Millisecond)
			if floor.Due(time.Now()) {
				t.Fatal("the floor must not fire while reads keep arriving faster than Interval")
			}
			result := InvokeSupportGit(context.Background(), []string{"rev-parse", "--git-dir"})
			if result.ExitCode != 0 {
				t.Fatalf("read failed: %s", result.Stderr)
			}
			floor.Reset()
		}
		if got := len(InvocationLog()); got != reads {
			t.Fatalf("invocation log has %d entries, want exactly %d (the floor must add none)", got, reads)
		}
	})
}

// Sanity check the floor is not simply inert: once reads stop, it does
// eventually come due — the mechanism agujero 5 needs still exists.
func TestPollFloorDuesAfterInactivity(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		const interval = 50 * time.Millisecond
		floor := NewPollFloor(interval)
		time.Sleep(interval - time.Nanosecond)
		if floor.Due(time.Now()) {
			t.Fatal("floor became due before Interval elapsed")
		}
		time.Sleep(time.Nanosecond)
		if !floor.Due(time.Now()) {
			t.Fatal("floor must become due once Interval elapses with no Reset")
		}
	})
}
