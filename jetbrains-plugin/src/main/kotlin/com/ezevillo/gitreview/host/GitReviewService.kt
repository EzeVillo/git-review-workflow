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
import java.util.concurrent.atomic.AtomicLong

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
    private val refreshGate = RefreshGate()
    private val whyRead = WhyReadState()
    private val publicationGeneration = AtomicLong(0)
    private val vcsWaitRegistered = AtomicBoolean(false)
    private val vcsWaitDone = AtomicBoolean(false)
    @Volatile
    private var panelVisible: Boolean = false

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
        // Busy covers the mutation and authoritative primary state. Comments and
        // prose finish independently; releasing the lock must repaint immediately.
        var mutationStartedAt = 0L
        lock.onDidChangeBusy { busy ->
            refreshGate.mutationChanged(busy)
            if (busy) mutationStartedAt = System.nanoTime()
            else {
                val elapsed = (System.nanoTime() - mutationStartedAt) / 1_000_000
                val line = "Mutation lock released after ${elapsed}ms (comments pending=${stateManager.current.comments?.loading == true})"
                com.intellij.openapi.diagnostic.Logger.getInstance(GitReviewService::class.java).info(line)
                CliLogSink.append(line)
            }
            publish()
            if (!busy) drainRefresh()
        }
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
                why = whyRead.valueFor(state.state) ?: if (isReviewReadable(state.situation) &&
                    state.state?.mode?.id == "walk") PanelWhy(WhyState.LOADING) else null,
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
        refreshGate.request()
        drainRefresh()
    }

    private fun drainRefresh() {
        if (project.isDisposed || !refreshGate.tryStart()) return
        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                doRefresh()
            } finally {
                refreshGate.finished()
                drainRefresh()
            }
        }
    }

    /** Blocking refresh — spawns CLI processes, so never call it from the EDT. */
    fun refreshNow(navigationOutput: String? = null) {
        refreshGate.primaryStarting()
        doRefresh(navigationOutput)
    }

    fun readForMutation(): ReviewState =
        stateManager.readForMutation(pickSoleTarget(listGitRoots(project))?.rootPath)

    private var commentWatchPaths: List<String> = emptyList()

    private fun doRefresh(navigationOutput: String? = null) {
        val roots = listGitRoots(project)
        if (roots.isEmpty() && !vcsWaitDone.get() && !vcsesActivated()) {
            // Not "this project has no git root" — nobody looked yet. Publishing
            // the multi-root error here is what left the panel on a diagnostic
            // the reviewer could not act on; wait for the VCSes instead.
            awaitVcsInitialization()
            return
        }
        val target = pickSoleTarget(roots)
        var primaryPublished = false
        val pending = stateManager.refreshPrimary(target?.rootPath, navigationOutput) { primary ->
            primaryPublished = true
            stateResolved = true
            val needsWhy = isReviewReadable(primary.situation) && primary.state?.mode?.id == "walk"
            val loading = if (!needsWhy) null else primary.inlineWhy?.let { com.ezevillo.gitreview.domain.whyFromText(it) } ?: PanelWhy(WhyState.LOADING)
            val ticket = whyRead.begin(primary.state, loading)
            if (needsWhy && primary.inlineWhy == null) fetchWhy(target?.rootPath, primary, ticket)
            publish()
        }
        val state = pending.state
        if (stateManager.current !== state) return
        // The walkthrough travels with the guides in the exact-path list, for the
        // same reason: no watch root of its own (it lives in the work tree, which
        // every git operation moves), but a save on it has to refresh -- you
        // write the reading order by hand and press Ctrl+S, and the badge would
        // still say what it said before.
        syncWatchedFiles(state)
        stateResolved = true
        if (!primaryPublished) {
            whyRead.begin(state.state, null)
        }
        publish()
        if (state.comments?.loading == true) {
            ApplicationManager.getApplication().executeOnPooledThread {
                val complete = stateManager.completeComments(pending) ?: return@executeOnPooledThread
                if (project.isDisposed) return@executeOnPooledThread
                syncWatchedFiles(complete)
                publish()
            }
        }
    }

    @Synchronized
    private fun syncWatchedFiles(state: ReviewState) {
        if (stateManager.current !== state) return
        if (state.comments?.loading != true) commentWatchPaths = state.comments?.documents.orEmpty().map { it.path }
        draftWatcher.sync(draftWatchDirs(state), state.guides.orEmpty().map { it.path } +
            listOfNotNull(state.walkthrough?.path) + commentWatchPaths)
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

    private fun fetchWhy(cwd: String?, state: ReviewState, ticket: WhyReadState.Ticket) {
        if (cwd == null) {
            if (whyRead.complete(ticket, PanelWhy(WhyState.FAILED))) publish()
            return
        }
        val current = state.state?.current
        val raw = when (current) {
            is com.ezevillo.gitreview.domain.PathRef -> current.raw
            is String -> current
            else -> null
        }
        if (raw == null) {
            if (whyRead.complete(ticket, PanelWhy(WhyState.ABSENT))) publish()
            return
        }
        ApplicationManager.getApplication().executeOnPooledThread {
            val result = invoker.invoke("status", listOf("--why", raw), cwd)
            val why = when {
                result.timedOut || result.errorCode != null || (result.exitCode != null && result.exitCode != 0) ->
                    PanelWhy(WhyState.FAILED)
                else -> com.ezevillo.gitreview.domain.whyFromText(result.stdout)
            }
            if (whyRead.complete(ticket, why)) publish()
        }
    }

    private fun publish() {
        val generation = publicationGeneration.incrementAndGet()
        val model = currentModel()
        ApplicationManager.getApplication().invokeLater {
            if (project.isDisposed || generation != publicationGeneration.get()) return@invokeLater
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
