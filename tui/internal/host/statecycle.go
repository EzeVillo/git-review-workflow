package host

import (
	"context"
	"strings"
	"sync"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// ReadResult is one full read cycle's outcome: the derived Situation plus
// whichever raw parses actually applied to it. Has* flags exist because
// `list`/`config` are only ever invoked for no-review/finish-pending
// (contracts/cli-invocation.md § Lecturas de estado) — a caller must not
// read Branches/Config and assume they are populated just because the field
// exists on the struct.
type ReadResult struct {
	Guard           string
	ContinueGuard   string
	SaveState       bool
	NavigationState bool
	WhyIncluded     bool
	DetailsPending  bool
	Comments        string
	CommentsError   string
	CommentsLoading bool
	Situation       domain.Situation

	Status    domain.PorcelainResult
	HasStatus bool

	Branches []domain.BranchRecord
	Fixes    []domain.FixesRecord
	HasList  bool

	Config    domain.ConfigPorcelainResult
	HasConfig bool

	Why      string
	WhyState domain.WhyState

	Stderr string
}

// ReadState runs one full read cycle, from "is this even a repository" down
// to `--why` when the walked entry calls for it. Every step re-derives from
// scratch — nothing here is cached across calls — which is what lets
// cli-missing/cli-outdated/error be reported fresh on every read instead of
// repainted from memory (contracts/tui-surface.md): installing the CLI and
// pressing `r` has to be able to walk the panel out of cli-missing, and that
// only works if the version probe runs again every time.
func ReadState(ctx context.Context, cwd, minVersion string) ReadResult {
	return ReadDetails(ctx, ReadPrimaryState(ctx, cwd, minVersion))
}

// ReadPrimaryState returns the review before comments and explanatory prose.
// Both remain explicitly pending until the independent details read completes.
func ReadPrimaryState(ctx context.Context, cwd, minVersion string) ReadResult {
	_, _, ok := ResolveGitDirs(ctx, cwd)
	if !ok {
		// T100: the panel's own actionable copy (per_client_strings.
		// no_single_root.tui), not git rev-parse's raw "fatal: not a git
		// repository..." -- the same substitution the other three clients
		// make (ReviewStateManager.cs / GitReviewService.kt / state.ts all
		// write their own no_single_root text into Stderr rather than
		// whatever the host layer originally reported), so the panel never
		// draws a blank error screen.
		return ReadResult{Situation: domain.SituationForMissingRepo(), Stderr: domain.NoSingleRoot}
	}

	outcome, vRes := ProbeVersion(ctx)
	if situation, ok := domain.SituationFromVersionProbe(outcome, minVersion); !ok {
		return ReadResult{Situation: situation, Stderr: vRes.Stderr}
	}

	statusRes := InvokeReview(ctx, "status", []string{"--porcelain"})
	parsed, parseOK := domain.ParsePorcelain(statusRes.Stdout)
	statusOutcome := domain.StatusOutcome{
		TimedOut:          statusRes.TimedOut,
		SpawnFailed:       statusRes.SpawnFailed,
		ExitCode:          statusRes.ExitCode,
		HasFinishConflict: parseOK && parsed.Finish != nil,
	}

	result := ReadResult{Stderr: statusRes.Stderr, Guard: domain.ParseStateGuard(statusRes.Stdout), SaveState: domain.HasSaveState(statusRes.Stdout), NavigationState: domain.HasNavigationState(statusRes.Stdout)}

	switch statusOutcome.ExitCode {
	case 2:
		// exit 2 needs `list` before the situation itself is final
		// (finish-pending is a REFINEMENT of no-review, decided by whether
		// list reports any repository-wide pending finish) — so list is read
		// before SituationFromStatus, unlike every other exit code.
		listRes := InvokeReview(ctx, "list", []string{"--porcelain"})
		listOK := !listRes.TimedOut && !listRes.SpawnFailed && listRes.ExitCode == 0
		if listOK {
			result.ContinueGuard = domain.ParseContinueGuard(listRes.Stdout)
			result.Branches = domain.ParseListPorcelain(listRes.Stdout)
			result.Fixes = domain.ParseListFixes(listRes.Stdout)
			result.HasList = true
			_, statusOutcome.ListFinishPending = domain.PendingFinish(result.Branches)
		}
	}

	result.Situation = domain.SituationFromStatus(statusOutcome)

	switch result.Situation {
	case domain.SituationReview, domain.SituationFinishConflict:
		result.Status = parsed
		result.HasStatus = parseOK

	case domain.SituationNoReview, domain.SituationFinishPending:
		// list already ran above (exit 2 always triggers it); config is
		// read here, alongside it, for the same two situations and no
		// others (T043's gate: never inside an active review).
		configRes := InvokeReview(ctx, "config", []string{"--porcelain"})
		if !configRes.TimedOut && !configRes.SpawnFailed && configRes.ExitCode == 0 {
			result.Config = domain.ParseConfigPorcelain(configRes.Stdout)
			result.HasConfig = true
		}
	}

	result.DetailsPending = statusRes.ExitCode == 0 || statusRes.ExitCode == 2
	result.CommentsLoading = result.DetailsPending
	return result
}

// Navigation uses the ordinary generation-protected details path.
func ReadNavigationReply(output string) (ReadResult, string, bool) {
	parsed, notice, ok := domain.ParseNavigationReply(output)
	if !ok {
		return ReadResult{}, "", false
	}
	result := ReadResult{Guard: domain.ParseStateGuard(output), NavigationState: true,
		Status: parsed, HasStatus: true, Situation: domain.SituationReview,
		DetailsPending: true, CommentsLoading: true}
	if text, ok := domain.ParseInlineWhy(output); ok {
		result.WhyIncluded = true
		result.Why, result.WhyState = whyFromText(text)
	}
	return result, notice, true
}

// ReadDetails enriches only the primary state passed by the caller. The UI
// generation gate rejects this entire result after a newer read or navigation.
func ReadDetails(ctx context.Context, result ReadResult) ReadResult {
	if !result.DetailsPending {
		return result
	}
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		comments := InvokeReview(ctx, "comments", []string{"status", "--porcelain"})
		result.Comments = comments.Stdout
		if comments.ExitCode != 0 || comments.TimedOut || comments.SpawnFailed {
			result.CommentsError = comments.Stderr
			if result.CommentsError == "" {
				result.CommentsError = domain.CommentsFailed
			}
		}
	}()
	if !result.WhyIncluded && result.HasStatus && result.Status.State.Mode == domain.ModeWalk && result.Status.State.CurrentPath.Raw != "" {
		result.Why, result.WhyState = readWhy(ctx, result.Status.State.CurrentPath.Raw)
	}
	wg.Wait()
	result.DetailsPending = false
	result.CommentsLoading = false
	return result
}

// readWhy runs `status --why <raw>` with the entry's RAW path — never the
// display form (data-model.md § PathRef) — and returns one of three states
// (T094): WhyFailed for a timeout, a spawn failure or a nonzero exit —
// the CLI itself could not answer, distinct from genuinely having nothing
// to say — WhyAbsent for an ok exit with empty stdout, and WhyPresent
// otherwise. WhyLoading is never returned here: by the time this function's
// caller sees a result, the read already happened, which is exactly why
// WhyLoading is the type's zero value instead (domain.WhyState's own doc).
func readWhy(ctx context.Context, raw string) (string, domain.WhyState) {
	res := InvokeReview(ctx, "status", []string{"--why", raw})
	if res.TimedOut || res.SpawnFailed || res.ExitCode != 0 {
		return "", domain.WhyFailed
	}
	return whyFromText(res.Stdout)
}

func whyFromText(stdout string) (string, domain.WhyState) {
	why := strings.TrimRight(stdout, "\n")
	if why == "" {
		return "", domain.WhyAbsent
	}
	return why, domain.WhyPresent
}

// Save's authoritative final inventory/config use the ordinary projection and
// generation-protected details path without starting another primary read.
func ReadSaveReply(output string) (ReadResult, bool) {
	reply, ok := domain.ParseSaveReply(output)
	if !ok {
		return ReadResult{}, false
	}
	branches := domain.ParseListPorcelain(reply.List)
	_, pending := domain.PendingFinish(branches)
	situation := domain.SituationNoReview
	if pending {
		situation = domain.SituationFinishPending
	}
	return ReadResult{Situation: situation, Branches: branches, ContinueGuard: domain.ParseContinueGuard(reply.List),
		Fixes: domain.ParseListFixes(reply.List), HasList: true,
		Config: domain.ParseConfigPorcelain(reply.Config), HasConfig: true,
		DetailsPending: true, CommentsLoading: true}, true
}

func ReadContinueReply(output string) (ReadResult, bool) {
	parsed, ok := domain.ParseContinueReply(output)
	if !ok {
		return ReadResult{}, false
	}
	return ReadResult{Guard: domain.ParseStateGuard(output), SaveState: domain.HasSaveState(output),
		NavigationState: domain.HasNavigationState(output), Status: parsed, HasStatus: true,
		Situation: domain.SituationReview, DetailsPending: true, CommentsLoading: true}, true
}
