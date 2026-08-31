package domain

// ConfirmingIDs mirrors `confirms: true` in contracts/client-product-
// surface.yaml (FR-024, FR-071). It is a fourth equivalent of VS Code's
// CONFIRMING_IDS, JetBrains' CONFIRMING_IDS and Visual Studio's
// ConfirmingIds — same set, byte for byte the same ids.
//
// startReview and startFromDraft are NOT here, deliberately, on both of the
// two paths that reach a start: the assistant already asks four questions,
// and `start` destroys nothing — it refuses on a dirty tree, and a review
// just started is cancelled with a single control, no undo needed.
//
// walkthroughInit IS confirms: true in the canonical, but it is the one
// declared exception: it does not ask yes/no, it opens the two-course
// picker ("Update" / "Start over") that ConfirmMutation cannot express,
// since ConfirmMutation's "no" is a plain cancel. It stays in this table
// because there is still a modal between the gesture and the mutation —
// that is what `confirms:` means — but its call site does not go through
// ConfirmMutation the way the other twelve do.
//
// EXCEPCION DECLARADA a la puerta unica: walkthroughInit (ver el comentario
// de arriba). scripts/check-client-product-surface.mjs lee esta frase para
// eximir el llamador de walkthroughInit del gate 2 (T067) — reformularla
// rompe el check.
var ConfirmingIDs = map[string]bool{
	"continueReview":   true,
	"discardInventory": true,
	"discardDraft":     true,
	"discardGuide":     true,
	"discardFixes":     true,
	"discardAllFixes":  true,
	"cleanReview":      true,
	"undoFinish":       true,
	"compareReview":    true,
	"walkthroughInit":  true,
	"walkthroughBuild": true,
	"saveReview":       true,
	"abortReview":      true,
}

// ConfirmChoice is what a confirmation overlay resolves to.
type ConfirmChoice int

const (
	// ConfirmCancelled: the dialog closed without the affirmative button —
	// closing it and pressing Cancel are the same "do nothing", never
	// "proceed".
	ConfirmCancelled ConfirmChoice = iota
	ConfirmAccepted
)

// ConfirmMutation is the ONLY gate a confirming mutation may pass through
// (contracts/client-product-surface.md § 8, gate 2). It takes the id so a
// caller cannot open a dialog the contract does not declare — the id does
// not change what gets drawn, only whether the static gate in
// scripts/check-client-product-surface.mjs accepts the call site.
//
// A caller decides what to draw (title, detail, button label); this
// function only enforces which ids may ask at all and reports what was
// chosen. It is deliberately a function value the ui package assigns and
// calls, not a type with behavior of its own — internal/ui/confirm.go
// (Phase 6) is the only file allowed to construct the overlay itself.
type ConfirmMutationFunc func(id string, title, detail, acceptLabel string) ConfirmChoice

// RequiresConfirmation reports whether id is one the canonical marks
// confirms: true.
func RequiresConfirmation(id string) bool {
	return ConfirmingIDs[id]
}
