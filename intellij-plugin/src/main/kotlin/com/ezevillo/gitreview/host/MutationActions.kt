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
 *
 * Every runner is asynchronous: the CLI work goes to a pooled thread via [Bg.async]
 * and the optional callback comes back on the EDT, where dialogs are legal.
 */
class MutationActions(
    private val project: Project,
    private val service: GitReviewService,
) {
    fun runStart(intent: ReviewIntent, branch: String, onDone: (StartRunResult) -> Unit) {
        val cwd = cwdOrNull()
        if (cwd == null) {
            onDone(StartRunResult.NoCwd)
            return
        }
        val token = captureToken(service.currentState())
        val path = GitReviewSettings.getInstance().path.ifBlank { null }
        Bg.async(
            project,
            "git review start",
            work = {
                service.mutationLock.run {
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
                } ?: StartRunResult.Busy
            },
            then = onDone,
        )
    }

    fun runSimple(
        action: String,
        params: ActionParams = ActionParams.Empty,
        onDone: ((Boolean) -> Unit)? = null,
    ) {
        val cwd = cwdOrNull()
        if (cwd == null) {
            onDone?.invoke(false)
            return
        }
        val token = captureToken(service.currentState())
        Bg.async(
            project,
            "git review $action",
            work = {
                service.mutationLock.run {
                    service.refreshNow()
                    if (!tokenStillValid(token, service.currentState())) {
                        return@run SimpleOutcome.Stale
                    }
                    val argv = actionToArgv(action, params)
                    if (argv.verb.isEmpty()) return@run SimpleOutcome.Done(false)
                    val result = service.cliInvoker.invoke(
                        argv.verb,
                        argv.args,
                        cwd,
                        network = argv.network,
                    )
                    service.refreshNow()
                    SimpleOutcome.Done(result.exitCode == 0 && !result.timedOut)
                } ?: SimpleOutcome.Discarded
            },
            then = { outcome ->
                if (outcome is SimpleOutcome.Stale) {
                    Messages.showWarningDialog(project, "Review state changed; try again.", "git review")
                }
                onDone?.invoke(outcome is SimpleOutcome.Done && outcome.ok)
            },
        )
    }

    fun runNextPrev(verb: String) {
        if (service.currentState().situation != Situation.REVIEW) return
        runSimple(if (verb == "prev") "prev" else "next")
    }

    fun runHousekeeping(action: HousekeepingAction) {
        runSimple("cleanReview", ActionParams.Housekeeping(action))
    }

    /** Reports the finish outcome as a message, or `null` when there was nothing to say. */
    fun runFinish(ontoSource: Boolean, onDone: (String?) -> Unit) {
        val branch = service.currentState().state?.branch
        if (branch == null) {
            onDone(null)
            return
        }
        runSimple("finishReview", ActionParams.FinishOnto(ontoSource)) { ok ->
            if (!ok) {
                onDone(null)
                return@runSimple
            }
            val fixes = branch.replace("review/", "review-fixes/")
            onDone(
                when (finishOutcome(service.currentState(), fixes)) {
                    com.ezevillo.gitreview.domain.FinishOutcome.PENDING ->
                        "Finish pending — edits extracted (or empty extract)."
                    com.ezevillo.gitreview.domain.FinishOutcome.NO_EDITS -> "Finish completed."
                },
            )
        }
    }

    fun requireReadable(): Boolean = isReviewReadable(service.currentState().situation)

    private fun cwdOrNull(): String? = pickSoleGitRoot(project)?.rootPath
}

/** What a [MutationActions.runSimple] attempt ended up doing, before it reaches the EDT. */
private sealed class SimpleOutcome {
    data object Discarded : SimpleOutcome()
    data object Stale : SimpleOutcome()
    data class Done(val ok: Boolean) : SimpleOutcome()
}

sealed class StartRunResult {
    data object Ok : StartRunResult()
    data object Busy : StartRunResult()
    data object Stale : StartRunResult()
    data object NoCwd : StartRunResult()
    data class Network(val command: String, val args: List<String>, val stderr: String) : StartRunResult()
    data class Failed(val stderr: String) : StartRunResult()
}
