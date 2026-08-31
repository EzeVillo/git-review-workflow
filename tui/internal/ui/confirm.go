package ui

import (
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// ConfirmOverlay is the ONE modal this client ever shows (CLAUDE.md § "La
// copy de los paneles": "un dialogo de confirmacion se abre en UN solo lugar
// por cliente, y esa puerta toma el id"). Every confirming mutation's
// yes/no runs through the type built HERE and nowhere else in tui/ —
// scripts/check-client-product-surface.mjs's gate 3 sweeps every other .go
// file under internal/ui for a "ConfirmOverlay{" construction and fails if
// it finds one.
//
// It is a plain value the rest of ui/ can build (via ConfirmMutation below)
// and store on Model as an optional field (nil = no overlay open) — the
// bubbletea-friendly shape T066 asks for: no goroutines, no blocking, just
// state a later KeyMsg resolves.
type ConfirmOverlay struct {
	ID          string
	Title       string
	Detail      string
	AcceptLabel string
	// Token: captured when the GESTURE that opened this overlay fired —
	// T065 revalidates it again, inside the lock, right before the actual
	// spawn, never here at construction time and never at accept time
	// either (accept time IS revalidation time, since the lock's Begin/
	// check/spawn all happen in the same synchronous call).
	Token domain.StateToken
	// Pending: what to run if the user accepts.
	Pending mutationRequest
}

// ConfirmMutation is the single gate every confirming mutation call site in
// this package must pass through (T066/T067 gate 2) — the TUI's version of
// VS Code's confirmMutation(id, ...), JetBrains' UiMessages.confirm and
// Visual Studio's GitReviewDialogs.Confirm, and the ONLY function in tui/
// allowed to construct a *ConfirmOverlay (gate 3, T068).
//
// It cannot share domain.ConfirmMutationFunc's own synchronous signature:
// that shape assumes the platform can block the calling goroutine until a
// person answers (VS Code awaits a Promise; JetBrains/Visual Studio block on
// a modal dialog call). bubbletea's Update must never block, so here the
// answer arrives on a LATER KeyMsg instead of being returned from this call.
// ConfirmMutation plays the same role domain.ConfirmMutationFunc documents
// — the id decides whether this may ask at all, not what gets drawn — just
// open-now/answer-later instead of ask-and-wait.
//
// id must be one the canonical marks confirms: true (domain.
// RequiresConfirmation); a caller that gets this wrong is a bug the static
// gate 2 in scripts/check-client-product-surface.mjs catches, not something
// this function defends against at runtime — mirroring confirm.ts's own
// choice to log and proceed rather than silently swallow the gesture.
func ConfirmMutation(id, title, detail, acceptLabel string, token domain.StateToken, pending mutationRequest) *ConfirmOverlay {
	return &ConfirmOverlay{
		ID:          id,
		Title:       title,
		Detail:      detail,
		AcceptLabel: acceptLabel,
		Token:       token,
		Pending:     pending,
	}
}

// HandleKey resolves one keypress against the open overlay. resolved=false
// means still open, waiting for another key — the same "closing it and
// pressing Cancel are the same do nothing" rule domain.ConfirmCancelled's
// own doc states applies here too: any key that is not an explicit accept
// leaves the choice at ConfirmCancelled once resolved.
func (o *ConfirmOverlay) HandleKey(key string) (choice domain.ConfirmChoice, resolved bool) {
	switch key {
	case "y", "enter":
		return domain.ConfirmAccepted, true
	case "n", "esc", "ctrl+c", "q":
		return domain.ConfirmCancelled, true
	}
	return domain.ConfirmCancelled, false
}

// Render draws the overlay as the WHOLE frame while it is open. This is a
// deliberate simplification over true ANSI-safe compositing: the base
// frame's lines already carry lipgloss escape sequences (bold headings,
// colored buttons), and splicing a centered box into the middle of them
// column-by-column risks cutting an escape sequence in half — there is no
// ANSI-aware splice helper in this tree, and building one just for a modal
// that already means "nothing else is live" is not worth the risk of a
// corrupted frame. Functionally a confirmation already means every OTHER
// control is inert (Update never lets a keypress reach the base frame's
// controls while this is open) — replacing the frame is the same
// user-visible effect ("there's a modal up") without the ANSI risk.
func (o *ConfirmOverlay) Render(vp Viewport) string {
	st := stylesFor(vp.Color)
	var lines []string
	lines = append(lines, st.heading.Render(o.Title))
	if o.Detail != "" {
		lines = append(lines, "", o.Detail)
	}
	lines = append(lines, "",
		"[ "+st.primary.Render(o.AcceptLabel)+" ]  (y / enter)",
		"[ "+st.secondary.Render("Cancel")+" ]  (n / esc)",
	)
	if vp.Cols > 0 {
		var wrapped []string
		for _, l := range lines {
			wrapped = append(wrapped, wrapLine(l, vp.Cols)...)
		}
		lines = wrapped
	}
	if vp.Rows > 0 && len(lines) > vp.Rows {
		lines = lines[:vp.Rows]
	}
	return strings.Join(lines, "\n")
}
