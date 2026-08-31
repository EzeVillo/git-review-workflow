package domain

import (
	"reflect"
	"testing"
)

func TestProductActionsHasExactlyTwentySix(t *testing.T) {
	if len(ProductActions) != 26 {
		t.Fatalf("expected 26 product actions, got %d: %v", len(ProductActions), ProductActions)
	}
	for _, id := range ProductActions {
		if id == "openAllChanges" {
			t.Fatal("openAllChanges is not_in: [tui] (T006) and must never be offered")
		}
	}
}

// FR-014's closed list, verified from the other side too: every action
// this client declares must be one the canonical actually knows about, and
// vice versa (the bidirectional sweep in scripts/check-client-product-
// surface.mjs does the authoritative version of this against the YAML; this
// is the same property asserted against a hand-copied list here so `go
// test` alone already catches an id that only exists on one side).
func TestProductActionsMatchTheCanonicalTwentySeven(t *testing.T) {
	canonical := map[string]bool{
		"openEntry": true, "openChange": true, "openAllChanges": true, "showWhy": true,
		"next": true, "prev": true, "goToEntry": true, "refresh": true, "installCli": true,
		"continueReview": true, "startReview": true, "setBase": true, "setRemote": true,
		"abortReview": true, "saveReview": true, "finishReview": true, "undoFinish": true,
		"resumeFinish": true, "discardInventory": true, "cleanReview": true, "forgetReview": true,
		"previewEdits": true, "previewEditsStat": true, "compareReview": true,
		"walkthroughInit": true, "walkthroughBuild": true, "showCliLog": true,
	}
	if len(canonical) != 27 {
		t.Fatalf("test fixture itself is wrong: %d canonical ids, want 27", len(canonical))
	}
	for _, id := range ProductActions {
		if !canonical[id] {
			t.Errorf("ProductActions declares %q, which is not one of the canonical's 27", id)
		}
	}
	for id := range canonical {
		if id == "openAllChanges" {
			continue // not_in: [tui]
		}
		if !Actions[id] {
			t.Errorf("canonical action %q is missing from ProductActions", id)
		}
	}
}

// The (action, params) -> argv table FR-014 requires, one row per verb
// shape documented in contracts/cli-invocation.md § Mutaciones.
func TestBuildArgv(t *testing.T) {
	cases := []struct {
		name   string
		action string
		params ActionParams
		want   Argv
	}{
		{"refresh", "refresh", ActionParams{}, Argv{Verb: "status", Args: []string{"--porcelain"}}},
		{"showWhy", "showWhy", ActionParams{Source: `"a\303\261o.txt"`}, Argv{Verb: "status", Args: []string{"--why", `"a\303\261o.txt"`}}},
		{"next", "next", ActionParams{}, Argv{Verb: "next"}},
		{"prev", "prev", ActionParams{}, Argv{Verb: "prev"}},
		{"continueReview with source", "continueReview", ActionParams{Source: "feature"}, Argv{Verb: "continue", Args: []string{"feature"}}},
		{"continueReview without source", "continueReview", ActionParams{}, Argv{Verb: "continue"}},
		{
			"startReview", "startReview",
			ActionParams{Intent: ReviewIntent{Branch: "feature", Source: "remote", Range: "full", Layout: "walk"}},
			Argv{Verb: "start", Args: []string{"--", "feature"}},
		},
		{"setBase", "setBase", ActionParams{Name: "develop"}, Argv{Verb: "config", Args: []string{"base", "--", "develop"}}},
		{"setRemote", "setRemote", ActionParams{Name: "upstream"}, Argv{Verb: "config", Args: []string{"remote", "--", "upstream"}}},
		{"abortReview", "abortReview", ActionParams{}, Argv{Verb: "abort"}},
		{"saveReview", "saveReview", ActionParams{}, Argv{Verb: "save"}},
		{"finishReview plain", "finishReview", ActionParams{}, Argv{Verb: "finish"}},
		{"finishReview onto-source", "finishReview", ActionParams{OntoSource: true}, Argv{Verb: "finish", Args: []string{"--onto-source"}}},
		{"undoFinish first attempt", "undoFinish", ActionParams{}, Argv{Verb: "finish", Args: []string{"--abort"}}},
		{"undoFinish forced after stderr asks", "undoFinish", ActionParams{Force: true}, Argv{Verb: "finish", Args: []string{"--abort", "--force"}}},
		{"resumeFinish plain", "resumeFinish", ActionParams{}, Argv{Verb: "finish", Args: []string{"--resume"}}},
		{"resumeFinish onto-source", "resumeFinish", ActionParams{OntoSource: true}, Argv{Verb: "finish", Args: []string{"--resume", "--onto-source"}}},
		{"previewEdits", "previewEdits", ActionParams{}, Argv{Verb: "preview"}},
		{"previewEditsStat", "previewEditsStat", ActionParams{}, Argv{Verb: "preview", Args: []string{"--stat"}}},
		{
			"compareReview", "compareReview",
			ActionParams{CompareLayout: []string{"--step"}, CompareLower: "develop", CompareUpper: "feature"},
			Argv{Verb: "compare", Args: []string{"--step", "--", "develop", "feature"}},
		},
		{
			"compareReview with empty layout (whole)", "compareReview",
			ActionParams{CompareLower: "a", CompareUpper: "b"},
			Argv{Verb: "compare", Args: []string{"--", "a", "b"}},
		},
		{"walkthroughInit plain", "walkthroughInit", ActionParams{}, Argv{Verb: "walkthrough", Args: []string{"init"}}},
		{"walkthroughInit forced", "walkthroughInit", ActionParams{WalkthroughForce: true}, Argv{Verb: "walkthrough", Args: []string{"init", "--force"}}},
		{"walkthroughBuild", "walkthroughBuild", ActionParams{}, Argv{Verb: "walkthrough", Args: []string{"build"}}},

		// discardInventory / cleanReview / forgetReview: all three funnel
		// through HousekeepingAction, so one representative case each plus
		// the shapes unique to this table are enough; ArgsForHousekeeping has
		// its own exhaustive test below.
		{
			"cleanReview one", "cleanReview",
			ActionParams{Housekeeping: HousekeepingAction{Kind: CleanOne, Source: "feature"}},
			Argv{Verb: "clean", Args: []string{"feature"}},
		},
		{
			"discardInventory as forget-saved", "discardInventory",
			ActionParams{Housekeeping: HousekeepingAction{Kind: ForgetSavedOne, Source: "feature"}},
			Argv{Verb: "forget", Args: []string{"--saved", "feature"}},
		},
		{
			"forgetReview delta stale", "forgetReview",
			ActionParams{Housekeeping: HousekeepingAction{Kind: ForgetDeltaStale}},
			Argv{Verb: "forget", Args: []string{"--delta", "--stale"}},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := BuildArgv(c.action, c.params)
			if !ok {
				t.Fatalf("BuildArgv(%q) returned ok=false", c.action)
			}
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("BuildArgv(%q, %+v) = %+v, want %+v", c.action, c.params, got, c.want)
			}
		})
	}
}

// The four actions with no CLI argv at all (they delegate to $EDITOR,
// $PAGER-via-difftool is a DIFFERENT case handled by previewEdits/
// compareReview themselves, a picker, a copy/URL, or the in-memory log)
// must say so honestly rather than returning an empty-but-"ok" Argv.
func TestActionsWithNoCliInvocationReturnNotOK(t *testing.T) {
	for _, id := range []string{"openEntry", "openChange", "goToEntry", "installCli", "showCliLog"} {
		if _, ok := BuildArgv(id, ActionParams{}); ok {
			t.Errorf("%s must return ok=false: it is not a git-review invocation", id)
		}
	}
}

func TestBuildArgvUnknownActionIsNotOK(t *testing.T) {
	if _, ok := BuildArgv("thisAintReal", ActionParams{}); ok {
		t.Fatal("an unknown action id must not resolve to any argv")
	}
	if _, ok := BuildArgv("openAllChanges", ActionParams{}); ok {
		t.Fatal("openAllChanges must never resolve to an argv on this client")
	}
}

// discardAllFixes ALWAYS runs --fixes-only with no branch, per the
// canonical's own wording, regardless of what Source carries.
func TestCleanFixesOneAllIgnoresSource(t *testing.T) {
	got := ArgsForHousekeeping(HousekeepingAction{Kind: CleanFixesOneAll, Source: "leftover-from-a-stale-read"})
	want := []string{"--fixes-only"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("CleanFixesOneAll args = %v, want %v (source must never leak in)", got, want)
	}
}

func TestArgsForHousekeepingAllTenShapes(t *testing.T) {
	cases := []struct {
		kind HousekeepingKind
		verb string
		src  string
		want []string
	}{
		{CleanOne, "clean", "feature", []string{"feature"}},
		{CleanKeepFixes, "clean", "feature", []string{"--keep-fixes", "feature"}},
		{CleanFixesOne, "clean", "feature", []string{"--fixes-only", "feature"}},
		{CleanFixesOneAll, "clean", "", []string{"--fixes-only"}},
		{CleanAll, "clean", "", []string{}},
		{ForgetSavedOne, "forget", "feature", []string{"--saved", "feature"}},
		{ForgetSavedAll, "forget", "", []string{"--saved", "--all"}},
		{ForgetDeltaOne, "forget", "feature", []string{"--delta", "feature"}},
		{ForgetDeltaAll, "forget", "", []string{"--delta", "--all"}},
		{ForgetDeltaStale, "forget", "", []string{"--delta", "--stale"}},
		{ForgetDraftOne, "forget", "feature", []string{"--draft", "feature"}},
		{ForgetDraftAll, "forget", "", []string{"--draft", "--all"}},
		{ForgetDraftReviewed, "forget", "", []string{"--draft", "--reviewed"}},
	}
	for _, c := range cases {
		if got := VerbForHousekeeping(c.kind); got != c.verb {
			t.Errorf("VerbForHousekeeping(%v) = %q, want %q", c.kind, got, c.verb)
		}
		got := ArgsForHousekeeping(HousekeepingAction{Kind: c.kind, Source: c.src})
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("ArgsForHousekeeping(%v) = %v, want %v", c.kind, got, c.want)
		}
	}
}

func TestHousekeepingIsNetworkOnlyForDeltaStale(t *testing.T) {
	if !HousekeepingIsNetwork(ForgetDeltaStale) {
		t.Error("--delta --stale checks the remote first: it must be the Network class")
	}
	for _, kind := range []HousekeepingKind{CleanOne, CleanAll, ForgetSavedAll, ForgetDeltaAll, ForgetDraftAll} {
		if HousekeepingIsNetwork(kind) {
			t.Errorf("%v must not be classified as Network", kind)
		}
	}
}

func TestCreateAndDiscardGuideArgs(t *testing.T) {
	if got := CreateGuideArgs(false); !reflect.DeepEqual(got, []string{"guide"}) {
		t.Errorf("CreateGuideArgs(false) = %v", got)
	}
	if got := CreateGuideArgs(true); !reflect.DeepEqual(got, []string{"guide", "--team"}) {
		t.Errorf("CreateGuideArgs(true) = %v", got)
	}
	if got := DiscardGuideArgs(); !reflect.DeepEqual(got, []string{"guide", "--delete"}) {
		t.Errorf("DiscardGuideArgs() = %v", got)
	}
}
