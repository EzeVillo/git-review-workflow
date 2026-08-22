package com.ezevillo.gitreview.ui.actions

import com.ezevillo.gitreview.diff.OpenEntryActions
import com.ezevillo.gitreview.domain.ActionParams
import com.ezevillo.gitreview.domain.HousekeepingAction
import com.ezevillo.gitreview.domain.HousekeepingKind
import com.ezevillo.gitreview.domain.ReviewLayout
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.branchPickerLabel
import com.ezevillo.gitreview.domain.confirmCopyFor
import com.ezevillo.gitreview.domain.currentEntry
import com.ezevillo.gitreview.domain.entryPickLabel
import com.ezevillo.gitreview.domain.pendingFinishInfo
import com.ezevillo.gitreview.domain.resumableSourceAt
import com.ezevillo.gitreview.domain.sourceFromReviewName
import com.ezevillo.gitreview.host.Bg
import com.ezevillo.gitreview.host.GitReviewService
import com.ezevillo.gitreview.host.MutationActions
import com.ezevillo.gitreview.ui.StartWizard
import com.ezevillo.gitreview.ui.UiMessages
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.ide.BrowserUtil
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.LocalFileSystem
import java.io.File

private fun service(e: AnActionEvent) = e.project?.let { GitReviewService.getInstance(it) }
private fun mutations(e: AnActionEvent): MutationActions? {
    val p = e.project ?: return null
    return MutationActions(p, GitReviewService.getInstance(p))
}

class NextAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        mutations(e)?.runNextPrev("next")
    }
}

class PrevAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        mutations(e)?.runNextPrev("prev")
    }
}

class GoToEntryAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        val state = service.currentState()
        if (state.entries.isEmpty()) return
        val labels = state.entries.map {
            entryPickLabel(it, state.state?.position, state.subjects?.get(it.position)).label
        }.toTypedArray()
        val idx = UiMessages.choose(
            project,
            "Go to entry",
            UserCopy.PRODUCT_TITLE,
            labels,
        )
        if (idx < 0) return
        val entry = state.entries[idx]
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        OpenEntryActions.openEntry(project, state, entry, cwd)
    }
}

class StartReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        e.project?.let { StartWizard.run(it) }
    }
}

class ContinueReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        val branches = service.currentState().branches
        if (branches.isEmpty()) {
            UiMessages.info(project, UserCopy.NO_SAVED_REVIEWS)
            return
        }
        val labels = branches.mapIndexed { i, b ->
            val src = resumableSourceAt(branches, i)
            "${b.name}" + if (src != null) " (resumable)" else ""
        }.toTypedArray()
        val idx = UiMessages.choose(
            project,
            "Continue which saved review?",
            UserCopy.PRODUCT_TITLE,
            labels,
        )
        if (idx < 0) return
        val source = resumableSourceAt(branches, idx) ?: run {
            UiMessages.error(project, UserCopy.NOT_RESUMABLE)
            return
        }
        if (!UiMessages.confirm(
                project,
                UserCopy.continueTitle(source),
                UserCopy.continueDetail(source),
                UserCopy.CONTINUE_BUTTON,
            )
        ) {
            return
        }
        mutations(e)?.runSimple(
            "continueReview",
            ActionParams.Continue(source),
            progressTitle = UserCopy.continuingProgress(source),
        )
    }
}

class FinishReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        val state = service.currentState()
        if (state.readonly == true) {
            UiMessages.info(project, UserCopy.READONLY_FINISH)
            return
        }
        val source = state.state?.source ?: return
        val options = arrayOf(UserCopy.FINISH_LOCATION_SEPARATE, UserCopy.FINISH_LOCATION_ONTO)
        val idx = UiMessages.choose(
            project,
            UserCopy.FINISH_LOCATION_PLACEHOLDER,
            UserCopy.finishLocationTitle(source),
            options,
        )
        if (idx < 0) return
        val onto = idx == 1
        mutations(e)?.runFinish(onto) { msg ->
            if (msg != null) {
                UiMessages.info(project, msg)
            }
        }
    }

    override fun update(e: AnActionEvent) {
        val model = service(e)?.currentModel()
        e.presentation.isEnabled =
            model != null &&
                model.situation == Situation.REVIEW &&
                !model.readonly &&
                !model.busy
    }

    override fun getActionUpdateThread() =
        com.intellij.openapi.actionSystem.ActionUpdateThread.BGT
}

class AbortReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val source = service(e)?.currentState()?.state?.source ?: return
        if (!UiMessages.confirm(
                project,
                UserCopy.abortTitle(source),
                UserCopy.ABORT_DETAIL,
                UserCopy.ABORT_BUTTON,
            )
        ) {
            return
        }
        mutations(e)?.runSimple(
            "abortReview",
            progressTitle = UserCopy.abortingProgress(source),
        )
    }

    override fun update(e: AnActionEvent) {
        val model = service(e)?.currentModel()
        val sit = model?.situation
        e.presentation.isEnabled =
            model != null &&
                !model.busy &&
                (sit == Situation.REVIEW || sit == Situation.FINISH_CONFLICT)
    }

    override fun getActionUpdateThread() =
        com.intellij.openapi.actionSystem.ActionUpdateThread.BGT
}

class SaveReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val source = service(e)?.currentState()?.state?.source ?: return
        if (!UiMessages.confirm(
                project,
                UserCopy.saveTitle(source),
                UserCopy.SAVE_DETAIL,
                UserCopy.SAVE_BUTTON,
            )
        ) {
            return
        }
        mutations(e)?.runSimple(
            "saveReview",
            progressTitle = UserCopy.savingProgress(source),
        )
    }

    override fun update(e: AnActionEvent) {
        val model = service(e)?.currentModel()
        e.presentation.isEnabled =
            model != null &&
                model.situation == Situation.REVIEW &&
                !model.busy
    }

    override fun getActionUpdateThread() =
        com.intellij.openapi.actionSystem.ActionUpdateThread.BGT
}

class UndoFinishAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val m = mutations(e) ?: return
        runUndoFinish(project, m, service(e)?.currentState()?.situation)
    }
}

/** Shared by the menu action and the panel control. */
internal fun runUndoFinish(project: Project, mutations: MutationActions, situation: Situation?) {
    val detail = if (situation == Situation.FINISH_CONFLICT) {
        UserCopy.UNDO_DETAIL_CONFLICT
    } else {
        UserCopy.UNDO_DETAIL_PENDING
    }
    if (!UiMessages.confirm(project, UserCopy.UNDO_TITLE, detail, UserCopy.UNDO_BUTTON)) {
        return
    }
    mutations.runSimple(
        "undoFinish",
        ActionParams.UndoFinish(false),
        showFailure = false,
        progressTitle = UserCopy.UNDOING_PROGRESS,
    ) { done ->
        if (done.ok || done.stale || done.discarded) return@runSimple
        val text = com.ezevillo.gitreview.domain.flattenCliMessage(done.stderr)
        if (text.isEmpty()) {
            UiMessages.error(project, UserCopy.UNDO_ABORT_FAILED)
            return@runSimple
        }
        // Only when the CLI names --force as the escape (same gate as VS Code).
        if (!text.contains("--force")) {
            UiMessages.error(project, text)
            return@runSimple
        }
        if (!UiMessages.confirm(
                project,
                text,
                UserCopy.UNDO_FORCE_DETAIL,
                UserCopy.UNDO_FORCE_BUTTON,
            )
        ) {
            return@runSimple
        }
        mutations.runSimple(
            "undoFinish",
            ActionParams.UndoFinish(true),
            progressTitle = UserCopy.FORCE_UNDOING_PROGRESS,
        )
    }
}

class ResumeFinishAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val state = service(e)?.currentState() ?: return
        val onto = state.finish?.onto == true
        mutations(e)?.runSimple(
            "resumeFinish",
            ActionParams.ResumeFinish(onto),
            progressTitle = UserCopy.RESUME_PROGRESS,
        )
    }
}

class OpenEntryAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        val state = service.currentState()
        val entry = currentEntry(state.entries, state.state?.position) ?: return
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        OpenEntryActions.openEntry(project, state, entry, cwd)
    }
}

class OpenChangeAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        val state = service.currentState()
        val entry = currentEntry(state.entries, state.state?.position) ?: return
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        OpenEntryActions.openChange(project, state, entry, cwd)
    }
}

class OpenAllChangesAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        OpenEntryActions.openAllChanges(project, service.currentState(), cwd)
    }
}

class SetBaseAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        val candidates = service.currentState().candidates
        if (candidates.isNullOrEmpty()) {
            Bg.sync(project, "git review config") { service.refreshNow() }
        }
        val list = service.currentState().candidates
        if (list.isNullOrEmpty()) {
            UiMessages.error(project, UserCopy.NO_BRANCHES_FOR_BASE)
            return
        }
        val sorted = list.sortedWith(
            compareByDescending<com.ezevillo.gitreview.domain.CandidateBranch> { it.current }
                .thenBy { it.name },
        )
        val names = sorted.map { branchPickerLabel(it) }.toTypedArray()
        val idx = UiMessages.choose(
            project,
            UserCopy.SET_BASE_PROMPT,
            UserCopy.SET_BASE_TITLE,
            names,
        )
        if (idx < 0) return
        mutations(e)?.runSimple("setBase", ActionParams.SetConfig("base", sorted[idx].name))
    }
}

class SetRemoteAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        Bg.sync(project, "git review config") { service.refreshNow() }
        val remotes = service.currentState().remotes
        if (remotes.isNullOrEmpty()) {
            UiMessages.error(project, UserCopy.NO_REMOTES)
            return
        }
        val sorted = remotes.sortedWith(
            compareByDescending<com.ezevillo.gitreview.domain.CandidateRemote> { it.current }
                .thenBy { it.name },
        )
        val names = sorted.map {
            if (it.current) "${it.name}  (current)" else it.name
        }.toTypedArray()
        val idx = UiMessages.choose(
            project,
            UserCopy.SET_REMOTE_PROMPT,
            UserCopy.SET_REMOTE_TITLE,
            names,
        )
        if (idx < 0) return
        mutations(e)?.runSimple("setRemote", ActionParams.SetConfig("remote", sorted[idx].name))
    }
}

class CleanReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val pending = service(e)?.currentState()?.let { pendingFinishInfo(it) }
        if (pending != null) {
            confirmAndRun(
                project,
                e,
                HousekeepingAction(HousekeepingKind.CLEAN_KEEP_FIXES, pending.first, onto = pending.second),
            )
            return
        }
        val kinds = arrayOf(UserCopy.CLEAN_ONE_LABEL, UserCopy.CLEAN_ALL_LABEL)
        val idx = UiMessages.choose(
            project,
            "What to delete",
            UserCopy.CLEAN_PICK_TITLE,
            kinds,
        )
        if (idx < 0) return
        val action = when (idx) {
            0 -> {
                val src = pickSourceName(project, service(e), savedOnly = false, forClean = true)
                    ?: return
                HousekeepingAction(HousekeepingKind.CLEAN_ONE, src)
            }
            else -> HousekeepingAction(HousekeepingKind.CLEAN_ALL)
        }
        confirmAndRun(project, e, action)
    }
}

class ForgetReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val kinds = arrayOf(
            UserCopy.FORGET_SAVED_ONE_LABEL,
            UserCopy.FORGET_SAVED_ALL_LABEL,
            UserCopy.FORGET_DELTA_ONE_LABEL,
            UserCopy.FORGET_DELTA_ALL_LABEL,
            UserCopy.FORGET_DELTA_STALE_LABEL,
        )
        val idx = UiMessages.choose(
            project,
            "What to discard",
            UserCopy.FORGET_PICK_TITLE,
            kinds,
        )
        if (idx < 0) return
        val action = when (idx) {
            0 -> {
                val src = pickSourceName(project, service(e), savedOnly = true, forClean = false)
                    ?: return
                HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, src)
            }
            1 -> HousekeepingAction(HousekeepingKind.FORGET_SAVED_ALL)
            2 -> {
                val src = pickSourceName(project, service(e), savedOnly = false, forClean = false)
                    ?: return
                HousekeepingAction(HousekeepingKind.FORGET_DELTA_ONE, src)
            }
            3 -> HousekeepingAction(HousekeepingKind.FORGET_DELTA_ALL)
            else -> HousekeepingAction(HousekeepingKind.FORGET_DELTA_STALE)
        }
        confirmAndRun(project, e, action)
    }
}

class DiscardInventoryAction : AnAction(), DumbAware {
    /**
     * Desde el panel el nombre ya viene de la fila; desde el menú se elige de ese
     * mismo inventario — filtrando al escribir, pero nunca inventando. Este verbo
     * borra ramas, así que un nombre que llega a la CLI sin haber estado en una
     * lista es un nombre que nadie verificó.
     */
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val names = service(e)?.currentState()?.branches.orEmpty()
            .map { it.name }
            .distinct()
        if (names.isEmpty()) {
            UiMessages.error(project, UserCopy.NO_REVIEWS_TO_DISCARD)
            return
        }
        val idx = UiMessages.choose(
            project,
            "Review branch to discard",
            "Discard",
            names.toTypedArray(),
        )
        if (idx < 0) return
        discardResolved(project, names[idx])
    }

    companion object {
        /** Panel path: review name already known from the inventory row. Confirmation still required. */
        fun discardResolved(project: Project, name: String) {
            val src = sourceFromReviewName(name)
            val action = if (name.startsWith("review-saved/")) {
                HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, src)
            } else {
                HousekeepingAction(HousekeepingKind.CLEAN_ONE, src)
            }
            val copy = confirmCopyFor(action)
            if (!UiMessages.confirm(project, copy.title, copy.detail, copy.button)) return
            MutationActions(project, GitReviewService.getInstance(project)).runHousekeeping(action)
        }
    }
}

class PreviewEditsAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        preview(e, stat = false)
    }

    override fun update(e: AnActionEvent) {
        val model = service(e)?.currentModel()
        val sit = model?.situation
        e.presentation.isEnabled =
            model != null &&
                !model.busy &&
                (sit == Situation.REVIEW || sit == Situation.FINISH_CONFLICT)
    }

    override fun getActionUpdateThread() =
        com.intellij.openapi.actionSystem.ActionUpdateThread.BGT
}

class PreviewEditsStatAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        preview(e, stat = true)
    }
}

private fun preview(e: AnActionEvent, stat: Boolean) {
    val project = e.project ?: return
    val cwd = pickSoleGitRoot(project)?.rootPath ?: return
    val service = GitReviewService.getInstance(project)
    val state = service.currentState()
    if (state.situation != Situation.REVIEW && state.situation != Situation.FINISH_CONFLICT) {
        UiMessages.info(project, UserCopy.NO_ACTIVE_PREVIEW)
        return
    }
    val args = if (stat) listOf("--stat") else emptyList()
    val result = Bg.sync(project, "git review preview") {
        service.cliInvoker.invoke("preview", args, cwd)
    }
    if (result.exitCode != 0 || result.timedOut) {
        UiMessages.cliError(
            project,
            result.stderr,
            UserCopy.PREVIEW_FAILED,
            result.stdout,
        )
        return
    }
    val note = result.stderr.trim()
    if (note.isNotEmpty()) {
        UiMessages.info(project, note.lineSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() } ?: note)
    }
    val body = result.stdout.ifEmpty { UserCopy.PREVIEW_EMPTY + "\n" }
    val suffix = if (stat) "-stat.txt" else ".diff"
    val tmp = File.createTempFile("git-review-preview", suffix)
    tmp.writeText(body)
    tmp.deleteOnExit()
    val vf = LocalFileSystem.getInstance().refreshAndFindFileByIoFile(tmp) ?: run {
        UiMessages.info(project, body, "Preview edits")
        return
    }
    FileEditorManager.getInstance(project).openFile(vf, true)
}

class CompareReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        // Las candidatas que la CLI ya reportó, más lo que se tipee: compare toma un
        // commit-ish, así que un tag o un SHA valen — pero mostrar la lista evita que
        // el caso común (una rama) haya que escribirlo de memoria.
        val candidates = service(e)?.currentState()?.candidates.orEmpty()
            .map { it.name }
            .distinct()
            .toTypedArray()
        val lower = UiMessages.chooseOrType(
            project, "Branch, tag or commit", UserCopy.COMPARE_LOWER_TITLE, candidates,
        ) ?: return
        val upper = UiMessages.chooseOrType(
            project, "Branch, tag or commit", UserCopy.COMPARE_UPPER_TITLE, candidates,
        ) ?: return
        val layoutOptions = arrayOf(
            "Walkthrough — guided reading order if the upper tip has a walkthrough",
            "Walkthrough — keys only — only entries marked key (--keys)",
            "Commit by commit — one commit at a time (--step)",
            "Whole diff — entire diff at once (--no-walk)",
        )
        val layoutIdx = UiMessages.choose(
            project,
            UserCopy.COMPARE_LAYOUT_PLACEHOLDER,
            UserCopy.COMPARE_LAYOUT_TITLE,
            layoutOptions,
        )
        if (layoutIdx < 0) return
        val layout = when (layoutIdx) {
            0 -> ReviewLayout.WALK
            1 -> ReviewLayout.KEYS
            2 -> ReviewLayout.STEP
            else -> ReviewLayout.WHOLE
        }
        if (!UiMessages.confirm(
                project,
                UserCopy.compareConfirmTitle(lower, upper, layout),
                UserCopy.COMPARE_CONFIRM_DETAIL,
                UserCopy.COMPARE_BUTTON,
            )
        ) {
            return
        }
        val flags = when (layout) {
            ReviewLayout.STEP -> listOf("--step")
            ReviewLayout.WHOLE -> listOf("--no-walk")
            ReviewLayout.KEYS -> listOf("--keys")
            ReviewLayout.WALK -> emptyList()
        }
        mutations(e)?.runSimple(
            "compareReview",
            ActionParams.Compare(flags, lower, upper),
            progressTitle = UserCopy.comparingProgress(lower, upper),
        )
    }
}

class WalkthroughInitAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val m = mutations(e) ?: return
        val cwd = pickSoleGitRoot(project)?.rootPath
        m.runSimple(
            "walkthroughInit",
            ActionParams.WalkthroughInit(false),
            showFailure = false,
            progressTitle = UserCopy.WALKTHROUGH_INIT_PROGRESS,
        ) { first ->
            if (first.ok) {
                openWalkthroughFile(project, cwd)
                return@runSimple
            }
            if (first.stale || first.discarded) return@runSimple
            val exists = cwd != null && java.io.File(cwd, ".review/walkthrough.md").isFile
            if (!exists) {
                UiMessages.cliError(
                    project,
                    first.stderr,
                    UserCopy.WALKTHROUGH_INIT_FAILED,
                    first.stdout,
                )
                return@runSimple
            }
            if (!UiMessages.confirm(
                    project,
                    UserCopy.WALKTHROUGH_EXISTS_TITLE,
                    UserCopy.WALKTHROUGH_EXISTS_DETAIL,
                    UserCopy.WALKTHROUGH_OVERWRITE_BUTTON,
                )
            ) {
                return@runSimple
            }
            m.runSimple(
                "walkthroughInit",
                ActionParams.WalkthroughInit(true),
                progressTitle = UserCopy.WALKTHROUGH_OVERWRITE_PROGRESS,
            ) { forced ->
                if (forced.ok) openWalkthroughFile(project, cwd)
            }
        }
    }
}

class WalkthroughBuildAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        if (!UiMessages.confirm(
                project,
                UserCopy.WALKTHROUGH_BUILD_TITLE,
                UserCopy.WALKTHROUGH_BUILD_DETAIL,
                UserCopy.WALKTHROUGH_BUILD_BUTTON,
            )
        ) {
            return
        }
        val cwd = pickSoleGitRoot(project)?.rootPath
        mutations(e)?.runSimple(
            "walkthroughBuild",
            progressTitle = UserCopy.WALKTHROUGH_BUILD_PROGRESS,
        ) { done ->
            if (done.ok) {
                UiMessages.info(project, UserCopy.WALKTHROUGH_BUILT)
                openWalkthroughFile(project, cwd)
            }
        }
    }
}

class InstallCliAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        // Same as VS Code: open the install docs ("Other install options").
        BrowserUtil.browse(UserCopy.INSTALL_DOCS_URL)
    }
}

class ShowWhyAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val model = GitReviewService.getInstance(project).currentModel()
        val text = model.why?.text ?: model.why?.state?.id ?: return
        UiMessages.info(project, text, "Why")
    }
}

private fun confirmAndRun(project: Project, e: AnActionEvent, action: HousekeepingAction) {
    val copy = confirmCopyFor(action)
    if (!UiMessages.confirm(project, copy.title, copy.detail, copy.button)) return
    mutations(e)?.runHousekeeping(action)
}

/**
 * A qué rama se le aplica un verbo de housekeeping — una de las reviews que este
 * cliente conoce, y sólo ésas. Un marcador --delta puede sobrevivir a toda rama de
 * review que lo hubiera nombrado, pero tipear ese nombre a ciegas no es la salida:
 * "Forget stale delta markers" es exactamente los marcadores cuya rama ya no
 * existe, y "Forget every delta marker" no pide nombrar nada. El picker filtra
 * mientras se escribe, así que escribir sigue llegando a la fila — sin poder
 * inventar una.
 */
private fun pickSourceName(
    project: Project,
    service: GitReviewService?,
    savedOnly: Boolean,
    forClean: Boolean,
): String? {
    val branches = service?.currentState()?.branches.orEmpty()
    val filtered = if (savedOnly) {
        branches.filter { it.saved || it.name.startsWith("review-saved/") }
    } else {
        branches
    }
    val names = filtered.map { sourceFromReviewName(it.name) }.distinct()
    val title = when {
        forClean -> UserCopy.CLEAN_BRANCH_TITLE
        savedOnly -> UserCopy.FORGET_SAVED_SOURCE_TITLE
        else -> UserCopy.FORGET_DELTA_SOURCE_TITLE
    }
    if (names.isEmpty()) {
        UiMessages.error(
            project,
            when {
                forClean -> UserCopy.NO_REVIEWS_TO_CLEAN
                savedOnly -> UserCopy.NO_SAVED_REVIEWS
                else -> UserCopy.NO_DELTA_SOURCES
            },
        )
        return null
    }
    val idx = UiMessages.choose(project, "Source branch name", title, names.toTypedArray())
    return if (idx < 0) null else names[idx]
}

private fun openWalkthroughFile(project: Project, cwd: String?) {
    if (cwd == null) return
    val file = File(cwd, ".review/walkthrough.md")
    val vf = LocalFileSystem.getInstance().refreshAndFindFileByIoFile(file) ?: return
    FileEditorManager.getInstance(project).openFile(vf, true)
}
