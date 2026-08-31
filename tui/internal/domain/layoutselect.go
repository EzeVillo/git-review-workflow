package domain

// LayoutSituationFor picks which of the 11 `panel_layout:` keys a given
// PanelModel draws as. Situation alone is not enough: "no-review" splits
// into no-review-setup/no-review by NoBaseConfigured, and "review" splits
// into review-walk/review-step/review-whole by Mode — the same split
// data-model.md describes and layout.go's AllLayoutSituations enumerates.
// This is the one place that split happens, so render.go and keys.go (and
// their tests) never re-derive it independently and risk disagreeing.
func LayoutSituationFor(m PanelModel) LayoutSituation {
	switch m.Situation {
	case SituationCliMissing:
		return LayoutCliMissing
	case SituationCliOutdated:
		return LayoutCliOutdated
	case SituationNoReview:
		if m.NoBaseConfigured {
			return LayoutNoReviewSetup
		}
		return LayoutNoReview
	case SituationFinishPending:
		return LayoutFinishPending
	case SituationFinishConflict:
		return LayoutFinishConflict
	case SituationReview:
		switch m.Mode {
		case ModeWalk:
			return LayoutReviewWalk
		case ModeStep:
			return LayoutReviewStep
		default:
			return LayoutReviewWhole
		}
	case SituationOutOfRange:
		return LayoutOutOfRange
	default:
		return LayoutError
	}
}
