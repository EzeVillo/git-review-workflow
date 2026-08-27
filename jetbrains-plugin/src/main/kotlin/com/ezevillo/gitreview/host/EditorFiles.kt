package com.ezevillo.gitreview.host

import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.LocalFileSystem
import com.intellij.openapi.vfs.VirtualFile
import java.io.File

/**
 * The plugin's only door to the VFS, and the reason there is exactly one: resolving a
 * path is two operations wearing one name. `refreshAndFindFileBy*` looks the file up
 * and, when the VFS has never seen it, creates the node and fires the creation event --
 * a mutation of the platform's model, so it needs the write-intent lock and counts as a
 * slow operation. A panel button's ActionListener has neither: it enters through plain
 * Swing, not through an AnAction the platform wraps, so the call died with "Access is
 * allowed from write thread only" and the file never opened.
 *
 * Which files take that branch is not a corner case: the reviewer's draft and their own
 * authoring guide live in the gitdir, the one place no editor indexes, so they are
 * always the node the VFS has to create. The author's walkthrough sits in the working
 * tree and only ever hit the cache, which is why the same line read as fine next to it.
 *
 * So resolution runs off the EDT and the editor opens back on it, with [Bg.async] doing
 * both halves -- the same shape the diff path already used.
 */
fun openInEditor(project: Project, path: String, onMissing: () -> Unit = {}) =
    openInEditor(project, File(path), onMissing)

fun openInEditor(project: Project, file: File, onMissing: () -> Unit = {}) {
    Bg.async(
        project,
        "git review: opening ${file.name}",
        work = { refreshAndFind(file) },
        then = { vf ->
            if (vf != null && vf.isValid) {
                FileEditorManager.getInstance(project).openFile(vf, true)
            } else {
                onMissing()
            }
        },
    )
}

/**
 * Resolves one path, refreshing the VFS when it does not know the file yet.
 *
 * **Never on the EDT** -- see above. Anything that ends in an editor tab goes through
 * [openInEditor]; this is for the callers that need the file as a value (the diff
 * sides), and they already run inside a [Bg.async] `work` block.
 */
fun refreshAndFind(file: File): VirtualFile? =
    LocalFileSystem.getInstance().refreshAndFindFileByIoFile(file)
        ?: LocalFileSystem.getInstance().findFileByIoFile(file)
