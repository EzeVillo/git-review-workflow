package com.ezevillo.gitreview.domain

/**
 * Resolves the entry a command should operate on: explicit [EntryRecord], or
 * current by position when arg is null.
 */
fun resolveEntryArg(
    arg: Any?,
    entries: List<EntryRecord>,
    position: Int?,
): EntryRecord? {
    if (arg == null) {
        return entries.find { it.position == position }
    }
    if (arg is EntryRecord) {
        return arg
    }
    return null
}
