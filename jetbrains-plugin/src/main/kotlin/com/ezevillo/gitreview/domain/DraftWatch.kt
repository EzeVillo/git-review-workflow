package com.ezevillo.gitreview.domain

/**
 * What to watch to see a draft grow, and what counts as a change to it.
 *
 * The reviewer's draft lives in the gitdir (`<gitdir>/review-walkthrough/
 * <src>.md`), outside the working tree and outside the refs: an agent filling
 * it in moves no `HEAD`, touches no index and writes no `config`, so none of
 * the panel's refresh signals sees it. Without a watcher the progress on the
 * draft block stays frozen at `3/9` until somebody hits Refresh — exactly while
 * the reviewer is looking at the panel to find out whether the agent is done.
 *
 * The directories come from the paths the CLI already reported (the `draft`
 * records of `config --porcelain` and `status --porcelain`), never from
 * rebuilding the gitdir layout — the same rule that has *Open draft* open the
 * path the CLI gave instead of deriving it. Deliberate consequence: a draft in
 * a directory no report has named yet has nobody watching it; there is no
 * progress to follow there, only a file the panel does not know about.
 */
fun draftWatchDirs(state: ReviewState): List<String> {
    val dirs = LinkedHashSet<String>()
    (listOf(state.draftPath) + (state.drafts.orEmpty().map { it.path })).forEach { file ->
        containerOf(file)?.let { dirs.add(it) }
    }
    // Sorted, not in order of appearance: the caller compares two results to
    // decide whether to rebuild the watch roots, and rebuilding them drops the
    // events that land while it happens.
    return dirs.sorted()
}

/**
 * Whether a VFS event on [path] is about a draft in one of [dirs].
 *
 * Case-insensitive on purpose: the VFS reports what the filesystem gave it, and
 * on Windows and macOS that casing need not match the CLI's. A false positive
 * costs one refresh; a false negative is the panel going quiet again.
 */
fun isDraftFileEvent(dirs: Collection<String>, path: String): Boolean {
    if (dirs.isEmpty() || !path.endsWith(".md", ignoreCase = true)) return false
    val dir = containerOf(path) ?: return false
    return dirs.any { it.equals(dir, ignoreCase = true) }
}

/** The directory holding [file], with separators normalised, or null. */
private fun containerOf(file: String?): String? {
    if (file.isNullOrBlank()) return null
    // The CLI resolves with `git rev-parse --absolute-git-dir`, which answers
    // with `/` even on Windows, but the VFS is not the only caller.
    val normalised = file.replace('\\', '/')
    val cut = normalised.lastIndexOf('/')
    return if (cut > 0) normalised.substring(0, cut) else null
}
