package com.ezevillo.gitreview.domain

/**
 * A file touched by a commit, with resolved before/after paths.
 * `null` means the file does not exist on that side.
 */
data class CommitChange(
    val path: String,
    val before: String?,
    val after: String?,
)

/**
 * Parses `git diff-tree -z --name-status` / `git diff --name-status -z` output.
 * With `-z`, git never quotes paths.
 */
fun parseNameStatus(output: String): List<CommitChange> {
    val fields = output.split('\u0000').filter { it.isNotEmpty() }
    val changes = ArrayList<CommitChange>()
    var i = 0
    while (i < fields.size) {
        val code = fields[i].firstOrNull() ?: break
        if (code == 'R' || code == 'C') {
            val from = fields.getOrNull(i + 1) ?: break
            val to = fields.getOrNull(i + 2) ?: break
            changes.add(CommitChange(path = to, before = from, after = to))
            i += 3
            continue
        }
        val path = fields.getOrNull(i + 1) ?: break
        changes.add(
            CommitChange(
                path = path,
                before = if (code == 'A') null else path,
                after = if (code == 'D') null else path,
            ),
        )
        i += 2
    }
    return changes
}
