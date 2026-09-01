package host

import (
	"context"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// ReadResult is one full read cycle's outcome: the derived Situation plus
// whichever raw parses actually applied to it. Has* flags exist because
// `list`/`config` are only ever invoked for no-review/finish-pending
// (contracts/cli-invocation.md § Lecturas de estado) — a caller must not
// read Branches/Config and assume they are populated just because the field
// exists on the struct.
type ReadResult struct {
	Situation domain.Situation

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

	result := ReadResult{Stderr: statusRes.Stderr}

	switch statusOutcome.ExitCode {
	case 2:
		// exit 2 needs `list` before the situation itself is final
		// (finish-pending is a REFINEMENT of no-review, decided by whether
		// list reports any repository-wide pending finish) — so list is read
		// before SituationFromStatus, unlike every other exit code.
		listRes := InvokeReview(ctx, "list", []string{"--porcelain"})
		listOK := !listRes.TimedOut && !listRes.SpawnFailed && listRes.ExitCode == 0
		if listOK {
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
		if parseOK && parsed.State.Mode == domain.ModeWalk && parsed.State.CurrentPath.Raw != "" {
			why, state := readWhy(ctx, parsed.State.CurrentPath.Raw)
			result.Why, result.WhyState = why, state
		}

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
	why := strings.TrimRight(res.Stdout, "\n")
	if why == "" {
		return "", domain.WhyAbsent
	}
	return why, domain.WhyPresent
}
