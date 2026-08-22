// User-facing copy that is shared with the other clients, byte for byte.
//
// The JetBrains plugin and the Visual Studio extension have carried a UserCopy
// module for a while; this one is the extension's, and it exists for the same
// reason theirs do: scripts/check-client-product-surface.mjs compares the three
// against one canonical, and a string embedded in a command module would force
// that check to match against code rather than against a constant — which is
// fragile precisely when the text changes, the one thing the check exists to
// catch.

/**
 * What "Copy for agent" puts on the clipboard for one draft row.
 *
 * A pointer, not a prompt: the brief lives inside the file, in the instruction
 * block at the top, and repeating it here would give an agent two sources for
 * the same rules. `path` is the absolute path the CLI reported for that row —
 * never one the client built — so the text is enough on its own for an agent to
 * find the file.
 *
 * Byte for byte identical to UserCopy.kt and UserCopy.cs. Nothing here names a
 * model, a service or an assistant: copying is copying.
 */
export function draftAgentPrompt(path: string): string {
	return (
		`Fill in the reading order at ${path}. The instructions are inside the file, ` +
		"in the comment at the top. Do not change the file list or the numbering rules."
	);
}

/**
 * What "Copy for agent" puts on the clipboard for the author's own walkthrough.
 *
 * A pointer, like the draft one, and for the same reason. Two sentences differ,
 * and both are about the situation rather than the format: the file usually
 * already holds finished prose (a walkthrough is written when the PR is done,
 * and then the PR keeps moving), so the one damaging thing an agent can do here
 * is rewrite it whole. Saying "fill in the reading order" over a full file is
 * an instruction to start over, and it would undo exactly what updating in
 * place exists to preserve.
 *
 * Byte for byte identical to UserCopy.kt and UserCopy.cs.
 */
export function walkthroughAgentPrompt(path: string): string {
	return (
		`Update the reading order at ${path}. The instructions are inside the file, ` +
		"in the comment at the top. Entries that already have a number and a why are " +
		"finished: leave them as they are, and fill in only the ones marked \"## ?.\"."
	);
}
