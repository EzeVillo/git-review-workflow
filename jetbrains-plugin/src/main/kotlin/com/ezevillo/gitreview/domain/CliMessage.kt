package com.ezevillo.gitreview.domain

/**
 * Flatten CLI stderr/stdout the same way the VS Code extension does for toasts:
 * trim each line, drop empties, join with a single space.
 */
fun flattenCliMessage(text: String): String =
    text.split('\n')
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .joinToString(" ")

/** First non-empty trimmed line (e.g. next/prev boundary note on stdout). */
fun firstCliLine(text: String): String =
    text.split('\n')
        .map { it.trim() }
        .firstOrNull { it.isNotEmpty() }
        .orEmpty()

/**
 * Prefer stderr, then stdout, then [fallback] — same fallbacks the extension uses
 * when the CLI exits non-zero with empty streams (killed / broken binary).
 */
fun cliErrorText(stderr: String, stdout: String = "", fallback: String): String {
    val err = flattenCliMessage(stderr)
    if (err.isNotEmpty()) return err
    val out = flattenCliMessage(stdout)
    if (out.isNotEmpty()) return out
    return fallback
}

/**
 * What a draft verb has to say once it succeeded, in one message: first what it
 * did, then its notes.
 *
 * The outcome comes on **stdout**, which is where this project puts the result
 * of every verb (start, finish, forget…), leaving stderr for errors and notes.
 * Reading stderr alone — which this path used to do — dropped the only sentence
 * that answers what happened: an update says "N kept, M added, K dropped", and
 * without it pressing the offer produced no signal at all. On a branch with no
 * note nothing appeared; on one with a note (the authoring-guide hint) what
 * appeared had nothing to do with what had just been pressed.
 */
fun draftOutcomeText(stdout: String, stderr: String): String =
    listOf(flattenCliMessage(stdout), flattenCliMessage(stderr))
        .filter { it.isNotEmpty() }
        .joinToString(" — ")
