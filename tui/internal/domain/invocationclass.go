package domain

// InvocationClass picks an invocation's timeout and, for Network, the
// anti-prompt environment (contracts/cli-invocation.md § Timeouts,
// data-model.md § InvocationClass). It never dictates the environment for
// Read/LocalMutation/SupportGit — only Network does (FR-011).
type InvocationClass int

const (
	// Read: 15s. Default class — reads AND config writes (`config
	// base|remote` is a config write, not a ref move, so it stays Read,
	// the same rule the other three clients use).
	Read InvocationClass = iota
	// LocalMutation: 120s.
	LocalMutation
	// Network: 300s. `start`, and `forget` when its args carry --stale.
	Network
	// SupportGit: 30s. The plain `git` calls that are not git-review at
	// all (rev-parse, diff --name-status, diff-tree).
	SupportGit
)

// TimeoutMillis is the class's timeout in milliseconds.
func (c InvocationClass) TimeoutMillis() int {
	switch c {
	case LocalMutation:
		return 120_000
	case Network:
		return 300_000
	case SupportGit:
		return 30_000
	default:
		return 15_000
	}
}

var localMutationVerbs = map[string]bool{
	"finish": true, "save": true, "abort": true, "continue": true,
	"next": true, "prev": true, "clean": true, "forget": true,
	"compare": true, "walkthrough": true, "preview": true,
}

// ClassForVerb classifies a `git review <verb> <args>` invocation. An
// unknown verb falls to Read, the same rule invoke.ts uses — the default is
// the SHORT timeout, so a verb this client does not recognize fails fast
// instead of hanging for five minutes.
//
// `forget` is LocalMutation by default and ONLY Network when args carries
// `--stale` (it checks the remote first); every other verb's class does
// not depend on its args at all.
func ClassForVerb(verb string, args []string) InvocationClass {
	switch verb {
	case "start":
		return Network
	case "forget":
		for _, a := range args {
			if a == "--stale" {
				return Network
			}
		}
		return LocalMutation
	case "status", "list", "config", "--version":
		return Read
	default:
		if localMutationVerbs[verb] {
			return LocalMutation
		}
		return Read
	}
}
