package domain

// Argv is one invocation's verb and arguments — never the dispatcher word
// itself (`review`), and never a shell string (contracts/cli-
// invocation.md): "review" is what `git` consumes, so the CLI's own
// dispatcher only ever sees $1=<verb>.
type Argv struct {
	Verb string
	Args []string
}

// ProductActions is the 26 ids this client offers: the canonical's 27
// minus openAllChanges, which is not_in: [tui] (T006) — opening N diffs at
// once is not a gesture a multiplexer pane can hold, and the inventory's
// rows already open each diff one at a time.
var ProductActions = []string{
	"openEntry", "openChange", "showWhy", "next", "prev", "goToEntry",
	"refresh", "installCli", "continueReview", "startReview", "setBase",
	"setRemote", "abortReview", "saveReview", "finishReview", "undoFinish",
	"resumeFinish", "discardInventory", "cleanReview", "forgetReview",
	"previewEdits", "previewEditsStat", "compareReview", "walkthroughInit",
	"walkthroughBuild", "showCliLog",
}

// Actions mirrors ProductActions as a set, for O(1) membership checks
// (keymap_test.go uses it to confirm "refresh" is declared).
var Actions = func() map[string]bool {
	m := make(map[string]bool, len(ProductActions))
	for _, id := range ProductActions {
		m[id] = true
	}
	return m
}()

// HousekeepingKind is the ten ways `clean`/`forget` can be invoked from a
// panel control (cleanReview, discardInventory and forgetReview all funnel
// through this, the same grouping Visual Studio's ActionArgv.cs uses,
// because the argv shape — verb plus a small, fixed set of flag
// combinations — is identical across the three ids; what differs is only
// which control on which row offers which Kind).
type HousekeepingKind int

const (
	CleanOne HousekeepingKind = iota
	CleanKeepFixes
	CleanFixesOne
	CleanFixesOneAll
	CleanAll
	ForgetSavedOne
	ForgetSavedAll
	ForgetDeltaOne
	ForgetDeltaAll
	ForgetDeltaStale
	ForgetDraftOne
	ForgetDraftAll
	ForgetDraftReviewed
)

// HousekeepingAction is a `clean`/`forget` invocation's shape. Source is
// required by every *One kind and ignored by every *All/*Stale/*Reviewed
// kind.
type HousekeepingAction struct {
	Kind   HousekeepingKind
	Source string
}

// VerbForHousekeeping picks `clean` or `forget`.
func VerbForHousekeeping(kind HousekeepingKind) string {
	switch kind {
	case CleanOne, CleanKeepFixes, CleanFixesOne, CleanFixesOneAll, CleanAll:
		return "clean"
	default:
		return "forget"
	}
}

// ArgsForHousekeeping builds the args for one HousekeepingAction, per
// contracts/cli-invocation.md § Mutaciones.
func ArgsForHousekeeping(a HousekeepingAction) []string {
	switch a.Kind {
	case CleanOne:
		return []string{a.Source}
	case CleanKeepFixes:
		return []string{"--keep-fixes", a.Source}
	case CleanFixesOne:
		return []string{"--fixes-only", a.Source}
	case CleanFixesOneAll:
		// discardAllFixes ALWAYS runs --fixes-only with no branch, even with
		// the session closed: the argv cannot depend on a datum re-read on
		// every refresh, and clean's own scoping (bin/git-review-verbs/clean)
		// means bare --fixes-only never touches a live review/*.
		return []string{"--fixes-only"}
	case CleanAll:
		return []string{}
	case ForgetSavedOne:
		return []string{"--saved", a.Source}
	case ForgetSavedAll:
		return []string{"--saved", "--all"}
	case ForgetDeltaOne:
		return []string{"--delta", a.Source}
	case ForgetDeltaAll:
		return []string{"--delta", "--all"}
	case ForgetDeltaStale:
		return []string{"--delta", "--stale"}
	case ForgetDraftOne:
		return []string{"--draft", a.Source}
	case ForgetDraftAll:
		return []string{"--draft", "--all"}
	case ForgetDraftReviewed:
		return []string{"--draft", "--reviewed"}
	default:
		return nil
	}
}

// HousekeepingIsNetwork reports whether a housekeeping call needs the
// Network invocation class — only --delta --stale does, because it checks
// the remote first (contracts/cli-invocation.md § Timeouts).
func HousekeepingIsNetwork(kind HousekeepingKind) bool {
	return kind == ForgetDeltaStale
}

// ActionParams carries whatever a given action id needs to build its argv.
// Fields not relevant to the id being built are simply left at their zero
// value; BuildArgv reads only the ones its own case needs, the same
// discipline Visual Studio's ActionArgvMap.ActionToArgv follows with its
// discriminated ActionParams record.
type ActionParams struct {
	// startReview / startFromDraft
	Intent ReviewIntent
	// continueReview
	Source string
	// setBase / setRemote
	Name string
	// finishReview / resumeFinish
	OntoSource bool
	// undoFinish
	Force bool
	// compareReview
	CompareLayout              []string
	CompareLower, CompareUpper string
	// cleanReview / discardInventory / forgetReview
	Housekeeping HousekeepingAction
	// walkthroughInit
	WalkthroughForce bool
	// createGuide
	Team bool
}

// BuildArgv is the (action, params) -> argv table FR-014 requires as a
// closed list: an id missing here is an id this client cannot invoke, and
// an id here that the canonical does not declare is caught by
// actions_test.go and by scripts/check-client-product-surface.mjs's
// bidirectional sweep (T030).
//
// openEntry, openChange, goToEntry, installCli and showCliLog return
// ok=false: they are not `git review` invocations at all (the first two
// delegate straight to $EDITOR, goToEntry only picks an already-known entry
// without moving the CLI's cursor, installCli copies text or opens a URL,
// and showCliLog reads the in-memory invocation log). refresh returns the
// read that drives it (`status --porcelain`); which follow-up reads
// (`list`/`config`) that triggers is a host decision (T043), not part of
// this action's own argv.
func BuildArgv(action string, p ActionParams) (Argv, bool) {
	switch action {
	case "openEntry", "openChange", "goToEntry", "installCli", "showCliLog":
		return Argv{}, false
	case "refresh":
		return Argv{Verb: "status", Args: []string{"--porcelain"}}, true
	case "showWhy":
		return Argv{Verb: "status", Args: []string{"--why", p.Source}}, true
	case "next":
		return Argv{Verb: "next"}, true
	case "prev":
		return Argv{Verb: "prev"}, true
	case "continueReview":
		if p.Source == "" {
			return Argv{Verb: "continue"}, true
		}
		return Argv{Verb: "continue", Args: []string{p.Source}}, true
	case "startReview":
		return Argv{Verb: "start", Args: IntentToArgs(p.Intent)}, true
	case "setBase":
		return Argv{Verb: "config", Args: []string{"base", "--", p.Name}}, true
	case "setRemote":
		return Argv{Verb: "config", Args: []string{"remote", "--", p.Name}}, true
	case "abortReview":
		return Argv{Verb: "abort"}, true
	case "saveReview":
		return Argv{Verb: "save"}, true
	case "finishReview":
		if p.OntoSource {
			return Argv{Verb: "finish", Args: []string{"--onto-source"}}, true
		}
		return Argv{Verb: "finish"}, true
	case "undoFinish":
		// --force is NEVER the first choice: it is only ever appended after
		// the CLI's own stderr asks for it on a prior --abort.
		if p.Force {
			return Argv{Verb: "finish", Args: []string{"--abort", "--force"}}, true
		}
		return Argv{Verb: "finish", Args: []string{"--abort"}}, true
	case "resumeFinish":
		if p.OntoSource {
			return Argv{Verb: "finish", Args: []string{"--resume", "--onto-source"}}, true
		}
		return Argv{Verb: "finish", Args: []string{"--resume"}}, true
	case "discardInventory", "cleanReview", "forgetReview":
		return Argv{
			Verb: VerbForHousekeeping(p.Housekeeping.Kind),
			Args: ArgsForHousekeeping(p.Housekeeping),
		}, true
	case "previewEdits":
		return Argv{Verb: "preview"}, true
	case "previewEditsStat":
		return Argv{Verb: "preview", Args: []string{"--stat"}}, true
	case "compareReview":
		args := make([]string, 0, len(p.CompareLayout)+3)
		args = append(args, p.CompareLayout...)
		args = append(args, "--", p.CompareLower, p.CompareUpper)
		return Argv{Verb: "compare", Args: args}, true
	case "walkthroughInit":
		if p.WalkthroughForce {
			return Argv{Verb: "walkthrough", Args: []string{"init", "--force"}}, true
		}
		return Argv{Verb: "walkthrough", Args: []string{"init"}}, true
	case "walkthroughBuild":
		return Argv{Verb: "walkthrough", Args: []string{"build"}}, true
	default:
		return Argv{}, false
	}
}

// --- row controls with their own CLI call, not among the 27 ---------------

// CreateGuideArgs builds `walkthrough guide` / `walkthrough guide --team`.
func CreateGuideArgs(team bool) []string {
	if team {
		return []string{"guide", "--team"}
	}
	return []string{"guide"}
}

// DiscardGuideArgs builds `walkthrough guide --delete` — only ever the
// reviewer's own: the shared guide is a tracked file, and the CLI itself
// refuses `--delete --team`.
func DiscardGuideArgs() []string {
	return []string{"guide", "--delete"}
}

// StartFromDraftArgs is startFromDraft's argv: identical shape to
// startReview's, built from the same ReviewIntent (the draft's own
// recorded source/range choose the intent's fields).
func StartFromDraftArgs(intent ReviewIntent) []string {
	return IntentToArgs(intent)
}
