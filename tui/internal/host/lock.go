package host

import "time"

// SilenceWindow is contracts/refresh.md's post-mutation grace period: 600ms
// (debounce 200 + techo 1s/2 + gracia) during which the verb's OWN
// late-arriving file events are absorbed without costing a repaint —
// domain.PanelModel is comparable by value, so re-reading identical state
// costs a process but never a frame (SC-004).
const SilenceWindow = 600 * time.Millisecond

// MutationLock is depth 1 (contracts/refresh.md § "El lock y la ventana de
// silencio", User Story 5 escenario 6): a second mutation while one is
// already running is DISCARDED with a notice, never queued — queuing it
// would run an intent against a state that changed while it waited.
//
// It also owns disparador 2's suppression: only watchMsg (file events) are
// ever passed through Suppress — contracts/refresh.md's own table marks
// FocusMsg and the refresh key as NOT suppressed by the lock, on purpose, so
// a revisor is never stuck ignoring their own keypress just because a
// mutation happens to be running.
//
// Every method is a value transition over plain fields — no goroutines, no
// channels, no I/O — which is what lets internal/ui hold one by value on its
// own Model and test the whole thing without a real clock. gen exists
// purely so a silence-window timer armed by an EARLIER mutation can be told
// it is stale once a NEWER one has already begun and ended (the same
// gen-guard shape internal/ui/program.go's poll floor already uses for the
// same reason).
type MutationLock struct {
	busy     bool
	inWindow bool
	pending  bool
	gen      int
}

// Begin acquires the lock for a new mutation. false means DISCARD: a
// mutation is already running and the caller must show a notice, never
// queue this one. A successful Begin always closes out whatever window was
// still open from a PREVIOUS mutation — that mutation's own end already
// produced its one guaranteed read, and this new mutation's own end will
// open a fresh window that supersedes it.
func (l *MutationLock) Begin() bool {
	if l.busy {
		return false
	}
	l.busy = true
	l.inWindow = false
	l.pending = false
	l.gen++
	return true
}

// Cancel gives back a lock Begin() just acquired without ever spawning a
// process — the StateToken revalidation inside the lock (contracts/
// refresh.md, right before the spawn) found stale state. There is no
// process running and therefore no late-arriving event to wait out, so
// Cancel never opens the silence window End() would.
func (l *MutationLock) Cancel() {
	l.busy = false
	l.inWindow = false
	l.pending = false
}

// Busy reports whether a mutation is currently running — the same bit
// domain.PanelModel.Busy is projected from on every read.
func (l *MutationLock) Busy() bool { return l.busy }

// Suppress is called for every watchMsg (disparador 2, and ONLY that
// trigger — contracts/refresh.md's table). While busy, or while the grace
// window opened by End() is still open, it returns true — the caller must
// discard the signal without reading — and remembers that something
// arrived, so the window's own close can decide whether it owes one more
// read. Outside both, it returns false: nothing to suppress, the caller
// reads normally.
func (l *MutationLock) Suppress() bool {
	if !l.busy && !l.inWindow {
		return false
	}
	l.pending = true
	return true
}

// End marks the verb's own process as finished: busy drops immediately (a
// new mutation may begin right away) and the grace window opens. The
// returned generation is what a later WindowClosed call must present back —
// a window from a mutation that already ended must never act on behalf of a
// newer one that started before this window's timer fired.
func (l *MutationLock) End() int {
	l.busy = false
	l.inWindow = true
	l.pending = false
	return l.gen
}

// WindowClosed reports whether the window ending at gen owes one more read:
// true only when a watchMsg was suppressed WHILE that specific window was
// open (contracts/refresh.md: "si hubo disparos descartados, una lectura
// más"). A stale gen — superseded by a newer Begin/End before this timer
// fired — is inert.
func (l *MutationLock) WindowClosed(gen int) bool {
	if gen != l.gen {
		return false
	}
	needsRead := l.inWindow && l.pending
	l.inWindow = false
	l.pending = false
	return needsRead
}
