package domain

import (
	"reflect"
	"testing"
)

func TestIntentToArgsFixedOrder(t *testing.T) {
	cases := []struct {
		name   string
		intent ReviewIntent
		want   []string
	}{
		{
			"walk, full, remote: the all-defaults case",
			ReviewIntent{Branch: "feature", Source: "remote", Range: "full", Layout: "walk"},
			[]string{"--", "feature"},
		},
		{
			"keys layout",
			ReviewIntent{Branch: "feature", Source: "remote", Range: "full", Layout: "keys"},
			[]string{"--keys", "--", "feature"},
		},
		{
			"step layout",
			ReviewIntent{Branch: "feature", Source: "remote", Range: "full", Layout: "step"},
			[]string{"--step", "--", "feature"},
		},
		{
			"whole layout uses --no-walk",
			ReviewIntent{Branch: "feature", Source: "remote", Range: "full", Layout: "whole"},
			[]string{"--no-walk", "--", "feature"},
		},
		{
			"delta range",
			ReviewIntent{Branch: "feature", Source: "remote", Range: "delta", Layout: "walk"},
			[]string{"--delta", "--", "feature"},
		},
		{
			"local source",
			ReviewIntent{Branch: "feature", Source: "local", Range: "full", Layout: "walk"},
			[]string{"--local", "--", "feature"},
		},
		{
			"offline source",
			ReviewIntent{Branch: "feature", Source: "offline", Range: "full", Layout: "walk"},
			[]string{"--offline", "--", "feature"},
		},
		{
			"everything at once, in the documented order: layout, delta, source, --, branch",
			ReviewIntent{Branch: "feature", Source: "local", Range: "delta", Layout: "step"},
			[]string{"--step", "--delta", "--local", "--", "feature"},
		},
		{
			"whole + delta + offline",
			ReviewIntent{Branch: "feature/foo", Source: "offline", Range: "delta", Layout: "whole"},
			[]string{"--no-walk", "--delta", "--offline", "--", "feature/foo"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := IntentToArgs(c.intent)
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("IntentToArgs(%+v) = %v, want %v", c.intent, got, c.want)
			}
		})
	}
}

// A branch name that looks like a flag must still land after `--`, never
// interpreted as one — this is the whole reason `--` is there.
func TestIntentToArgsAlwaysSeparatesTheBranchWithDoubleDash(t *testing.T) {
	got := IntentToArgs(ReviewIntent{Branch: "--suspicious", Source: "remote", Range: "full", Layout: "walk"})
	if len(got) < 2 || got[len(got)-2] != "--" {
		t.Fatalf("argv = %v, the branch must be the last arg right after --", got)
	}
	if got[len(got)-1] != "--suspicious" {
		t.Errorf("argv = %v, branch must be passed through unmodified", got)
	}
}

func TestDraftValidationAndConfigRepeatTheRecordedSourceAndRange(t *testing.T) {
	intent := ReviewIntent{Branch: `feature/\303\261o`, Source: "offline", Range: "delta", Layout: "walk"}
	if got, want := DraftBuildArgs(intent), []string{"draft", "--build", "--offline", "--delta", "--", `feature/\303\261o`}; !reflect.DeepEqual(got, want) {
		t.Fatalf("DraftBuildArgs() = %#v, want %#v", got, want)
	}
	if got, want := DraftConfigArgs(intent), []string{"--porcelain", "--offline", "--delta", "--", `feature/\303\261o`}; !reflect.DeepEqual(got, want) {
		t.Fatalf("DraftConfigArgs() = %#v, want %#v", got, want)
	}
	if got, want := DraftWriteArgs(intent), []string{"draft", "--porcelain", "--offline", "--delta", "--", `feature/\303\261o`}; !reflect.DeepEqual(got, want) {
		t.Fatalf("DraftWriteArgs() = %#v, want %#v", got, want)
	}
}
