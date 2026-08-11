package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.diff.OpenEntryActions
import com.ezevillo.gitreview.domain.ActionParams
import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.HousekeepingAction
import com.ezevillo.gitreview.domain.HousekeepingKind
import com.ezevillo.gitreview.domain.NPM_INSTALL_CMD
import com.ezevillo.gitreview.domain.NPM_UPDATE_CMD
import com.ezevillo.gitreview.domain.PanelModel
import com.ezevillo.gitreview.domain.ReviewMode
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.SupportLinks
import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.confirmCopyFor
import com.ezevillo.gitreview.domain.currentEntry
import com.ezevillo.gitreview.domain.pendingFinishInfo
import com.ezevillo.gitreview.domain.requiresConfirmation
import com.ezevillo.gitreview.domain.resumableSourceAt
import com.ezevillo.gitreview.domain.sourceFromReviewName
import com.ezevillo.gitreview.host.GitReviewService
import com.ezevillo.gitreview.host.MutationActions
import com.ezevillo.gitreview.ui.actions.runUndoFinish
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.ide.BrowserUtil
import com.intellij.openapi.ide.CopyPasteManager
import com.intellij.openapi.project.Project
import java.awt.datatransfer.StringSelection

/**
 * Routes [ControlId] (+ optional index) to existing host actions.
 * Returns true when the caller should show transient "Copied" feedback.
 *
 * Confirmations and error/success toasts use the same English copy as VS Code.
 */
class PanelActionDispatcher(
    private val project: Project,
    private val service: GitReviewService,
) {
    private val mutations = MutationActions(project, service)

    fun dispatch(id: ControlId, index: Int?, supportLinkId: String? = null): Boolean {
        // Guard: confirmation path must run when required (FR-032)
        if (requiresConfirmation(id)) {
            // Actual dialog is inside the routed action (or here for index-resolved paths)
        }
        return when (id) {
            ControlId.REFRESH -> {
                service.scheduleRefresh()
                false
            }
            ControlId.NEXT -> {
                mutations.runNextPrev("next")
                false
            }
            ControlId.PREV -> {
                mutations.runNextPrev("prev")
                false
            }
            ControlId.OPEN_ENTRY -> {
                openEntry()
                false
            }
            ControlId.OPEN_CHANGE -> {
                openChange(index)
                false
            }
            ControlId.OPEN_ALL_CHANGES -> {
                openAll()
                false
            }
            ControlId.SHOW_WHY -> {
                val text = modelWhy() ?: return false
                UiMessages.info(project, text, "Why")
                false
            }
            ControlId.START_REVIEW -> {
                StartWizard.run(project)
                false
            }
            ControlId.CONTINUE_REVIEW -> {
                continueAt(index)
                false
            }
            ControlId.DISCARD_INVENTORY -> {
                discardAt(index)
                false
            }
            ControlId.SET_BASE -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.SetBaseAction")
                false
            }
            ControlId.SET_REMOTE -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.SetRemoteAction")
                false
            }
            ControlId.UNDO_FINISH -> {
                runUndoFinish(project, mutations, service.currentState().situation)
                false
            }
            ControlId.RESUME_FINISH -> {
                val state = service.currentState()
                val onto = state.finish?.onto == true
                mutations.runSimple(
                    "resumeFinish",
                    ActionParams.ResumeFinish(onto),
                    progressTitle = UserCopy.RESUME_PROGRESS,
                )
                false
            }
            ControlId.CLEAN_REVIEW -> {
                cleanPending(service.currentModel())
                false
            }
            ControlId.FINISH_REVIEW -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.FinishReviewAction")
                false
            }
            ControlId.SAVE_REVIEW -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.SaveReviewAction")
                false
            }
            ControlId.ABORT_REVIEW -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.AbortReviewAction")
                false
            }
            ControlId.PREVIEW_EDITS -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.PreviewEditsAction")
                false
            }
            ControlId.COMPARE_REVIEW -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.CompareReviewAction")
                false
            }
            ControlId.WALKTHROUGH_INIT -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.WalkthroughInitAction")
                false
            }
            ControlId.WALKTHROUGH_BUILD -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.WalkthroughBuildAction")
                false
            }
            ControlId.INSTALL_CLI -> {
                invokeAction("com.ezevillo.gitreview.ui.actions.InstallCliAction")
                false
            }
            ControlId.COPY_CLI_INSTALL -> {
                val cmd = if (service.currentModel().situation == Situation.CLI_OUTDATED) {
                    NPM_UPDATE_CMD
                } else {
                    NPM_INSTALL_CMD
                }
                CopyPasteManager.getInstance().setContents(StringSelection(cmd))
                true
            }
            ControlId.OUT_OF_RANGE_HELP -> {
                val stderr = service.currentModel().stderr?.trim().orEmpty()
                val text = if (stderr.isNotEmpty()) stderr else UserCopy.OUT_OF_RANGE_FALLBACK
                // VS Code uses a warning toast for the diagnostic.
                UiMessages.warning(project, text, "How to fix it")
                false
            }
            ControlId.OPEN_SUPPORT -> {
                val url = SupportLinks.urlFor(supportLinkId) ?: SupportLinks.STAR_URL
                BrowserUtil.browse(url)
                false
            }
        }
    }

    private fun modelWhy(): String? = service.currentModel().why?.text

    private fun openEntry() {
        val state = service.currentState()
        val entry = currentEntry(state.entries, state.state?.position) ?: return
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        OpenEntryActions.openEntry(project, state, entry, cwd)
    }

    private fun openChange(index: Int?) {
        val state = service.currentState()
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        // Step + index: position is within the current commit's file list, not
        // the commit sequence (entries). Whole + index: entries are the files.
        val entry = if (index != null) {
            if (state.state?.mode == ReviewMode.STEP) {
                state.files.find { it.position == index }
            } else {
                state.entries.find { it.position == index }
            }
        } else {
            currentEntry(state.entries, state.state?.position)
        } ?: return
        OpenEntryActions.openChange(project, state, entry, cwd)
    }

    private fun openAll() {
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        OpenEntryActions.openAllChanges(project, service.currentState(), cwd)
    }

    private fun continueAt(index: Int?) {
        val branches = service.currentState().branches
        val source = resumableSourceAt(branches, index) ?: run {
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
        mutations.runSimple(
            "continueReview",
            ActionParams.Continue(source),
            progressTitle = UserCopy.continuingProgress(source),
        )
    }

    private fun discardAt(index: Int?) {
        if (index == null) return
        val review = service.currentModel().reviews.getOrNull(index) ?: return
        val name = review.name
        val src = sourceFromReviewName(name)
        val action = if (name.startsWith("review-saved/")) {
            HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, src)
        } else {
            HousekeepingAction(HousekeepingKind.CLEAN_ONE, src)
        }
        val copy = confirmCopyFor(action)
        if (!UiMessages.confirm(project, copy.title, copy.detail, copy.button)) return
        mutations.runHousekeeping(action)
    }

    private fun cleanPending(model: PanelModel) {
        val info = pendingFinishInfo(service.currentState())
        val src = info?.first
            ?: model.pendingFinish?.branch?.let { sourceFromReviewName(it) }
            ?: return
        val action = HousekeepingAction(HousekeepingKind.CLEAN_KEEP_FIXES, src, onto = info?.second)
        val copy = confirmCopyFor(action)
        if (!UiMessages.confirm(project, copy.title, copy.detail, copy.button)) return
        mutations.runHousekeeping(action)
    }

    private fun invokeAction(className: String) {
        try {
            val clazz = Class.forName(className)
            val action = clazz.getDeclaredConstructor().newInstance() as com.intellij.openapi.actionSystem.AnAction
            val dataContext = com.intellij.openapi.actionSystem.impl.SimpleDataContext.builder()
                .add(com.intellij.openapi.actionSystem.CommonDataKeys.PROJECT, project)
                .build()
            val event = com.intellij.openapi.actionSystem.AnActionEvent.createFromAnAction(
                action,
                null,
                "GitReview.Panel",
                dataContext,
            )
            action.actionPerformed(event)
        } catch (e: Exception) {
            UiMessages.error(project, e.message ?: "Action failed.")
        }
    }
}
