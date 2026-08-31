package host

import "context"

// Watcher is disparador 2's whole abstraction (contracts/refresh.md § Cómo
// se apaga entera): a real fsnotify-backed implementation and a no-op
// stand-in that never fires, chosen exactly once in cmd/git-review-ui/
// main.go. "No es un flag chequeado en veinte lugares: es una interface con
// dos implementaciones" — everything downstream of Start only ever sees a
// channel; it has no way to tell which implementation is feeding it.
//
// Start and Rebuild take the three raw ingredients BuildWatchSet needs
// (gitDir, gitCommonDir, draftPaths) rather than a pre-built
// domain.WatchSet. That is a deliberate departure from the illustrative
// signature in contracts/refresh.md: the real implementation has to be
// able to recompute its own watched set WITHOUT a caller in the loop the
// moment it notices a directory came or went inside something it already
// watches (T057 — "Rebuild antes de emitir" happens INSIDE the debounce
// firing, triggered by the watcher itself, never by an external call for
// that case). Keeping the three ingredients in the interface — instead of
// stashing them only in fsnotifyWatcher's private state — is what lets an
// external caller drive a rebuild for the OTHER reason the contract lists
// (the draft paths a later read reported changed) through the exact same
// method, with BuildWatchSet itself staying the single place that turns
// them into a concrete set.
type Watcher interface {
	// Start begins watching the closure BuildWatchSet(gitDir, gitCommonDir,
	// draftPaths) resolves, and returns a channel that receives one value
	// per coalesced batch (contracts/refresh.md § Debounce y coalescencia:
	// no payload, ever — always struct{}{}). Start must return promptly:
	// T061/SC-002 needs "opened and idle" to cost zero CLI invocations, not
	// zero setup time, and the caller is expected to be able to enter its
	// own event loop right after this returns.
	Start(ctx context.Context, gitDir, gitCommonDir string, draftPaths []string) (<-chan struct{}, error)
	// Rebuild recomputes BuildWatchSet(gitDir, gitCommonDir, draftPaths)
	// and applies it INCREMENTALLY against whatever is currently watched:
	// it adds fsnotify watches for directories that are new and removes
	// the ones for directories that dropped out, but never tears down and
	// re-creates the underlying OS watch handle itself (contracts/
	// refresh.md § Cómo se arma y se rearma — "nunca tira el watcher
	// entero"). Safe to call before Start has ever run (a no-op then).
	Rebuild(gitDir, gitCommonDir string, draftPaths []string) error
	// Stop releases every OS watch handle and stops the background loop.
	// Safe to call more than once; a second call is a no-op. Safe to call
	// even if Start was never called.
	Stop() error
}

// nopWatcher is disparador 2 turned off entirely: Start hands back a
// channel that is never sent to and never closed, Rebuild and Stop do
// nothing. This is the DEFAULT for the whole test suite — main.go only
// swaps in the real fsnotifyWatcher when GIT_REVIEW_UI_WATCH=1 — which is
// what proves FR-063/SC-016 ("the watcher's absence never changes
// correctness") BY CONSTRUCTION: every Phase 3/4 test that exists today,
// and everything Phase 6+ adds, runs against exactly this implementation,
// never a dedicated "watcher off" test. If any of them needed the watcher
// to fire in order to pass, the whole suite would go red, not one test
// (tasks.md T054/T062).
//
// GIT_REVIEW_UI_WATCH is a support/suite lever, not a `reviewui.*` key:
// turning the acceleration mechanism off is not a reviewer preference, and
// putting it under reviewui.* would make it product surface that the three
// IDE clients' contract would then have to account for. See
// cmd/git-review-ui/main.go for where the one read of it lives.
type nopWatcher struct{}

// NewNopWatcher constructs the no-op Watcher.
func NewNopWatcher() Watcher { return nopWatcher{} }

func (nopWatcher) Start(context.Context, string, string, []string) (<-chan struct{}, error) {
	return make(chan struct{}), nil
}

func (nopWatcher) Rebuild(string, string, []string) error { return nil }

func (nopWatcher) Stop() error { return nil }
