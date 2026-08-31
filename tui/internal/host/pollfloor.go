package host

import (
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// PollSecondsConfig reads `reviewui.pollseconds` defensively — the Go
// mirror of the shell verbs' `git config --get ... || true`: absent,
// unparsable, zero or negative all read as "off", never as an error and
// NEVER as a default (FR-039). This key is the opt-in floor for agujero 5
// (a network mount whose inotify never fires): it is not a reviewer
// preference with a house default the way most `reviewui.*` keys could be.
func PollSecondsConfig() (time.Duration, bool) {
	out, err := exec.Command("git", "config", "--get", "reviewui.pollseconds").Output()
	if err != nil {
		return 0, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(out)))
	if err != nil || n <= 0 {
		return 0, false
	}
	return time.Duration(n) * time.Second, true
}

// PollFloor is FR-039's "piso, no poll": Due() only ever reports true after
// Interval has elapsed with NO Reset() call in between. Every read this
// client performs — from ANY of the four triggers, or from the floor's own
// firing — is expected to call Reset() right after, which is what makes
// "con la vigilancia funcionando, no agrega ni una invocación" true: a
// floor that keeps getting reset before it is ever due never asks for
// anything.
type PollFloor struct {
	Interval time.Duration

	mu   sync.Mutex
	next time.Time
}

// NewPollFloor builds an armed floor: Due() reports false until Interval
// has elapsed from construction, exactly as if a read had just happened.
func NewPollFloor(interval time.Duration) *PollFloor {
	return &PollFloor{Interval: interval, next: time.Now().Add(interval)}
}

// Reset re-arms the floor from now. Called after every read, regardless of
// what triggered it.
func (f *PollFloor) Reset() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.next = time.Now().Add(f.Interval)
}

// Due reports whether Interval has elapsed since the last Reset (or since
// construction, if Reset was never called). A caller that acts on a true
// Due() is expected to trigger a read and then call Reset() — that read
// IS a read, so it re-arms the floor exactly like any other.
func (f *PollFloor) Due(now time.Time) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return !now.Before(f.next)
}
