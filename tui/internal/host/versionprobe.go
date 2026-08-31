package host

import (
	"context"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// ProbeVersion runs `git review --version` and classifies the outcome into
// domain.VersionProbeOutcome, WITHOUT deciding the situation itself
// (FR-012: that derivation lives in domain.SituationFromVersionProbe) — this
// function's only job is to turn a Result into the three-way outcome that
// function already knows how to read, with a timeout taking priority over
// everything else so it can never be mistaken for a missing CLI.
func ProbeVersion(ctx context.Context) (domain.VersionProbeOutcome, Result) {
	res := InvokeReview(ctx, "--version", nil)
	switch {
	case res.TimedOut:
		return domain.VersionProbeOutcome{TimedOut: true}, res
	case res.SpawnFailed || res.ExitCode != 0:
		return domain.VersionProbeOutcome{SpawnOrExitFailed: true}, res
	default:
		return domain.VersionProbeOutcome{Version: strings.TrimSpace(res.Stdout)}, res
	}
}
