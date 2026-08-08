package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.ActionParams
import com.ezevillo.gitreview.domain.HousekeepingAction
import com.ezevillo.gitreview.domain.ReviewIntent
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.actionToArgv
import com.ezevillo.gitreview.domain.captureToken
import com.ezevillo.gitreview.domain.classifyStartFailure
import com.ezevillo.gitreview.domain.finishOutcome
import com.ezevillo.gitreview.domain.isReviewReadable
import com.ezevillo.gitreview.domain.resolveCommand
import com.ezevillo.gitreview.domain.tokenStillValid
import com.ezevillo.gitreview.domain.StartFailureCategory
import com.ezevillo.gitreview.settings.GitReviewSettings
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages

/**
 * Host-side mutation runners: lock + stale guard + invoke + refresh.
 */
class MutationActions(
    private val project: Project,
    private val service: GitReviewService,
) {
    fun runStart(intent: ReviewIntent, branch: String): StartRunResult {
        val cwd = cwdOrNull() ?: return StartRunResult.NoCwd
        val token = captureToken(service.currentState())
        val path = GitReviewSettings.getInstance().path.ifBlank { null }
        val locked = service.mutationLock.run {
            service.refreshNow()
            if (!tokenStillValid(token, service.currentState())) {
                return@run StartRunResult.Stale
            }
            val argv = actionToArgv("startReview", ActionParams.Start(intent, branch))
            val result = service.cliInvoker.invoke(argv.verb, argv.args, cwd, network = true)
            service.refreshNow()
            if (result.exitCode == 0 && !result.timedOut) {
                StartRunResult.Ok
            } else if (classifyStartFailure(result.stderr) == StartFailureCategory.NETWORK) {
                val resolved = resolveCommand(argv.verb, argv.args, path)
                StartRunResult.Network(resolved.command, resolved.args, result.stderr)
            } else {
                StartRunResult.Failed(result.stderr)
            }
        }
        return locked ?: StartRunResult.Busy
    }

    fun runSimple(action: String, params: ActionParams = ActionParams.Empty): Boolean {
        val cwd = cwdOrNull() ?: return false
        val token = captureToken(service.currentState())
        val ran = service.mutationLock.run {
            service.refreshNow()
            if (!tokenStillValid(token, service.currentState())) {
                Messages.showWarningDialog(project, "Review state changed; try again.", "git review")
                return@run false
            }
            val argv = actionToArgv(action, params)
            if (argv.verb.isEmpty()) return@run false
            val result = service.cliInvoker.invoke(
                argv.verb,
                argv.args,
                cwd,
                network = argv.network,
            )
            service.refreshNow()
            result.exitCode == 0 && !result.timedOut
        }
        return ran == true
    }

    fun runNextPrev(verb: String): Boolean {
        if (service.currentState().situation != Situation.REVIEW) return false
        return runSimple(if (verb == "prev") "prev" else "next")
    }

    fun runHousekeeping(action: HousekeepingAction): Boolean {
        return runSimple("cleanReview", ActionParams.Housekeeping(action))
    }

    fun runFinish(ontoSource: Boolean): String? {
        val before = service.currentState()
        val branch = before.state?.branch ?: return null
        val ok = runSimple("finishReview", ActionParams.FinishOnto(ontoSource))
        if (!ok) return null
        return when (finishOutcome(service.currentState(), branch.replace("review/", "review-fixes/"))) {
            com.ezevillo.gitreview.domain.FinishOutcome.PENDING -> "Finish pending — edits extracted (or empty extract)."
            com.ezevillo.gitreview.domain.FinishOutcome.NO_EDITS -> "Finish completed."
        }
    }

    fun requireReadable(): Boolean = isReviewReadable(service.currentState().situation)

    private fun cwdOrNull(): String? = pickSoleGitRoot(project)?.rootPath
}

sealed class StartRunResult {
    data object Ok : StartRunResult()
    data object Busy : StartRunResult()
    data object Stale : StartRunResult()
    data object NoCwd : StartRunResult()
    data class Network(val command: String, val args: List<String>, val stderr: String) : StartRunResult()
    data class Failed(val stderr: String) : StartRunResult()
}
