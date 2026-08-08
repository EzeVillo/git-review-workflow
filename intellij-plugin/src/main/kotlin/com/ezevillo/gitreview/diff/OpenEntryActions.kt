package com.ezevillo.gitreview.diff

import com.ezevillo.gitreview.domain.EntryRecord
import com.ezevillo.gitreview.domain.PathRef
import com.ezevillo.gitreview.domain.ReviewMode
import com.ezevillo.gitreview.domain.ReviewState
import com.ezevillo.gitreview.settings.LastOpenedStore
import com.intellij.diff.DiffContentFactory
import com.intellij.diff.DiffManager
import com.intellij.diff.requests.SimpleDiffRequest
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.LocalFileSystem
import java.io.File

private fun EntryRecord.displayPath(): String = when (val id = this.id) {
    is PathRef -> id.display
    is String -> id
    else -> id.toString()
}

/**
 * Opens entry / change / all based on mode. Best-effort using VFS + DiffManager.
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
            state.state?.branch?.let { branch ->
                project.getService(LastOpenedStore::class.java).set(branch, entry.displayPath())
            }
        }
    }

    fun openChange(project: Project, state: ReviewState, entry: EntryRecord, cwd: String) {
        val mode = state.state?.mode ?: return
        when (mode) {
            ReviewMode.WHOLE, ReviewMode.WALK -> {
                val changes = RangeChanges.nameStatusHead(cwd)
                val path = entry.displayPath()
                val change = changes.find { it.path == path || it.after == path || it.before == path }
                if (change != null) {
                    openFileDiff(project, cwd, change.before, change.after, path)
                } else {
                    openWorkingTreeFile(project, cwd, path)
                }
            }
            ReviewMode.STEP -> {
                val sha = entry.id as? String ?: return
                openCommitDiff(project, cwd, sha)
            }
        }
    }

    fun openAllChanges(project: Project, state: ReviewState, cwd: String) {
        if (state.state?.mode != ReviewMode.WHOLE) return
        val changes = RangeChanges.nameStatusHead(cwd)
        for (c in changes) {
            openFileDiff(project, cwd, c.before, c.after, c.path)
        }
    }

    private fun openWorkingTreeFile(project: Project, cwd: String, relative: String) {
        val file = File(cwd, relative)
        val vf = LocalFileSystem.getInstance().refreshAndFindFileByIoFile(file)
            ?: LocalFileSystem.getInstance().findFileByIoFile(file)
        if (vf != null) {
            FileEditorManager.getInstance(project).openFile(vf, true)
        }
    }

    private fun openCommitDiff(project: Project, cwd: String, sha: String) {
        val changes = RangeChanges.nameStatusCommit(cwd, sha)
        for (c in changes.take(20)) {
            openFileDiff(project, cwd, c.before, c.after, c.path)
        }
    }

    private fun openFileDiff(
        project: Project,
        cwd: String,
        before: String?,
        after: String?,
        title: String,
    ) {
        val factory = DiffContentFactory.getInstance()
        val left = if (before != null) {
            val f = File(cwd, before)
            val vf = LocalFileSystem.getInstance().findFileByIoFile(f)
            if (vf != null) factory.create(project, vf) else factory.createEmpty()
        } else {
            factory.createEmpty()
        }
        val right = if (after != null) {
            val f = File(cwd, after)
            val vf = LocalFileSystem.getInstance().refreshAndFindFileByIoFile(f)
            if (vf != null) factory.create(project, vf) else factory.createEmpty()
        } else {
            factory.createEmpty()
        }
        val request = SimpleDiffRequest(title, left, right, "Before", "After")
        DiffManager.getInstance().showDiff(project, request)
    }
}
