package ui

import "github.com/EzeVillo/git-review-workflow/tui/internal/domain"

// fixtureFor returns a FIXED PanelModel for one of the 11 panel_layout: keys
// (or "waiting"), built by hand — never from a real sandbox or a live
// invocation (T050: "un golden que depende de un sandbox es un golden que
// cambia solo"). golden_test.go and reachability_keyboard_test.go share
// these so the two suites are exercising the exact same shapes.
func fixtureFor(sit domain.LayoutSituation) domain.PanelModel {
	switch sit {
	case "waiting":
		return domain.PanelModel{Situation: domain.SituationWaiting}

	case domain.LayoutCliMissing:
		return domain.PanelModel{
			Situation: domain.SituationCliMissing,
			Stderr:    `exec: "git-review": executable file not found in $PATH`,
		}

	case domain.LayoutCliOutdated:
		return domain.PanelModel{Situation: domain.SituationCliOutdated}

	case domain.LayoutNoReviewSetup:
		return domain.PanelModel{
			Situation:        domain.SituationNoReview,
			NoBaseConfigured: true,
			ConfiguredRemote: "origin",
		}

	case domain.LayoutNoReview:
		return domain.PanelModel{
			Situation:        domain.SituationNoReview,
			NoBaseConfigured: false,
			ConfiguredBase:   "develop",
			ConfiguredRemote: "origin",
		}

	case domain.LayoutReviewWalk:
		return domain.PanelModel{
			Situation:   domain.SituationReview,
			Mode:        domain.ModeWalk,
			Branch:      "review/feat-x",
			Source:      "feat-x",
			Tip:         "a1b2c3d",
			Position:    3,
			Total:       7,
			AtFirst:     false,
			AtLast:      false,
			HasCurrent:  true,
			CurrentPath: domain.NewPathRef("src/core.ts"),
			HasWhy:      true,
			Why:         "touches shared state other entries also read",
		}

	case domain.LayoutReviewStep:
		return domain.PanelModel{
			Situation:  domain.SituationReview,
			Mode:       domain.ModeStep,
			Branch:     "review/feat-x",
			Source:     "feat-x",
			Position:   2,
			Total:      4,
			AtFirst:    false,
			AtLast:     false,
			HasCurrent: true,
			CurrentSHA: "abc1234",
			EntryCount: 2,
			Files:      "a.go\nb.go",
		}

	case domain.LayoutReviewWhole:
		return domain.PanelModel{
			Situation: domain.SituationReview,
			Mode:      domain.ModeWhole,
			Branch:    "review/feat-x",
			Source:    "feat-x",
			Base:      "develop",
			HasBase:   true,
			Total:     2,
			Files:     "README.md\nsrc/quoting.ts",
		}

	case domain.LayoutFinishPending:
		return domain.PanelModel{
			Situation:         domain.SituationFinishPending,
			PendingFinish:     true,
			FinishDestination: "review-fixes/feat-x",
		}

	case domain.LayoutFinishConflict:
		return domain.PanelModel{
			Situation:      domain.SituationFinishConflict,
			Mode:           domain.ModeWalk,
			Branch:         "review/feat-x",
			FinishConflict: true,
			Position:       1,
			Total:          3,
			HasCurrent:     true,
			CurrentPath:    domain.NewPathRef("a.go"),
			HasWhy:         true,
			Why:            "conflicting hunk in a.go",
		}

	case domain.LayoutOutOfRange:
		return domain.PanelModel{
			Situation: domain.SituationOutOfRange,
			Stderr:    "the base moved past this review's recorded tip",
		}

	case domain.LayoutError:
		return domain.PanelModel{
			Situation: domain.SituationError,
			Stderr:    "unexpected exit status 128",
		}
	}
	panic("fixtureFor: unhandled layout situation " + string(sit))
}

// allFixtureSituations is AllLayoutSituations plus "waiting" — the 12 keys
// T050's golden set covers (11 layout keys + the waiting frame).
var allFixtureSituations = append([]domain.LayoutSituation{"waiting"}, domain.AllLayoutSituations...)
