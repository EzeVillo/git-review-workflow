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

// draftOriginAndRangeArgs is shared by the two preparatory calls behind
// "Validate and start". Their flags must describe the exact same range as
// the final start; unlike IntentToArgs, these verbs document source before
// range and have no layout flag.
func draftOriginAndRangeArgs(intent ReviewIntent) []string {
	var args []string
	switch intent.Source {
	case "local":
		args = append(args, "--local")
	case "offline":
		args = append(args, "--offline")
	}
	if intent.Range == "delta" {
		args = append(args, "--delta")
	}
	return args
}

// DraftBuildArgs builds `walkthrough draft --build <flags> -- <branch>`.
func DraftBuildArgs(intent ReviewIntent) []string {
	args := []string{"draft", "--build"}
	args = append(args, draftOriginAndRangeArgs(intent)...)
	return append(args, "--", intent.Branch)
}

// DraftConfigArgs builds the read-only probe that follows a green draft
// build and decides whether the keys-only choice exists.
func DraftConfigArgs(intent ReviewIntent) []string {
	args := []string{"--porcelain"}
	args = append(args, draftOriginAndRangeArgs(intent)...)
	return append(args, "--", intent.Branch)
}

// DraftWriteArgs builds the assistant's create/update invocation. Porcelain
// keeps human output (including an absolute path and next command) out of the
// status line and supplies the optional merged counts for an update.
func DraftWriteArgs(intent ReviewIntent) []string {
	args := []string{"draft", "--porcelain"}
	args = append(args, draftOriginAndRangeArgs(intent)...)
	return append(args, "--", intent.Branch)
}
