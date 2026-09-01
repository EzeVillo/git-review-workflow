// fsnotify is imported in exactly this one file of the whole tui/ tree —
// fsnotify_boundary_test.go enforces it. Everything this file does funnels
// down to one signal: "something changed under a watched root, go re-read
// via porcelain" (contracts/refresh.md § Debounce y coalescencia). It never
// opens, reads or parses a single byte of what it watches.
package host

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/fsnotify/fsnotify"
)

// fsnotifyWatcher is the real Watcher. One instance owns exactly one
// *fsnotify.Watcher for its whole lifetime — Rebuild only ever adds/removes
// individual directory watches on it, it is never closed and replaced
// (contracts/refresh.md: "nunca tira el watcher entero").
type fsnotifyWatcher struct {
	mu      sync.Mutex
	fsw     *fsnotify.Watcher
	watched map[string]string // absolute dir path -> canonical NameFilter key currently applied
	out     chan struct{}
	cancel  context.CancelFunc
	wg      sync.WaitGroup

	// The last ingredients BuildWatchSet was called with — remembered so
	// the debounce loop can recompute the closure ON ITS OWN the moment it
	// notices a directory came or went, with no caller involved (T057).
	gitDir       string
	gitCommonDir string
	draftPaths   []string
	// ignoreDirWriteUntil absorbs the Windows backend's synthetic directory
	// WRITE immediately after a self-rebuild adds a newly created directory.
	// Child CREATE/REMOVE events remain visible through their own watches.
	ignoreDirWriteUntil map[string]time.Time
}

// NewFsnotifyWatcher constructs the real, fsnotify-backed Watcher.
func NewFsnotifyWatcher() Watcher { return &fsnotifyWatcher{} }

func (w *fsnotifyWatcher) Start(ctx context.Context, gitDir, gitCommonDir string, draftPaths []string) (<-chan struct{}, error) {
	fsw, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}
	runCtx, cancel := context.WithCancel(ctx)

	w.mu.Lock()
	w.fsw = fsw
	w.watched = map[string]string{}
	w.out = make(chan struct{})
	w.cancel = cancel
	w.ignoreDirWriteUntil = map[string]time.Time{}
	w.gitDir, w.gitCommonDir, w.draftPaths = gitDir, gitCommonDir, append([]string(nil), draftPaths...)
	out := w.out
	w.mu.Unlock()

	w.applySet(BuildWatchSet(gitDir, gitCommonDir, draftPaths), false)

	w.wg.Add(1)
	go w.loop(runCtx)

	return out, nil
}

// Rebuild is the EXTERNAL half of "cuándo se rehace": a caller that noticed
// the draft paths a read reported changed calls this with the fresh
// values. It shares one code path (applySet) with the watcher's own
// internal rebuild below, so both ends of the contract behave identically.
func (w *fsnotifyWatcher) Rebuild(gitDir, gitCommonDir string, draftPaths []string) error {
	w.mu.Lock()
	if w.fsw == nil {
		w.mu.Unlock()
		return nil // Start was never called: nothing to rebuild yet
	}
	w.gitDir, w.gitCommonDir, w.draftPaths = gitDir, gitCommonDir, append([]string(nil), draftPaths...)
	w.mu.Unlock()

	w.applySet(BuildWatchSet(gitDir, gitCommonDir, draftPaths), false)
	return nil
}

// selfRebuild is the INTERNAL half: triggered from the debounce loop when
// the coalesced batch itself contained a directory create/delete, using
// whichever (gitDir, gitCommonDir, draftPaths) this instance was last given
// — never a fresh git invocation, since re-walking the same three roots is
// what naturally discovers a subdirectory that just appeared (or drops one
// that just vanished).
func (w *fsnotifyWatcher) selfRebuild() {
	w.mu.Lock()
	gitDir, gitCommonDir, draftPaths := w.gitDir, w.gitCommonDir, w.draftPaths
	w.mu.Unlock()
	w.applySet(BuildWatchSet(gitDir, gitCommonDir, draftPaths), true)
}

// applySet diffs set against whatever is currently registered on the OS
// watcher and applies only the difference: fsw.Add for a new directory,
// fsw.Remove for one that dropped out. It never calls fsw.Close/re-creates
// fsw — that is the "incremental, nunca tira el watcher entero" guarantee
// (T057), shared by Start's initial application, the external Rebuild, and
// the watcher's own selfRebuild.
func (w *fsnotifyWatcher) applySet(set domain.WatchSet, suppressInitialDirWrite bool) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.fsw == nil {
		return
	}

	want := make(map[string]string, len(set.Dirs))
	for _, d := range set.Dirs {
		want[d.Path] = d.NameFilter
	}

	for path := range w.watched {
		if _, ok := want[path]; !ok {
			_ = w.fsw.Remove(path) // best-effort: a directory already gone errors harmlessly
			delete(w.watched, path)
			delete(w.ignoreDirWriteUntil, path)
		}
	}
	for path, filter := range want {
		if _, already := w.watched[path]; already {
			w.watched[path] = filter // the union of filters may have grown
			continue
		}
		if err := w.fsw.Add(path); err != nil {
			continue // FR-064: a root gone between BuildWatchSet and Add is not fatal
		}
		w.watched[path] = filter
		if suppressInitialDirWrite {
			w.ignoreDirWriteUntil[path] = time.Now().Add(domain.DebounceCeilingMillis * time.Millisecond)
		}
	}
}

func (w *fsnotifyWatcher) Stop() error {
	w.mu.Lock()
	cancel := w.cancel
	fsw := w.fsw
	w.mu.Unlock()
	if cancel == nil {
		return nil // Start was never called
	}
	cancel()
	w.wg.Wait()
	return fsw.Close()
}

// loop is the whole debounce/coalescence/rebuild state machine (contracts/
// refresh.md § Debounce y coalescencia). It is the ONLY goroutine that
// reads fsw.Events/fsw.Errors, mutates the debounce/ceiling timers, or
// sends on out — no locking needed for those, only applySet/selfRebuild's
// access to shared fields goes through w.mu.
func (w *fsnotifyWatcher) loop(ctx context.Context) {
	defer w.wg.Done()

	var debounce, ceiling *time.Timer
	defer func() {
		if debounce != nil {
			debounce.Stop()
		}
		if ceiling != nil {
			ceiling.Stop()
		}
	}()

	timerC := func(t *time.Timer) <-chan time.Time {
		if t == nil {
			return nil // a nil channel blocks forever in select — exactly "not armed"
		}
		return t.C
	}

	pending := false
	rebuildNeeded := false

	arm := func() {
		if debounce != nil {
			debounce.Stop()
		}
		debounce = time.NewTimer(domain.DebounceMillis * time.Millisecond)
		if ceiling == nil {
			// The ceiling starts on the FIRST event of a burst and is
			// never reset by later ones in the same burst — that is what
			// guarantees at least one flush per second under continuous
			// writes (contracts/refresh.md § La ráfaga de HEAD).
			ceiling = time.NewTimer(domain.DebounceCeilingMillis * time.Millisecond)
		}
	}

	fire := func() {
		pending = false
		if debounce != nil {
			debounce.Stop()
			debounce = nil
		}
		if ceiling != nil {
			ceiling.Stop()
			ceiling = nil
		}
		if rebuildNeeded {
			rebuildNeeded = false
			w.selfRebuild() // T057: Rebuild BEFORE emitting, always
		}
		select {
		case w.out <- struct{}{}:
		case <-ctx.Done():
		}
	}

	for {
		select {
		case <-ctx.Done():
			return

		case ev, ok := <-w.fsw.Events:
			if !ok {
				return
			}
			relevant, dirChange := w.classify(ev)
			if !relevant {
				continue
			}
			if dirChange {
				rebuildNeeded = true
			}
			pending = true
			arm()

		case _, ok := <-w.fsw.Errors:
			if !ok {
				return
			}
			// A watcher-internal error is exactly agujero 5's shape (best
			// effort, fails in silence): never surfaced, never retried
			// specially — the other three triggers and the poll floor are
			// what compensate.

		case <-timerC(debounce):
			if pending {
				fire()
			}

		case <-timerC(ceiling):
			if pending {
				fire()
			} else {
				ceiling.Stop()
				ceiling = nil
			}
		}
	}
}

// classify decides, for one raw fsnotify event, whether it counts towards
// the coalesced signal at all (relevant) and whether it specifically
// signals a directory appearing or disappearing inside a watched root
// (dirChange) — the ONLY thing that ever asks for a Rebuild (T057). It
// never reads the file's content, only its name and, for Create, whether
// the path IS now a directory.
func (w *fsnotifyWatcher) classify(ev fsnotify.Event) (relevant, dirChange bool) {
	if ev.Op == fsnotify.Write {
		w.mu.Lock()
		ignoreUntil, freshlyAdded := w.ignoreDirWriteUntil[filepath.Clean(ev.Name)]
		if freshlyAdded {
			delete(w.ignoreDirWriteUntil, filepath.Clean(ev.Name))
		}
		w.mu.Unlock()
		if freshlyAdded && time.Now().Before(ignoreUntil) {
			return false, false
		}
	}

	dir := filepath.Dir(ev.Name)
	name := filepath.Base(ev.Name)

	w.mu.Lock()
	filter, watched := w.watched[dir]
	w.mu.Unlock()
	if !watched {
		return false, false
	}

	if ev.Op&fsnotify.Create != 0 {
		if info, err := os.Stat(ev.Name); err == nil && info.IsDir() {
			return true, true
		}
		// A file Create — or a Create for something already gone again by
		// the time it could be stat'd — is judged by name, same as any
		// other file-level event below.
		return matchesFilter(name, filter), false
	}

	if ev.Op&(fsnotify.Remove|fsnotify.Rename) != 0 {
		if filter == "" {
			// An unfiltered directory (RootRefs, RootReftable): the entry
			// that just disappeared could have been a subdirectory, and it
			// can no longer be stat'd to check — treated conservatively as
			// a possible closure change. A spurious extra Rebuild costs
			// one process; missing a real one could leave a vanished
			// subtree "watched" forever, or a real new one unwatched.
			return true, true
		}
		if matchesFilter(name, filter) {
			return true, true
		}
		// A FILTERED directory's Remove/Rename on a name the filter does
		// NOT care about is exactly the other half of git's own atomic
		// replace: "config" or "HEAD" appears via the Create branch above
		// (the rename's destination); the SOURCE name moving away
		// ("config.lock", "HEAD.lock") must not count a second time, or
		// disparador 2 would fire twice for one mutation.
		return false, false
	}

	return matchesFilter(name, filter), false
}

// matchesFilter applies one directory's canonical NameFilter (nameFilterKey
// in watchset.go) to a single filename. "" means unfiltered (RootRefs,
// RootReftable): everything inside counts.
func matchesFilter(name, filterKey string) bool {
	if filterKey == "" {
		return true
	}
	for _, want := range strings.Split(filterKey, "|") {
		if want == "*.md" {
			if strings.HasSuffix(name, ".md") {
				return true
			}
			continue
		}
		if want == name {
			return true
		}
	}
	return false
}
