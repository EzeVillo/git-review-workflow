package domain

// KeymapEntry is one row of `keymap:` in contracts/client-product-
// surface.yaml. Exactly one of Does / Action / Opens / Toggles is set,
// matching whichever verb the entry's own section uses in the canonical.
type KeymapEntry struct {
	Keys []string
	// Does: movement — moves the focused row, never the review cursor.
	Does string
	// Action: cursor (next/prev) or actions (a product action with its own
	// key, e.g. refresh).
	Action string
	// Opens: overlays — the id of the overlay this key brings up.
	Opens string
	// Toggles: toggles — the id of the thing this key flips.
	Toggles string
}

// KeymapMovement moves the focused row in the LIST. It never touches the
// review's own cursor (n/p, below).
var KeymapMovement = []KeymapEntry{
	{Keys: []string{"j", "down"}, Does: "focus_next_row"},
	{Keys: []string{"k", "up"}, Does: "focus_prev_row"},
}

// KeymapCursor is the REVIEW's cursor. n/p are RESERVED for this and
// nothing else: navigating the list is a different concept, and confusing
// the two is the exact error this reservation exists to prevent
// (contracts/client-product-surface.yaml `keymap:`, gate (c)).
var KeymapCursor = []KeymapEntry{
	{Keys: []string{"n"}, Action: "next"},
	{Keys: []string{"p"}, Action: "prev"},
}

// KeymapActions is a product action bound to a key. `r`/refresh is
// available in all eight situations (FR-038). More entries land here as
// this client wires more actions to their own key — the canonical is the
// list to extend, not this comment.
var KeymapActions = []KeymapEntry{
	{Keys: []string{"r"}, Action: "refresh"},
}

// KeymapOverlays opens a full-screen or modal surface. action_list is the
// equivalent of `surface: action` in the other three clients — the palette
// where the four panel_excluded actions live exclusively.
var KeymapOverlays = []KeymapEntry{
	{Keys: []string{":"}, Opens: "action_list"},
	{Keys: []string{"g"}, Opens: "entry_picker"},
}

// KeymapToggles flips a piece of client-local state that is not itself a
// product action (mouse reporting on/off).
var KeymapToggles = []KeymapEntry{
	{Keys: []string{"m"}, Toggles: "mouse_reporting"},
}

func findKey(entries []KeymapEntry, key string) (KeymapEntry, bool) {
	for _, e := range entries {
		for _, k := range e.Keys {
			if k == key {
				return e, true
			}
		}
	}
	return KeymapEntry{}, false
}

// MovementFor resolves a key to a list-movement verb, or ok=false.
func MovementFor(key string) (string, bool) {
	e, ok := findKey(KeymapMovement, key)
	return e.Does, ok
}

// CursorActionFor resolves a key to a review-cursor action (next/prev), or
// ok=false.
func CursorActionFor(key string) (string, bool) {
	e, ok := findKey(KeymapCursor, key)
	return e.Action, ok
}

// BoundActionFor resolves a key to a product action bound outside the
// cursor (KeymapActions), or ok=false.
func BoundActionFor(key string) (string, bool) {
	e, ok := findKey(KeymapActions, key)
	return e.Action, ok
}

// OverlayFor resolves a key to the overlay it opens, or ok=false.
func OverlayFor(key string) (string, bool) {
	e, ok := findKey(KeymapOverlays, key)
	return e.Opens, ok
}

// ToggleFor resolves a key to the toggle it flips, or ok=false.
func ToggleFor(key string) (string, bool) {
	e, ok := findKey(KeymapToggles, key)
	return e.Toggles, ok
}
