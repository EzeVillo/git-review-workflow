package com.ezevillo.gitreview.domain

data class SourcePreferenceLevels(
    val workspaceValue: String? = null,
    val globalValue: String? = null,
)

private val VALID = setOf("remote", "local", "offline")

private fun asSource(value: String?): ReviewSource? {
    if (value != null && value in VALID) return ReviewSource.parse(value)
    return null
}

/** Workspace wins over user; default `"remote"`. */
fun resolveDefaultSource(levels: SourcePreferenceLevels): ReviewSource =
    asSource(levels.workspaceValue) ?: asSource(levels.globalValue) ?: ReviewSource.REMOTE
