package domain

// Situation is the eight-way (plus Waiting) verdict the panel draws from.
// Derivation is identical to the other three clients (data-model.md §
// Situation): CLI presence and freshness come first, then `status
// --porcelain`'s exit code, then the two records that split an exit code in
// two (`finish` for 0, `list`'s pending finish for 2).
type Situation string

const (
	// SituationWaiting is not a situation: it is the value before any
	// verdict exists (data-model.md). It draws waiting_text and nothing
	// else, and it is never derived by this package — a caller starts here
	// and DeriveX moves it forward, never back.
	SituationWaiting        Situation = "waiting"
	SituationCliMissing     Situation = "cli-missing"
	SituationCliOutdated    Situation = "cli-outdated"
	SituationNoReview       Situation = "no-review"
	SituationFinishPending  Situation = "finish-pending"
	SituationReview         Situation = "review"
	SituationFinishConflict Situation = "finish-conflict"
	SituationOutOfRange     Situation = "out-of-range"
	SituationError          Situation = "error"
)

// VersionProbeOutcome is what the host learned from invoking `--version`,
// classified enough to derive a situation without this package spawning
// anything itself (FR-012). A host-side retry of an ambiguous result (a
// ENOENT that might be transient) happens BEFORE this type is built —
// SituationFromVersionProbe sees only the settled verdict.
type VersionProbeOutcome struct {
	// TimedOut takes priority over everything else: a CLI that is merely
	// slow is the opposite of one that is absent, and reporting cli-missing
	// there would send the user to install what is already installed
	// (edge case of the spec, User Story 2 scenario 5).
	TimedOut bool
	// SpawnOrExitFailed: the process could not start, or it started and
	// exited non-zero. Meaningless when TimedOut is true.
	SpawnOrExitFailed bool
	// Version: `--version`'s trimmed stdout. Meaningful only when neither
	// of the above is true. An empty string here is treated as "nothing to
	// compare" and passes through to the next read, exactly like a version
	// string that parses and is not below the minimum — inventing
	// cli-outdated from silence would be worse than deferring to `status`.
	Version string
}

// SituationFromVersionProbe returns the terminal situation the probe alone
// decides (cli-missing, cli-outdated or the timeout's error), or ok=true
// when the CLI is present and current enough that the read should continue
// to `status --porcelain`.
func SituationFromVersionProbe(outcome VersionProbeOutcome, minVersion string) (situation Situation, ok bool) {
	if outcome.TimedOut {
		return SituationError, false
	}
	if outcome.SpawnOrExitFailed {
		return SituationCliMissing, false
	}
	if outcome.Version == "" {
		return "", true
	}
	if IsOutdated(outcome.Version, minVersion) {
		return SituationCliOutdated, false
	}
	return "", true
}

// StatusOutcome is what the host learned from `status --porcelain` (and,
// only when its exit code is 2, from `list --porcelain`) — never from
// reading refs, review config or the working tree directly (FR-012), and
// never from parsing a mutation's human stdout (FR-013).
type StatusOutcome struct {
	// TimedOut and SpawnFailed both fall to SituationError: "an old version
	// might be enough" is worth saying to the user, but neither one is
	// "no CLI" — the version probe already ruled that out for this same
	// read.
	TimedOut    bool
	SpawnFailed bool
	// ExitCode: meaningful only when neither of the above is true.
	ExitCode int
	// HasFinishConflict: a `finish` record was present. Only possible
	// (and only consulted) when ExitCode == 0.
	HasFinishConflict bool
	// ListFinishPending: `list --porcelain`, invoked because ExitCode == 2,
	// reported at least one branch with a pending finish. Only consulted
	// when ExitCode == 2.
	ListFinishPending bool
}

// SituationFromStatus derives the situation from a status read. It takes no
// previous situation as input — there is nothing to carry over, which is
// what keeps cli-missing/cli-outdated/error from ever being "repainted from
// memory": each read produces its own independent verdict, contracts/tui-
// surface.md's "no se repinten de memoria".
func SituationFromStatus(outcome StatusOutcome) Situation {
	if outcome.TimedOut || outcome.SpawnFailed {
		return SituationError
	}
	switch outcome.ExitCode {
	case 0:
		if outcome.HasFinishConflict {
			return SituationFinishConflict
		}
		return SituationReview
	case 2:
		if outcome.ListFinishPending {
			return SituationFinishPending
		}
		return SituationNoReview
	case 3:
		return SituationOutOfRange
	default:
		return SituationError
	}
}

// SituationForMissingRepo is the situation when the process cwd is not
// inside a git repository at all — the one case that precedes even the
// version probe (data-model.md). It carries its own copy
// (per_client_strings.no_single_root.tui) rather than the generic error
// text.
func SituationForMissingRepo() Situation { return SituationError }

// IsReviewReadable mirrors the other three clients: the two situations
// where the panel's review-shaped fields are populated and safe to read or
// leave entirely — a stuck finish still leaves the review legible, only
// navigating it (next/prev) does not belong there.
func IsReviewReadable(s Situation) bool {
	return s == SituationReview || s == SituationFinishConflict
}
