package host

import "os"

// AskpassSentinelEnv is the variable `main` checks, as the very first thing
// it does, to recognize it is being run AS an askpass helper rather than as
// the TUI itself (contracts/cli-invocation.md § Entorno de red). git invokes
// GIT_ASKPASS/SSH_ASKPASS as a plain child process when it needs a
// credential; pointing both at this same executable with the sentinel set
// means that child process is this binary re-invoked, and it has to exit
// before touching the terminal in any way — a credential prompt stuck in a
// pane the user cannot see is a pane that looks hung forever.
const AskpassSentinelEnv = "GIT_REVIEW_UI_ASKPASS"

// networkEnv is the anti-prompt environment layered onto a Network-class
// invocation only (FR-011): GIT_TERMINAL_PROMPT=0 so git never falls back to
// its own terminal prompt, and GIT_ASKPASS/SSH_ASKPASS pointed at this
// program's own executable so that if something still tries to ask, it hits
// the sentinel exit instead of a live prompt. os.Executable() failing is not
// fatal — GIT_TERMINAL_PROMPT=0 alone already stops git from prompting the
// terminal directly; the askpass pair is defense in depth for the few git
// operations that go through GIT_ASKPASS even with the terminal prompt off.
func networkEnv() []string {
	env := []string{"GIT_TERMINAL_PROMPT=0"}
	exe, err := os.Executable()
	if err != nil {
		return env
	}
	return append(env,
		"GIT_ASKPASS="+exe,
		"SSH_ASKPASS="+exe,
		AskpassSentinelEnv+"=1",
	)
}

// IsAskpassSentinel reports whether this process was launched as the
// askpass/ssh-askpass stand-in rather than as the TUI proper. main() calls
// this before doing anything else — before reading a single byte of
// terminal state — and exits non-zero without printing anything when it is
// true (contracts/cli-invocation.md, User Story 2).
func IsAskpassSentinel() bool {
	return os.Getenv(AskpassSentinelEnv) == "1"
}
