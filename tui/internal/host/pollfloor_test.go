package host

import (
	"context"
	"testing"
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
	floor := NewPollFloor(50 * time.Millisecond)
	deadline := time.Now().Add(300 * time.Millisecond)
	for time.Now().Before(deadline) {
		if floor.Due(time.Now()) {
			t.Fatal("floor must never be due while reads keep arriving faster than Interval")
		}
		floor.Reset()
		time.Sleep(10 * time.Millisecond)
	}
}

// The same property, measured against the REAL invocation log (host.go's
// in-memory record of every process this client spawned): as long as
// something else keeps calling Reset() faster than Interval, the floor
// contributes exactly zero of the invocations in the log.
func TestPollFloorAddsNoInvocationsWhileReadsStayFrequent(t *testing.T) {
	dir := initRepo(t)
	t.Chdir(dir)
	ResetInvocationLogForTest()

	floor := NewPollFloor(50 * time.Millisecond)
	reads := 0
	deadline := time.Now().Add(250 * time.Millisecond)
	for time.Now().Before(deadline) {
		if floor.Due(time.Now()) {
			t.Fatal("the floor must not fire while reads keep arriving faster than Interval")
		}
		InvokeSupportGit(context.Background(), []string{"rev-parse", "--git-dir"})
		reads++
		floor.Reset()
		time.Sleep(10 * time.Millisecond)
	}

	if got := len(InvocationLog()); got != reads {
		t.Fatalf("invocation log has %d entries, want exactly %d (the floor must add none)", got, reads)
	}
}

// Sanity check the floor is not simply inert: once reads stop, it does
// eventually come due — the mechanism agujero 5 needs still exists.
func TestPollFloorDuesAfterInactivity(t *testing.T) {
	floor := NewPollFloor(50 * time.Millisecond)
	time.Sleep(80 * time.Millisecond)
	if !floor.Due(time.Now()) {
		t.Fatal("floor must become due once Interval elapses with no Reset")
	}
}
