package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.MutationLock
import com.ezevillo.gitreview.domain.PanelInputs
import com.ezevillo.gitreview.domain.PanelModel
import com.ezevillo.gitreview.domain.ReviewState
import com.ezevillo.gitreview.domain.WhyState
import com.ezevillo.gitreview.domain.PanelWhy
import com.ezevillo.gitreview.domain.buildPanelModel
import com.ezevillo.gitreview.domain.draftWatchDirs
import com.ezevillo.gitreview.domain.isReviewReadable
import com.ezevillo.gitreview.domain.pickSoleTarget
import com.ezevillo.gitreview.settings.GitReviewSettings
import com.ezevillo.gitreview.settings.LastOpenedStore
import com.ezevillo.gitreview.ui.UiMessages
import com.ezevillo.gitreview.vcs.listGitRoots
import com.intellij.dvcs.repo.VcsRepositoryManager
import com.intellij.dvcs.repo.VcsRepositoryMappingListener
import com.intellij.openapi.Disposable
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.Disposer
import com.intellij.openapi.vcs.ProjectLevelVcsManager
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

@Service(Service.Level.PROJECT)
class GitReviewService(private val project: Project) : Disposable {
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
    private val refreshRequested = AtomicBoolean(false)
    private val vcsWaitRegistered = AtomicBoolean(false)
    private val vcsWaitDone = AtomicBoolean(false)
    @Volatile
    private var panelVisible: Boolean = false
    @Volatile
    private var lastWhy: PanelWhy? = null

    /**
     * Refresh signal for the one thing that is neither git nor a mutation of
     * ours: an agent filling in a draft. Same laziness as the mapping listener
     * below -- a draft that grows while nobody looks at the panel is read when
     * the tool window comes back, not before.
     */
    private val draftWatcher = DraftWatcher {
        if (panelVisible || listeners.isNotEmpty()) scheduleRefresh()
    }

    /**
     * Whether a refresh ever resolved a state. Before that there is nothing to
     * draw: the manager's seed value is an `ERROR` placeholder, and painting it
     * would tell the reviewer the review state is broken when it was never read.
     */
    @Volatile
    private var stateResolved: Boolean = false

    val mutationLock: MutationLock get() = lock
    val cliInvoker: CliInvoker get() = invoker

    init {
        Disposer.register(this, draftWatcher)
        // Mutations run off the EDT now, so busy/idle is a real interval the panel can
        // paint. Both refreshes of a mutation happen while the lock is held; without
        // this the model would stay busy until some later refresh cleared it.
        lock.onDidChangeBusy { publish() }
        // FR-036: palette/shortcuts do not see panel busy — surface the discard reason
        // (same string as VS Code: "Another operation is already in progress").
        lock.onDidDiscard { reason ->
            ApplicationManager.getApplication().invokeLater {
                if (!project.isDisposed) {
                    UiMessages.info(project, reason)
                }
            }
        }
        // The panel derives nothing on its own, so someone has to tell it when
        // git4idea finished discovering the repositories: opening a project
        // materializes the tool window before the VCS mappings are up, and
        // without this signal that first refresh stayed on "no single root"
        // until the reviewer hit Refresh by hand. The extension does the same
        // thing waiting for `vscode.git` to activate.
        // Still lazy (SC-006 / FR-017): a mapping change wakes the CLI only when
        // someone is looking at the panel.
        project.messageBus.connect(this).subscribe(
            VcsRepositoryManager.VCS_REPOSITORY_MAPPING_UPDATED,
            VcsRepositoryMappingListener {
                if (panelVisible || listeners.isNotEmpty()) scheduleRefresh()
            },
        )
    }

    override fun dispose() {
        // The message-bus connection and the draft watcher's roots are tied to
        // this service (the watcher through Disposer); nothing else to release.
    }

    fun currentState(): ReviewState = stateManager.current

    /** False until a refresh resolved a state — the panel has nothing to draw yet. */
    fun hasResolvedState(): Boolean = stateResolved

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

    /**
     * Coalesced, but never dropped: a request that lands while a refresh is in
     * flight re-runs it instead of being swallowed. The signals that fix a wrong
     * state (VCS mappings arriving, a mutation finishing) all arrive that way, so
     * losing one is exactly the case where the panel stays stale until the
     * reviewer refreshes by hand.
     */
    fun scheduleRefresh() {
        if (!panelVisible && listeners.isEmpty()) {
            // Lazy: no CLI until someone is listening (tool window shown) or refresh forced.
        }
        refreshRequested.set(true)
        if (!refreshScheduled.compareAndSet(false, true)) return
        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                while (refreshRequested.compareAndSet(true, false)) {
                    doRefresh()
                }
            } finally {
                refreshScheduled.set(false)
            }
            // A request between the loop exit and releasing the flag would have
            // no one to run it.
            if (refreshRequested.get()) scheduleRefresh()
        }
    }

    /** Blocking refresh — spawns CLI processes, so never call it from the EDT. */
    fun refreshNow() {
        doRefresh()
    }

    private fun doRefresh() {
        val roots = listGitRoots(project)
        if (roots.isEmpty() && !vcsWaitDone.get() && !vcsesActivated()) {
            // Not "this project has no git root" — nobody looked yet. Publishing
            // the multi-root error here is what left the panel on a diagnostic
            // the reviewer could not act on; wait for the VCSes instead.
            awaitVcsInitialization()
            return
        }
        val target = pickSoleTarget(roots)
        val state = stateManager.refresh(target?.rootPath)
        draftWatcher.sync(draftWatchDirs(state), state.guides.orEmpty().map { it.path })
        stateResolved = true
        lastWhy = null
        if (isReviewReadable(state.situation) && state.state?.mode?.id == "walk") {
            lastWhy = PanelWhy(WhyState.LOADING)
            publish()
            fetchWhy(target?.rootPath, state)
        } else {
            publish()
        }
    }

    private fun vcsesActivated(): Boolean =
        ProjectLevelVcsManager.getInstance(project).areVcsesActivated()

    /**
     * One-shot: re-refresh once the project's VCSes are up. [vcsWaitDone] is
     * never cleared, so a project that genuinely has no git root waits exactly
     * once and then gets the error like before.
     */
    private fun awaitVcsInitialization() {
        if (!vcsWaitRegistered.compareAndSet(false, true)) return
        ProjectLevelVcsManager.getInstance(project).runAfterInitialization {
            vcsWaitDone.set(true)
            scheduleRefresh()
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
