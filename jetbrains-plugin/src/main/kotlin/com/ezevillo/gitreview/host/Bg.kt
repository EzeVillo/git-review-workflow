package com.ezevillo.gitreview.host

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.Project
import java.util.concurrent.atomic.AtomicReference

/**
 * Every git-review (and support-git) call spawns a process and blocks until it exits,
 * so none of them may run on the EDT: `OSProcessHandler.checkEdtAndReadAction` reports
 * it as an error and the UI freezes for the whole invocation. Button handlers and
 * `AnAction.actionPerformed` both run on the EDT, so these two helpers are the way in.
 */
object Bg {
    /**
     * Runs [work] on a pooled thread and hands the result to [then] back on the EDT.
     * Preferred: the panel keeps painting while the work runs, so the busy/skeleton
     * surface it already models is actually reachable.
     */
    fun <T> async(project: Project, title: String, work: () -> T, then: (T) -> Unit) {
        val holder = AtomicReference<T>()
        ProgressManager.getInstance().run(
            object : Task.Backgroundable(project, title, false) {
                override fun run(indicator: ProgressIndicator) {
                    holder.set(work())
                }

                override fun onSuccess() {
                    then(holder.get())
                }
            },
        )
    }

    /**
     * Runs [work] off the EDT but blocks the caller behind a modal progress dialog.
     * Only for the dialog-driven flows whose *next* question needs the answer (the
     * start wizard probes). A plain call when already off the EDT.
     */
    fun <T> sync(project: Project, title: String, work: () -> T): T {
        if (!ApplicationManager.getApplication().isDispatchThread) return work()
        val holder = AtomicReference<T>()
        ProgressManager.getInstance().runProcessWithProgressSynchronously(
            Runnable { holder.set(work()) },
            title,
            false,
            project,
        )
        return holder.get()
    }
}
