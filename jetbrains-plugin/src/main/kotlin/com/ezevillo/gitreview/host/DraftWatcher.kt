package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.isDraftFileEvent
import com.ezevillo.gitreview.domain.isReportedGuide
import com.intellij.openapi.Disposable
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.vfs.LocalFileSystem
import com.intellij.openapi.vfs.VirtualFileManager
import com.intellij.openapi.vfs.newvfs.BulkFileListener
import com.intellij.openapi.vfs.newvfs.events.VFileEvent

/**
 * The third refresh signal, and the only one that is not git: the directories
 * where the CLI said the drafts are (see `domain/DraftWatch.kt`). An agent
 * filling a draft in writes to the gitdir, which neither the VCS mapping
 * listener nor the tool window's visibility ever hears about.
 *
 * The roots are registered **flat**, not recursive: the draft sits directly in
 * the reported directory, and a recursive root under the gitdir would have the
 * platform refreshing everything git writes there.
 */
class DraftWatcher(private val onChange: () -> Unit) : Disposable {
    private val localFs = LocalFileSystem.getInstance()

    @Volatile
    private var dirs: List<String> = emptyList()

    /**
     * The authoring guides, matched as EXACT paths and with no watch root of
     * their own: see `isReportedGuide`. They ride this listener rather than one
     * of their own because the events are the same ones.
     */
    @Volatile
    private var guides: List<String> = emptyList()
    private var requests: Set<LocalFileSystem.WatchRequest> = emptySet()

    init {
        ApplicationManager.getApplication().messageBus.connect(this)
            .subscribe(
                VirtualFileManager.VFS_CHANGES,
                object : BulkFileListener {
                    override fun after(events: MutableList<out VFileEvent>) {
                        val watched = dirs
                        val guided = guides
                        if (watched.isEmpty() && guided.isEmpty()) return
                        if (events.any {
                                isDraftFileEvent(watched, it.path) || isReportedGuide(guided, it.path)
                            }
                        ) {
                            onChange()
                        }
                    }
                },
            )
    }

    /**
     * Point the watcher at [next]. A no-op when the set did not change, which is
     * the case on nearly every refresh: replacing the roots drops the events
     * that land while it happens.
     */
    @Synchronized
    fun sync(next: List<String>, nextGuides: List<String> = emptyList()) {
        // Los guides no llevan watch root: sólo se comparan contra los eventos
        // que ya llegan, así que actualizarlos no puede perder ninguno.
        guides = nextGuides
        if (next == dirs) return
        dirs = next
        requests = localFs.replaceWatchedRoots(requests, null, next)
    }

    @Synchronized
    override fun dispose() {
        localFs.replaceWatchedRoots(requests, null, null)
        requests = emptySet()
        dirs = emptyList()
        guides = emptyList()
    }
}
