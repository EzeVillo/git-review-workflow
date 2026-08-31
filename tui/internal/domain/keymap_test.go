package domain

import (
	"strings"
	"testing"
)

func allKeymapSections() map[string][]KeymapEntry {
	return map[string][]KeymapEntry{
		"movement": KeymapMovement,
		"cursor":   KeymapCursor,
		"actions":  KeymapActions,
		"overlays": KeymapOverlays,
		"toggles":  KeymapToggles,
	}
}

// n/p are reserved for the review's cursor and must not appear anywhere
// else — the barra de teclas draws from this exact map, so a stray n/p
// bound to list movement would be a silent conflict with next/prev.
func TestNAndPAreReservedForCursorOnly(t *testing.T) {
	for name, entries := range allKeymapSections() {
		if name == "cursor" {
			continue
		}
		for _, e := range entries {
			for _, k := range e.Keys {
				if k == "n" || k == "p" {
					t.Errorf("keymap.%s binds reserved key %q", name, k)
				}
			}
		}
	}
}

func TestNoKeyIsBoundTwiceInTheSameSection(t *testing.T) {
	for name, entries := range allKeymapSections() {
		seen := map[string]bool{}
		for _, e := range entries {
			for _, k := range e.Keys {
				if seen[k] {
					t.Errorf("keymap.%s binds key %q twice", name, k)
				}
				seen[k] = true
			}
		}
	}
}

func TestMovementResolvesJKAndArrows(t *testing.T) {
	if got, ok := MovementFor("j"); !ok || got != "focus_next_row" {
		t.Errorf("MovementFor(j) = %q, %v", got, ok)
	}
	if got, ok := MovementFor("down"); !ok || got != "focus_next_row" {
		t.Errorf("MovementFor(down) = %q, %v", got, ok)
	}
	if got, ok := MovementFor("k"); !ok || got != "focus_prev_row" {
		t.Errorf("MovementFor(k) = %q, %v", got, ok)
	}
	if _, ok := MovementFor("n"); ok {
		t.Error("n must not resolve as movement")
	}
}

func TestCursorResolvesNAndP(t *testing.T) {
	if got, ok := CursorActionFor("n"); !ok || got != "next" {
		t.Errorf("CursorActionFor(n) = %q, %v", got, ok)
	}
	if got, ok := CursorActionFor("p"); !ok || got != "prev" {
		t.Errorf("CursorActionFor(p) = %q, %v", got, ok)
	}
}

func TestRefreshIsBoundAndReferencesADeclaredAction(t *testing.T) {
	got, ok := BoundActionFor("r")
	if !ok || got != "refresh" {
		t.Fatalf("BoundActionFor(r) = %q, %v", got, ok)
	}
	if _, ok := Actions["refresh"]; !ok {
		t.Fatal("keymap.actions references \"refresh\", which must be a declared action")
	}
}

func TestOverlaysResolve(t *testing.T) {
	if got, ok := OverlayFor(":"); !ok || got != "action_list" {
		t.Errorf(`OverlayFor(":") = %q, %v`, got, ok)
	}
	if got, ok := OverlayFor("g"); !ok || got != "entry_picker" {
		t.Errorf("OverlayFor(g) = %q, %v", got, ok)
	}
}

func TestTogglesResolve(t *testing.T) {
	if got, ok := ToggleFor("m"); !ok || got != "mouse_reporting" {
		t.Errorf("ToggleFor(m) = %q, %v", got, ok)
	}
}

// panel_excluded actions (goToEntry, forgetReview, previewEditsStat,
// showCliLog) reach the user only through the action_list overlay: none of
// them may have a direct key under keymap.actions (gate (e)).
func TestPanelExcludedActionsHaveNoDirectKey(t *testing.T) {
	excluded := map[string]bool{
		"goToEntry": true, "forgetReview": true, "previewEditsStat": true, "showCliLog": true,
	}
	for _, e := range KeymapActions {
		if excluded[e.Action] {
			t.Errorf("panel_excluded action %q must not have a direct key under keymap.actions", e.Action)
		}
	}
	if _, ok := OverlayFor("g"); !ok {
		t.Fatal("goToEntry must be reachable through its own picker overlay")
	}
}

func TestKeymapMirrorsCanonicalStructure(t *testing.T) {
	yaml := readCanonicalYAML(t)
	block := topLevelYAMLBlock(yaml, "keymap")
	if block == "" {
		t.Fatal("canonical has no keymap: block")
	}
	if !containsAll(block, "focus_next_row", "focus_prev_row", "action_list", "entry_picker", "mouse_reporting") {
		t.Error("keymap.go's verbs do not all appear in the canonical keymap: block")
	}
}

func containsAll(s string, subs ...string) bool {
	for _, sub := range subs {
		if !strings.Contains(s, sub) {
			return false
		}
	}
	return true
}
