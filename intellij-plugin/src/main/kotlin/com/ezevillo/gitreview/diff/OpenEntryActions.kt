package com.ezevillo.gitreview.diff

import com.ezevillo.gitreview.domain.CommitChange
import com.ezevillo.gitreview.domain.EntryRecord
import com.ezevillo.gitreview.domain.PathRef
import com.ezevillo.gitreview.domain.ReviewMode
import com.ezevillo.gitreview.domain.ReviewState
import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.host.Bg
import com.ezevillo.gitreview.settings.LastOpenedStore
import com.ezevillo.gitreview.ui.UiMessages
import com.intellij.diff.DiffContentFactory
import com.intellij.diff.DiffDialogHints
import com.intellij.diff.DiffManager
import com.intellij.diff.chains.SimpleDiffRequestChain
import com.intellij.diff.contents.DiffContent
import com.intellij.diff.requests.SimpleDiffRequest
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.fileTypes.FileTypeManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.LocalFileSystem
import com.intellij.openapi.vfs.VirtualFile
import java.io.File

private fun EntryRecord.displayPath(): String = when (val id = this.id) {
    is PathRef -> id.display
    is String -> id
    else -> id.toString()
}

/** The working-tree side of a review diff, as opposed to a blob at some ref. */
private const val WORKING_TREE = "Working tree"

/**
 * One side of a diff, already resolved off the EDT.
 *
 * [bytes] is the blob at a ref; [file] is the working-tree file (kept as a
 * `VirtualFile` so the reviewer can edit inside the diff, which is the whole point of
 * a review). Both null means the side does not exist at all — the file is added, or
 * deleted, and the viewer gets an empty pane.
 */
private class DiffSide(
    val label: String,
    val bytes: ByteArray? = null,
    val file: VirtualFile? = null,
    val fileName: String = "",
) {
    fun content(project: Project): DiffContent {
        val factory = DiffContentFactory.getInstance()
        if (file != null) return factory.create(project, file)
        if (bytes == null) return factory.createEmpty()
        val type = FileTypeManager.getInstance().getFileTypeByFileName(fileName)
        return try {
            factory.createFromBytes(project, bytes, type, fileName)
        } catch (_: Exception) {
            factory.createEmpty()
        }
    }
}

private class FileDiff(val title: String, val before: DiffSide, val after: DiffSide)

/**
 * Opens entry / change / all based on mode.
 *
 * Both halves matter: git is asked on a pooled thread ([Bg.async]), and the diff is
 * built and shown on the EDT. A diff's *before* side is the blob at the base ref, not
 * the file on disk — reading both sides from the working tree is the same file twice,
 * which the viewer reports as "contents are identical".
 */
object OpenEntryActions {
    fun openEntry(project: Project, state: ReviewState, entry: EntryRecord, cwd: String) {
        val mode = state.state?.mode ?: return
        when (mode) {
            ReviewMode.WALK, ReviewMode.WHOLE -> openWorkingTreeFile(project, cwd, entry.displayPath())
            ReviewMode.STEP -> {
                // For step, open the commit diff for the SHA
                val sha = entry.id as? String ?: return
                openCommitDiff(project, cwd, sha)
            }
        }
        if (mode == ReviewMode.WHOLE) {
            project.getService(LastOpenedStore::class.java)
                .set(state.state.branch, entry.displayPath())
        }
    }

    fun openChange(project: Project, state: ReviewState, entry: EntryRecord, cwd: String) {
        val mode = state.state?.mode ?: return
        when (mode) {
            ReviewMode.WHOLE, ReviewMode.WALK -> {
                val path = entry.displayPath()
                Bg.async(
                    project,
                    "git review: loading diff",
                    work = {
                        try {
                            val changes = RangeChanges.nameStatusHead(cwd)
                            val change = changes.find {
                                it.path == path || it.after == path || it.before == path
                            }
                            Pair(true, change?.let { listOf(rangeDiff(cwd, it)) })
                        } catch (_: Exception) {
                            Pair(false, null)
                        }
                    },
                    then = { (ok, diffs) ->
                        when {
                            !ok -> UiMessages.error(project, UserCopy.OPEN_RANGE_FAILED)
                            diffs == null -> UiMessages.info(project, UserCopy.openNoChangesLeft(path))
                            else -> show(project, diffs)
                        }
                    },
                )
            }
            ReviewMode.STEP -> {
                val sha = entry.id as? String ?: return
                openCommitDiff(project, cwd, sha)
            }
        }
    }

    /**
     * Whole mode: every change in the review range, in one DiffRequestChain window
     * (same UX as step commit Diff — Prev/Next file, not one editor tab each).
     */
    fun openAllChanges(project: Project, state: ReviewState, cwd: String) {
        if (state.state?.mode != ReviewMode.WHOLE) return
        Bg.async(
            project,
            "git review: loading changes",
            work = {
                try {
                    Pair(true, RangeChanges.nameStatusHead(cwd).map { rangeDiff(cwd, it) })
                } catch (_: Exception) {
                    Pair(false, emptyList())
                }
            },
            then = { (ok, diffs) ->
                when {
                    !ok -> UiMessages.error(project, UserCopy.OPEN_RANGE_FAILED)
                    diffs.isEmpty() -> UiMessages.info(project, UserCopy.OPEN_RANGE_EMPTY)
                    else -> show(project, diffs)
                }
            },
        )
    }

    private fun openWorkingTreeFile(project: Project, cwd: String, relative: String) {
        val file = File(cwd, relative)
        Bg.async(
            project,
            "git review: opening ${file.name}",
            work = { findWorkingTreeFile(file) },
            then = { vf -> if (vf != null) FileEditorManager.getInstance(project).openFile(vf, true) },
        )
    }

    private fun openCommitDiff(project: Project, cwd: String, sha: String) {
        Bg.async(
            project,
            "git review: loading commit",
            work = {
                try {
                    Pair(true, RangeChanges.nameStatusCommit(cwd, sha).take(20).map { commitDiff(cwd, sha, it) })
                } catch (_: Exception) {
                    Pair(false, emptyList())
                }
            },
            then = { (ok, diffs) ->
                when {
                    !ok -> UiMessages.error(project, UserCopy.openCommitFailed(sha))
                    diffs.isEmpty() -> UiMessages.info(project, UserCopy.openCommitEmpty(sha))
                    else -> show(project, diffs)
                }
            },
        )
    }

    /**
     * Review range: HEAD sits at the lower bound and the PR's changes are staged on top,
     * so *before* is the blob at HEAD and *after* is what the reviewer is editing.
     */
    private fun rangeDiff(cwd: String, change: CommitChange): FileDiff = FileDiff(
        title = change.path,
        before = blobSide(cwd, "HEAD", change.before, "HEAD"),
        after = change.after
            ?.let { DiffSide(WORKING_TREE, file = findWorkingTreeFile(File(cwd, it))) }
            ?: DiffSide(WORKING_TREE),
    )

    /** Step mode: a single commit against its parent, neither side from the working tree. */
    private fun commitDiff(cwd: String, sha: String, change: CommitChange): FileDiff {
        val short = sha.take(7)
        return FileDiff(
            title = change.path,
            before = blobSide(cwd, "$sha^", change.before, "$short^"),
            after = blobSide(cwd, sha, change.after, short),
        )
    }

    private fun blobSide(cwd: String, ref: String, path: String?, label: String): DiffSide {
        if (path == null) return DiffSide(label)
        return DiffSide(
            label,
            bytes = RangeChanges.showBytes(cwd, ref, path),
            fileName = path.substringAfterLast('/'),
        )
    }

    private fun findWorkingTreeFile(file: File): VirtualFile? =
        LocalFileSystem.getInstance().refreshAndFindFileByIoFile(file)
            ?: LocalFileSystem.getInstance().findFileByIoFile(file)

    /**
     * One file → single request. Several (step commit or whole open-all) →
     * [SimpleDiffRequestChain] so IntelliJ keeps one window with Prev/Next file
     * instead of one editor tab each.
     */
    private fun show(project: Project, diffs: List<FileDiff>) {
        if (diffs.isEmpty()) return
        val requests = diffs.map { diff ->
            SimpleDiffRequest(
                diff.title,
                diff.before.content(project),
                diff.after.content(project),
                diff.before.label,
                diff.after.label,
            )
        }
        if (requests.size == 1) {
            DiffManager.getInstance().showDiff(project, requests[0])
        } else {
            DiffManager.getInstance().showDiff(
                project,
                SimpleDiffRequestChain(requests),
                DiffDialogHints.DEFAULT,
            )
        }
    }
}
