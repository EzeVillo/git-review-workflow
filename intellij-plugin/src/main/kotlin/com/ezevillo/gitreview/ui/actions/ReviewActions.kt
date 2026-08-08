package com.ezevillo.gitreview.ui.actions

import com.ezevillo.gitreview.diff.OpenEntryActions
import com.ezevillo.gitreview.domain.ActionParams
import com.ezevillo.gitreview.domain.HousekeepingAction
import com.ezevillo.gitreview.domain.HousekeepingKind
import com.ezevillo.gitreview.domain.confirmCopyFor
import com.ezevillo.gitreview.domain.currentEntry
import com.ezevillo.gitreview.domain.entryPickLabel
import com.ezevillo.gitreview.domain.pendingFinishInfo
import com.ezevillo.gitreview.domain.resumableSourceAt
import com.ezevillo.gitreview.domain.sourceFromReviewName
import com.ezevillo.gitreview.host.GitReviewService
import com.ezevillo.gitreview.host.MutationActions
import com.ezevillo.gitreview.ui.StartWizard
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.ui.Messages

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
        val idx = Messages.showChooseDialog(
            project,
            "Go to entry",
            "git review",
            Messages.getQuestionIcon(),
            labels,
            labels.first(),
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
            Messages.showInfoMessage(project, "No saved reviews.", "git review")
            return
        }
        val labels = branches.mapIndexed { i, b ->
            val src = resumableSourceAt(branches, i)
            "${b.name}" + if (src != null) " (resumable)" else ""
        }.toTypedArray()
        val idx = Messages.showChooseDialog(
            project,
            "Continue which saved review?",
            "git review",
            Messages.getQuestionIcon(),
            labels,
            labels.first(),
        )
        if (idx < 0) return
        val source = resumableSourceAt(branches, idx) ?: run {
            Messages.showErrorDialog(project, "That review is not resumable.", "git review")
            return
        }
        val confirm = Messages.showYesNoDialog(
            project,
            "Continue saved review $source?",
            "git review",
            Messages.getQuestionIcon(),
        )
        if (confirm != Messages.YES) return
        mutations(e)?.runSimple("continueReview", ActionParams.Continue(source))
    }
}

class FinishReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val onto = Messages.showYesNoDialog(
            project,
            "Extract edits onto the PR branch (--onto-source)?\nChoose No for review-fixes/*.",
            "Finish Review",
            "Onto source",
            "review-fixes",
            Messages.getQuestionIcon(),
        )
        // YES = onto-source, NO = default destination
        val msg = mutations(e)?.runFinish(onto == Messages.YES)
        if (msg != null) {
            Messages.showInfoMessage(project, msg, "git review")
        }
    }
}

class AbortReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val ok = Messages.showYesNoDialog(
            project,
            "Cancel the active review? Uncommitted edits may be lost.",
            "Cancel Review",
            Messages.getWarningIcon(),
        )
        if (ok != Messages.YES) return
        mutations(e)?.runSimple("abortReview")
    }
}

class SaveReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val ok = Messages.showYesNoDialog(
            project,
            "Save this review for later?",
            "Save Review",
            Messages.getQuestionIcon(),
        )
        if (ok != Messages.YES) return
        mutations(e)?.runSimple("saveReview")
    }
}

class UndoFinishAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val m = mutations(e) ?: return
        if (!m.runSimple("undoFinish", ActionParams.UndoFinish(false))) {
            val force = Messages.showYesNoDialog(
                e.project,
                "Undo finish failed. Force (--force)?",
                "Undo Finish",
                Messages.getWarningIcon(),
            )
            if (force == Messages.YES) {
                m.runSimple("undoFinish", ActionParams.UndoFinish(true))
            }
        }
    }
}

class ResumeFinishAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val state = service(e)?.currentState() ?: return
        val onto = state.finish?.onto == true
        mutations(e)?.runSimple("resumeFinish", ActionParams.ResumeFinish(onto))
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
            // Ensure config is loaded
            service.refreshNow()
        }
        val list = service.currentState().candidates
        if (list.isNullOrEmpty()) {
            Messages.showErrorDialog(
                project,
                "No branches to pick a base from were found.",
                "git review",
            )
            return
        }
        val names = list.map { "${it.name} (${it.origin})" }.toTypedArray()
        val idx = Messages.showChooseDialog(
            project,
            "Base branch",
            "Set the Base Branch",
            Messages.getQuestionIcon(),
            names,
            names.first(),
        )
        if (idx < 0) return
        mutations(e)?.runSimple("setBase", ActionParams.SetConfig("base", list[idx].name))
    }
}

class SetRemoteAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val service = GitReviewService.getInstance(project)
        service.refreshNow()
        val remotes = service.currentState().remotes
        if (remotes.isNullOrEmpty()) {
            Messages.showErrorDialog(project, "No remotes found.", "git review")
            return
        }
        val names = remotes.map { it.name }.toTypedArray()
        val idx = Messages.showChooseDialog(
            project,
            "Remote",
            "Set the Remote",
            Messages.getQuestionIcon(),
            names,
            names.first(),
        )
        if (idx < 0) return
        mutations(e)?.runSimple("setRemote", ActionParams.SetConfig("remote", names[idx]))
    }
}

class CleanReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val kinds = arrayOf(
            "Clean one source",
            "Clean keep-fixes (pending finish)",
            "Clean all",
        )
        val idx = Messages.showChooseDialog(
            project,
            "Clean",
            "git review",
            Messages.getQuestionIcon(),
            kinds,
            kinds[0],
        )
        if (idx < 0) return
        val action = when (idx) {
            0 -> {
                val src = Messages.showInputDialog(project, "Source name:", "Clean", null) ?: return
                HousekeepingAction(HousekeepingKind.CLEAN_ONE, src)
            }
            1 -> {
                val info = service(e)?.currentState()?.let { pendingFinishInfo(it) }
                val src = info?.first
                    ?: Messages.showInputDialog(project, "Source name:", "Clean keep-fixes", null)
                    ?: return
                HousekeepingAction(HousekeepingKind.CLEAN_KEEP_FIXES, src, onto = info?.second)
            }
            else -> HousekeepingAction(HousekeepingKind.CLEAN_ALL)
        }
        val copy = confirmCopyFor(action)
        if (Messages.showYesNoDialog(project, copy.detail, copy.title, Messages.getWarningIcon()) != Messages.YES) {
            return
        }
        mutations(e)?.runHousekeeping(action)
    }
}

class ForgetReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val kinds = arrayOf(
            "Forget one saved",
            "Forget all saved",
            "Forget one delta",
            "Forget all deltas",
            "Forget stale deltas",
        )
        val idx = Messages.showChooseDialog(
            project,
            "Forget",
            "git review",
            Messages.getQuestionIcon(),
            kinds,
            kinds[0],
        )
        if (idx < 0) return
        val action = when (idx) {
            0 -> {
                val src = Messages.showInputDialog(project, "Source:", "Forget saved", null) ?: return
                HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, src)
            }
            1 -> HousekeepingAction(HousekeepingKind.FORGET_SAVED_ALL)
            2 -> {
                val src = Messages.showInputDialog(project, "Source:", "Forget delta", null) ?: return
                HousekeepingAction(HousekeepingKind.FORGET_DELTA_ONE, src)
            }
            3 -> HousekeepingAction(HousekeepingKind.FORGET_DELTA_ALL)
            else -> HousekeepingAction(HousekeepingKind.FORGET_DELTA_STALE)
        }
        val copy = confirmCopyFor(action)
        if (Messages.showYesNoDialog(project, copy.detail, copy.title, Messages.getWarningIcon()) != Messages.YES) {
            return
        }
        mutations(e)?.runHousekeeping(action)
    }
}

class DiscardInventoryAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val name = Messages.showInputDialog(project, "Review branch name to discard:", "Discard", null) ?: return
        val src = sourceFromReviewName(name)
        val action = if (name.startsWith("review-saved/")) {
            HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, src)
        } else {
            HousekeepingAction(HousekeepingKind.CLEAN_ONE, src)
        }
        val copy = confirmCopyFor(action)
        if (Messages.showYesNoDialog(project, copy.detail, copy.title, Messages.getWarningIcon()) != Messages.YES) {
            return
        }
        mutations(e)?.runHousekeeping(action)
    }
}

class PreviewEditsAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        val service = GitReviewService.getInstance(project)
        val result = service.cliInvoker.invoke("preview", emptyList(), cwd)
        Messages.showInfoMessage(project, result.stdout.ifBlank { result.stderr }, "Preview Edits")
    }
}

class PreviewEditsStatAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val cwd = pickSoleGitRoot(project)?.rootPath ?: return
        val service = GitReviewService.getInstance(project)
        val result = service.cliInvoker.invoke("preview", listOf("--stat"), cwd)
        Messages.showInfoMessage(project, result.stdout.ifBlank { result.stderr }, "Preview Edits (stat)")
    }
}

class CompareReviewAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val lower = Messages.showInputDialog(project, "Lower bound (commit/ref):", "Compare", null) ?: return
        val upper = Messages.showInputDialog(project, "Upper bound (commit/ref):", "Compare", null) ?: return
        mutations(e)?.runSimple(
            "compareReview",
            ActionParams.Compare(emptyList(), lower, upper),
        )
        Messages.showInfoMessage(
            project,
            "Compare is read-only. Use the review panel to navigate.",
            "git review",
        )
    }
}

class WalkthroughInitAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val force = Messages.showYesNoDialog(
            project,
            "Force overwrite existing walkthrough?",
            "Walkthrough Init",
            Messages.getQuestionIcon(),
        ) == Messages.YES
        mutations(e)?.runSimple("walkthroughInit", ActionParams.WalkthroughInit(force))
    }
}

class WalkthroughBuildAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        mutations(e)?.runSimple("walkthroughBuild")
    }
}

class InstallCliAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        Messages.showInfoMessage(
            project,
            "Install: npm install -g git-review-workflow\n" +
                "Update: npm install -g git-review-workflow@latest\n\n" +
                "Other options: https://github.com/EzeVillo/git-review-workflow#readme",
            "How to Install the CLI",
        )
    }
}

class ShowWhyAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val model = GitReviewService.getInstance(project).currentModel()
        val text = model.why?.text ?: model.why?.state?.id ?: "(no why)"
        Messages.showInfoMessage(project, text, "Why")
    }
}
