package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.*

/** Buffer state belongs to the IDE; ownership and closure guards still belong to the CLI. */
fun saveSessionComments(
    cli: CliRunner, root: String, state: ReviewState, action: String, params: ActionParams,
    hasUnsaved: () -> Boolean?, save: (List<String>) -> Boolean,
): Boolean {
    val housekeeping = (params as? ActionParams.Housekeeping)?.action
    val relevant = action in setOf("saveReview", "abortReview", "finishReview", "undoFinish", "resumeFinish") ||
        housekeeping?.kind in setOf(HousekeepingKind.CLEAN_ONE, HousekeepingKind.CLEAN_KEEP_FIXES,
            HousekeepingKind.CLEAN_ALL, HousekeepingKind.FORGET_SAVED_ONE, HousekeepingKind.FORGET_SAVED_ALL)
    if (!relevant) return true
    if (runCatching { hasUnsaved() }.getOrNull() == false) return true
    val response = cli.invoke("comments", listOf("status", "--porcelain", "--all"), root)
    if (response.exitCode != 0 || response.timedOut || response.errorCode != null) return false
    val report = parseComments(response.stdout)
    val saved = housekeeping?.kind in setOf(HousekeepingKind.FORGET_SAVED_ONE, HousekeepingKind.FORGET_SAVED_ALL)
    val prefix = if (saved) "review-saved/" else "review/"
    val source = housekeeping?.source ?: state.state?.source
        ?: state.fixes.firstOrNull { it.current }?.name?.removePrefix("review-fixes/")
    val all = housekeeping?.kind in setOf(HousekeepingKind.CLEAN_ALL, HousekeepingKind.FORGET_SAVED_ALL)
    val owners = report.records("comments-owner").filter { it.size >= 3 &&
        if (all) it[2].startsWith(prefix) else it[2] == prefix + source }.map { it[2] }.toSet()
    return save(commentsOwnedBy(report, owners).map { it.path })
}
