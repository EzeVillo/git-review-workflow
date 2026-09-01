package host

import (
	"context"
	"strings"
	"time"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

const (
	versionProbeAttempts   = 3
	versionProbeRetryDelay = 400 * time.Millisecond
)

type versionProbeInvoker func(context.Context, string, []string) Result
type versionProbeWaiter func(context.Context, time.Duration) bool

// ProbeVersion runs `git review --version` and classifies the outcome into
// domain.VersionProbeOutcome, WITHOUT deciding the situation itself
// (FR-012: that derivation lives in domain.SituationFromVersionProbe) — this
// function retries ambiguous failures twice before returning. Every real
// attempt still uses InvokeReview, preserving the central environment,
// timeout and in-memory logging policy.
func ProbeVersion(ctx context.Context) (domain.VersionProbeOutcome, Result) {
	return probeVersionWith(ctx, InvokeReview, waitForVersionProbeRetry)
}

func probeVersionWith(ctx context.Context, invoke versionProbeInvoker, wait versionProbeWaiter) (domain.VersionProbeOutcome, Result) {
	var outcome domain.VersionProbeOutcome
	var res Result
	for attempt := 0; attempt < versionProbeAttempts; attempt++ {
		res = invoke(ctx, "--version", nil)
		var retry bool
		outcome, retry = classifyVersionResult(res)
		if !retry || attempt == versionProbeAttempts-1 {
			return outcome, res
		}
		if !wait(ctx, versionProbeRetryDelay) {
			return outcome, res
		}
	}
	return outcome, res
}

func waitForVersionProbeRetry(ctx context.Context, delay time.Duration) bool {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func classifyVersionResult(res Result) (domain.VersionProbeOutcome, bool) {
	switch {
	case res.TimedOut:
		return domain.VersionProbeOutcome{TimedOut: true}, true
	case hasExecutableNotFoundEvidence(res):
		return domain.VersionProbeOutcome{ExecutableNotFound: true}, false
	case res.SpawnFailed || res.ExitCode != 0:
		return domain.VersionProbeOutcome{Failed: true}, true
	default:
		return domain.VersionProbeOutcome{Version: strings.TrimSpace(res.Stdout)}, false
	}
}

func hasExecutableNotFoundEvidence(res Result) bool {
	if res.ExecutableNotFound {
		return true
	}
	if !res.SpawnFailed && res.ExitCode == 0 {
		return false
	}
	stderr := strings.ToLower(res.Stderr)
	for _, evidence := range []string{
		"is not a git command",
		"not found",
		"no such file",
		"enoent",
		"createprocess error=2",
	} {
		if strings.Contains(stderr, evidence) {
			return true
		}
	}
	return false
}
