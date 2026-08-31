package domain

// ReviewIntent is the start assistant's four choices, before they become an
// argv (data-model.md § ReviewIntent): which branch, where its tip comes
// from, how much of it to read, and in what order.
type ReviewIntent struct {
	Branch string
	Source string // "remote" | "local" | "offline"
	Range  string // "full" | "delta"
	Layout string // "walk" | "keys" | "step" | "whole"
}

// IntentToArgs produces `start`'s argv in the FIXED order
// contracts/cli-invocation.md § "start intent -> args" pins down: layout
// flag, then --delta, then --local/--offline, then `--` and the branch.
// startFromDraft uses the exact same function — the draft's own recorded
// source/range simply become this same ReviewIntent's fields.
func IntentToArgs(intent ReviewIntent) []string {
	var args []string
	switch intent.Layout {
	case "keys":
		args = append(args, "--keys")
	case "step":
		args = append(args, "--step")
	case "whole":
		args = append(args, "--no-walk")
	case "walk":
		// No flag: walk is the default layout.
	}
	if intent.Range == "delta" {
		args = append(args, "--delta")
	}
	switch intent.Source {
	case "local":
		args = append(args, "--local")
	case "offline":
		args = append(args, "--offline")
	case "remote":
		// No flag: remote is the default source.
	}
	args = append(args, "--", intent.Branch)
	return args
}
