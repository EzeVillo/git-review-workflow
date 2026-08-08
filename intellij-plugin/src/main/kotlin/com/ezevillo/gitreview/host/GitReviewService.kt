package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.MutationLock
import com.ezevillo.gitreview.domain.PanelInputs
import com.ezevillo.gitreview.domain.PanelModel
import com.ezevillo.gitreview.domain.ReviewState
import com.ezevillo.gitreview.domain.WhyState
import com.ezevillo.gitreview.domain.PanelWhy
import com.ezevillo.gitreview.domain.buildPanelModel
import com.ezevillo.gitreview.domain.isReviewReadable
import com.ezevillo.gitreview.settings.GitReviewSettings
import com.ezevillo.gitreview.settings.LastOpenedStore
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

@Service(Service.Level.PROJECT)
class GitReviewService(private val project: Project) {
    private val lock = MutationLock()
    private val invoker = CliInvoker(
        gitReviewPath = {
            GitReviewSettings.getInstance().path.ifBlank { null }
        },
    )
    private val stateManager = ReviewStateManager(
        invoker = invoker,
        gitReviewPath = { GitReviewSettings.getInstance().path.ifBlank { null } },
    )

    private val listeners = CopyOnWriteArrayList<(PanelModel) -> Unit>()
    private val refreshScheduled = AtomicBoolean(false)
    @Volatile
    private var panelVisible: Boolean = false
    @Volatile
    private var lastWhy: PanelWhy? = null

    val mutationLock: MutationLock get() = lock
    val cliInvoker: CliInvoker get() = invoker

    fun currentState(): ReviewState = stateManager.current

    fun currentModel(): PanelModel {
        val state = stateManager.current
        val lastOpened = state.state?.branch?.let { branch ->
            project.getService(LastOpenedStore::class.java).get(branch)
        }
        return buildPanelModel(
            state,
            PanelInputs(
                busy = lock.isBusy,
                why = lastWhy,
                lastOpened = lastOpened,
            ),
        )
    }

    fun onModelChanged(listener: (PanelModel) -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    fun setPanelVisible(visible: Boolean) {
        val was = panelVisible
        panelVisible = visible
        if (visible && !was) {
            scheduleRefresh()
        }
    }

    fun scheduleRefresh() {
        if (!panelVisible && listeners.isEmpty()) {
            // Lazy: no CLI until someone is listening (tool window shown) or refresh forced.
        }
        if (!refreshScheduled.compareAndSet(false, true)) return
        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                doRefresh()
            } finally {
                refreshScheduled.set(false)
            }
        }
    }

    fun refreshNow() {
        doRefresh()
    }

    private fun doRefresh() {
        val target = pickSoleGitRoot(project)
        val state = stateManager.refresh(target?.rootPath)
        lastWhy = null
        if (isReviewReadable(state.situation) && state.state?.mode?.id == "walk") {
            lastWhy = PanelWhy(WhyState.LOADING)
            publish()
            fetchWhy(target?.rootPath, state)
        } else {
            publish()
        }
    }

    private fun fetchWhy(cwd: String?, state: ReviewState) {
        if (cwd == null) {
            lastWhy = PanelWhy(WhyState.FAILED)
            publish()
            return
        }
        val current = state.state?.current
        val raw = when (current) {
            is com.ezevillo.gitreview.domain.PathRef -> current.raw
            is String -> current
            else -> null
        }
        if (raw == null) {
            lastWhy = PanelWhy(WhyState.ABSENT)
            publish()
            return
        }
        ApplicationManager.getApplication().executeOnPooledThread {
            val result = invoker.invoke("status", listOf("--why", raw), cwd)
            lastWhy = when {
                result.timedOut || result.errorCode != null || (result.exitCode != null && result.exitCode != 0) ->
                    PanelWhy(WhyState.FAILED)
                result.stdout.trim().isEmpty() -> PanelWhy(WhyState.ABSENT)
                else -> PanelWhy(WhyState.PRESENT, text = result.stdout.trimEnd())
            }
            publish()
        }
    }

    private fun publish() {
        val model = currentModel()
        ApplicationManager.getApplication().invokeLater {
            listeners.forEach { it(model) }
        }
    }

    fun invalidateCliVersion() {
        stateManager.invalidateVersion()
        scheduleRefresh()
    }

    companion object {
        fun getInstance(project: Project): GitReviewService =
            project.getService(GitReviewService::class.java)
    }
}
