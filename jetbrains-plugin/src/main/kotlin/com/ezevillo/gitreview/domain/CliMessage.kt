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
