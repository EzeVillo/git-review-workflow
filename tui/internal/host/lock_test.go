package host

import "testing"

func TestMutationLockDepthOneDiscardsSecondBegin(t *testing.T) {
	var l MutationLock
	if !l.Begin() {
		t.Fatal("first Begin must succeed")
	}
	if l.Begin() {
		t.Fatal("a second Begin while busy must be discarded (depth 1), never queued")
	}
	if !l.Busy() {
		t.Fatal("Busy must report true while a mutation is running")
	}
}

func TestMutationLockBeginAfterEndSucceeds(t *testing.T) {
	var l MutationLock
	l.Begin()
	l.End()
	if l.Busy() {
		t.Fatal("End must clear busy immediately")
	}
	if !l.Begin() {
		t.Fatal("a new mutation must be able to begin right after the previous one ended")
	}
}

func TestMutationLockSuppressesWatchWhileBusy(t *testing.T) {
	var l MutationLock
	l.Begin()
	if !l.Suppress() {
		t.Fatal("a watchMsg while busy must be suppressed")
	}
}

func TestMutationLockSuppressesWatchDuringWindowAndOwesOneRead(t *testing.T) {
	var l MutationLock
	l.Begin()
	gen := l.End()
	if !l.Suppress() {
		t.Fatal("a watchMsg during the silence window must be suppressed")
	}
	if !l.WindowClosed(gen) {
		t.Fatal("a suppressed watchMsg during the window must owe exactly one more read at close")
	}
}

func TestMutationLockWindowWithNoSuppressedEventOwesNoRead(t *testing.T) {
	var l MutationLock
	l.Begin()
	gen := l.End()
	if l.WindowClosed(gen) {
		t.Fatal("a window nothing arrived during must not owe a read")
	}
}

func TestMutationLockDoesNotSuppressWhenIdle(t *testing.T) {
	var l MutationLock
	if l.Suppress() {
		t.Fatal("Suppress must return false when the lock is neither busy nor in its window")
	}
}

func TestMutationLockWindowClosedIsOneShot(t *testing.T) {
	var l MutationLock
	l.Begin()
	gen := l.End()
	l.Suppress()
	if !l.WindowClosed(gen) {
		t.Fatal("expected the first WindowClosed to report the owed read")
	}
	if l.WindowClosed(gen) {
		t.Fatal("a second WindowClosed with the same gen must not owe a read again")
	}
}

func TestMutationLockStaleWindowGenerationIsInert(t *testing.T) {
	var l MutationLock
	l.Begin()
	staleGen := l.End()
	// A brand new mutation begins and ends before the old window's timer
	// ever fires — its own End() hands back a NEWER generation, and the
	// stale one must never act on its behalf.
	l.Begin()
	l.Suppress() // something arrives during the second mutation's own window setup path (busy)
	newGen := l.End()
	if staleGen == newGen {
		t.Fatal("generations must differ across separate Begin/End cycles")
	}
	if l.WindowClosed(staleGen) {
		t.Fatal("a stale generation's WindowClosed must be a no-op")
	}
	// The real (current) window can still resolve normally afterwards.
	l.Suppress()
	if !l.WindowClosed(newGen) {
		t.Fatal("the current generation must still resolve normally after a stale one was rejected")
	}
}

func TestMutationLockCancelReleasesWithoutOpeningAWindow(t *testing.T) {
	var l MutationLock
	l.Begin()
	l.Cancel()
	if l.Busy() {
		t.Fatal("Cancel must clear busy")
	}
	if l.Suppress() {
		t.Fatal("Cancel must not leave a window open for Suppress to act on")
	}
}

func TestMutationLockBeginResetsAnyDanglingWindowFromThePreviousMutation(t *testing.T) {
	var l MutationLock
	l.Begin()
	oldGen := l.End()
	l.Suppress() // a late event lands in the old window, before it is ever closed
	// A new mutation starts before the old window closes.
	if !l.Begin() {
		t.Fatal("Begin must succeed once the previous mutation ended")
	}
	// The stale window's own close must not fire a read on the new
	// mutation's behalf.
	if l.WindowClosed(oldGen) {
		t.Fatal("the superseded window must be inert once a newer mutation began")
	}
}
