// Package host is the process/filesystem layer: everything internal/domain
// is forbidden from touching (os/exec, the terminal, fsnotify). This file is
// the ONE place in the whole tui/ tree allowed to export GIT_REVIEW_ADVICE
// (FR-009) — TestGitReviewAdviceExportedNowhereElse below sweeps every other
// .go file in the module and fails if it finds a second one.
package host

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// Result is one invocation's outcome: enough to derive a Situation (FR-012:
// never more than exit code and stdout/stderr) and enough to render one
// showCliLog row (FR-078: the log lives in memory only, see log.go).
type Result struct {
	Argv     []string // the full argv passed to exec, "git" included
	Cwd      string
	Stdout   string
	Stderr   string
	ExitCode int
	// TimedOut and SpawnFailed are mutually exclusive with a meaningful
	// ExitCode: contracts/cli-invocation.md's "exitCode=nil" on timeout,
	// expressed here as two booleans instead of a pointer so Result stays a
	// plain value type.
	TimedOut    bool
	SpawnFailed bool
	// ExecutableNotFound is the narrow SpawnFailed subtype backed by the
	// operating system's not-found error. Permission and other start errors
	// leave it false so a version probe cannot mistake them for CLI absence.
	ExecutableNotFound bool
	Duration           time.Duration
}

// decodeUTF8 is the "UTF-8 explícito en los tres sistemas operativos"
// FR-010 asks for: a child process's stdout/stderr arrives as raw bytes
// regardless of platform or console code page (these are pipes, never a
// console), and the CLI itself only ever emits UTF-8 — but a byte sequence
// this client did not expect (a corrupted pipe, a future record this parser
// cannot read) becomes U+FFFD rather than an invalid Go string silently
// propagating into a terminal write.
func decodeUTF8(b []byte) string {
	if utf8.Valid(b) {
		return string(b)
	}
	return strings.ToValidUTF8(string(b), "�")
}

// runProcess is the one low-level spawn point every invocation in this
// package funnels through. It takes the binary name as a parameter purely
// so invoke_test.go can exercise SpawnFailed/TimedOut against a name that
// is not "git" without any real process taking 15s to time out — the two
// PUBLIC entry points below (InvokeReview, InvokeSupportGit) are the only
// callers, and both hardcode "git" (FR-007): there is no exported way to
// pick a different binary.
func runProcess(ctx context.Context, name string, argv []string, extraEnv []string) Result {
	cwd, _ := os.Getwd() // best-effort, only used for the invocation log
	cmd := exec.CommandContext(ctx, name, argv...)
	cmd.Env = append(os.Environ(), extraEnv...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	start := time.Now()
	err := cmd.Run()
	dur := time.Since(start)

	res := Result{
		Argv:     append([]string{name}, argv...),
		Cwd:      cwd,
		Stdout:   decodeUTF8(stdout.Bytes()),
		Stderr:   decodeUTF8(stderr.Bytes()),
		Duration: dur,
	}

	// Checked BEFORE inspecting err: whether the process never got to start
	// or was killed mid-flight by CommandContext's own cancellation, ctx.Err
	// is what tells the two apart from an ordinary exit — a timeout is never
	// "no CLI" (contracts/cli-invocation.md § Timeouts).
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		res.TimedOut = true
		return res
	}
	return resultFromProcessError(res, err)
}

// resultFromProcessError applies the exit and spawn-error policy shared by
// buffered invocations and terminal-owned interactive commands.
func resultFromProcessError(res Result, err error) Result {
	if err == nil {
		res.ExitCode = 0
		return res
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		res.ExitCode = exitErr.ExitCode()
		return res
	}
	// Could not even start: binary not found, permission denied, and so on.
	res.SpawnFailed = true
	res.ExecutableNotFound = errors.Is(err, exec.ErrNotFound) || errors.Is(err, os.ErrNotExist)
	return res
}

// gitReviewAdviceEnv is appended to every invocation this file makes,
// review or plain git — harmless for the latter, and keeping it
// unconditional is what makes "one file, one export" a single line to
// verify instead of two call sites that both need to remember it.
const gitReviewAdviceEnv = "GIT_REVIEW_ADVICE=0"

// InteractiveReviewInvocation is a terminal-owned `git review` command. Cmd
// goes to tea.ExecProcess so the child gets the real TTY; Complete must be
// called with ExecProcess's error once the child exits to apply the normal
// invocation-result and logging policy.
type InteractiveReviewInvocation struct {
	Cmd       *exec.Cmd
	startedAt time.Time
}

// InteractiveReviewCmd builds an interactive `git review <verb> <args...>`
// invocation. Unlike InvokeReview it deliberately has no buffered output or
// timeout, because the terminal UI owns its streams and lifetime. Its command
// environment, working directory, completion classification, and log entry
// otherwise share the central process policy.
func InteractiveReviewCmd(verb string, args []string, dir string) InteractiveReviewInvocation {
	argv := make([]string, 0, len(args)+2)
	argv = append(argv, "review", verb)
	argv = append(argv, args...)
	cmd := exec.Command("git", argv...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), gitReviewAdviceEnv)
	return InteractiveReviewInvocation{Cmd: cmd, startedAt: time.Now()}
}

// Complete records the terminal child's completion using the same exit and
// spawn-error policy as runProcess. Tea's ExecProcess already ran Cmd, so
// there is intentionally no second execution here.
func (i InteractiveReviewInvocation) Complete(err error) Result {
	res := resultFromProcessError(Result{
		Argv:     append([]string(nil), i.Cmd.Args...),
		Cwd:      i.Cmd.Dir,
		Duration: time.Since(i.startedAt),
	}, err)
	appendResultLog(res, i.startedAt)
	return res
}

func appendResultLog(res Result, startedAt time.Time) {
	appendLog(LogEntry{
		Argv: res.Argv, Cwd: res.Cwd, Duration: res.Duration,
		ExitCode: res.ExitCode, TimedOut: res.TimedOut, SpawnFailed: res.SpawnFailed,
		Stderr: res.Stderr, StartedAt: startedAt,
	})
}

// InvokeReview runs `git review <verb> <args...>` — never the dispatcher
// directly (FR-007) and never with a configurable path to it (FR-008): the
// binary name is the literal "git", always. ctx's deadline is intersected
// with the verb's own class timeout (contracts/cli-invocation.md § Timeouts)
// via context.WithTimeout, so a caller in a test can impose a much shorter
// deadline than the class would without this function knowing it.
func InvokeReview(ctx context.Context, verb string, args []string) Result {
	class := domain.ClassForVerb(verb, args)
	runCtx, cancel := context.WithTimeout(ctx, time.Duration(class.TimeoutMillis())*time.Millisecond)
	defer cancel()

	argv := make([]string, 0, len(args)+2)
	argv = append(argv, "review", verb)
	argv = append(argv, args...)

	extraEnv := []string{gitReviewAdviceEnv}
	if class == domain.Network {
		extraEnv = append(extraEnv, networkEnv()...)
	}

	res := runProcess(runCtx, "git", argv, extraEnv)
	appendResultLog(res, time.Now().Add(-res.Duration))
	return res
}

// InvokeSupportGit runs a plain `git <args...>` — never `git review`
// (contracts/cli-invocation.md § Git de apoyo): rev-parse, diff
// --name-status, diff-tree. Always class SupportGit (30s), never Network.
func InvokeSupportGit(ctx context.Context, args []string) Result {
	runCtx, cancel := context.WithTimeout(ctx, time.Duration(domain.SupportGit.TimeoutMillis())*time.Millisecond)
	defer cancel()

	res := runProcess(runCtx, "git", args, []string{gitReviewAdviceEnv})
	appendResultLog(res, time.Now().Add(-res.Duration))
	return res
}

// --- in-memory invocation log (T039, FR-078) --------------------------------

// LogEntry is one showCliLog row: command, cwd, duration, exit, timedOut,
// stderr. Never written to disk — it lives only in this process's memory
// and dies with it.
type LogEntry struct {
	Argv        []string
	Cwd         string
	Duration    time.Duration
	ExitCode    int
	TimedOut    bool
	SpawnFailed bool
	Stderr      string
	StartedAt   time.Time
}

// logMax and logStderrMax bound what a long-lived pane can accumulate. A
// TUI is not a command that exits: a pane left open all day, with the
// watcher accelerating a read on every ref and config change, appends
// several entries per refresh forever. The other clients already have their
// bound — Visual Studio's CliLogSink is a 500-line ring, VS Code hands the
// text to an OutputChannel that trims and caps stderr at 2000 chars — and
// this is the same bound in the same two places.
//
// Dropping the OLDEST is the right end to drop: showCliLog exists to answer
// "what did the thing I just pressed run", and the entry that answers it is
// always the newest.
const (
	logMax       = 500
	logStderrMax = 2000
	logTruncated = "\n… (truncated)"
)

// truncateStderr cuts at a RUNE boundary, never mid-sequence: decodeUTF8
// went to the trouble of guaranteeing the string is valid UTF-8, and a naive
// byte slice would hand the renderer a broken tail it would draw as U+FFFD.
func truncateStderr(s string) string {
	if len(s) <= logStderrMax {
		return s
	}
	cut := logStderrMax
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut] + logTruncated
}

var logMu sync.Mutex
var log []LogEntry

func appendLog(e LogEntry) {
	e.Stderr = truncateStderr(e.Stderr)
	logMu.Lock()
	defer logMu.Unlock()
	log = append(log, e)
	if len(log) > logMax {
		// Re-slice into a fresh backing array rather than log[1:]: the latter
		// keeps the whole original array alive behind a moving window, so the
		// bound would cap what is VISIBLE without capping what is retained.
		trimmed := make([]LogEntry, logMax)
		copy(trimmed, log[len(log)-logMax:])
		log = trimmed
	}
}

// InvocationLog returns a copy of every invocation recorded so far, oldest
// first. Safe for concurrent use; the copy means a caller cannot mutate the
// package's own history.
func InvocationLog() []LogEntry {
	logMu.Lock()
	defer logMu.Unlock()
	out := make([]LogEntry, len(log))
	copy(out, log)
	return out
}

// ResetInvocationLogForTest clears the in-memory log. Test-only: production
// code has no reason to ever forget history mid-run.
func ResetInvocationLogForTest() {
	logMu.Lock()
	defer logMu.Unlock()
	log = nil
}
