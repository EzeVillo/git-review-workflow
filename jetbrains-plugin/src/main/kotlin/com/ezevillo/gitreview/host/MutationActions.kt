package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.ActionParams
import com.ezevillo.gitreview.domain.FinishOutcome
import com.ezevillo.gitreview.domain.HousekeepingAction
import com.ezevillo.gitreview.domain.ReviewIntent
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.StartFailureCategory
import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.actionToArgv
import com.ezevillo.gitreview.domain.captureToken
import com.ezevillo.gitreview.domain.classifyStartFailure
import com.ezevillo.gitreview.domain.cliErrorText
import com.ezevillo.gitreview.domain.finishOutcome
import com.ezevillo.gitreview.domain.firstCliLine
import com.ezevillo.gitreview.domain.flattenCliMessage
import com.ezevillo.gitreview.domain.isReviewReadable
import com.ezevillo.gitreview.domain.resolveCommand
import com.ezevillo.gitreview.domain.tokenStillValid
import com.ezevillo.gitreview.settings.GitReviewSettings
import com.ezevillo.gitreview.ui.UiMessages
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.openapi.project.Project

/**
 * Host-side mutation runners: lock + stale guard + invoke + refresh.
 *
 * Every runner is asynchronous: the CLI work goes to a pooled thread via [Bg.async]
 * and the optional callback comes back on the EDT, where dialogs are legal.
 *
 * Failure / stale toasts use the same English copy as the VS Code extension
 * ([UserCopy]); CLI stderr is shown unredacted (FR-024).
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
            UserCopy.startingProgress(branch),
            work = {
                service.mutationLock.run {
                    service.refreshNow()
                    if (!tokenStillValid(token, service.currentState())) {
                        return@run StartRunResult.Stale
                    }
                    val situation = service.currentState().situation
                    if (situation != Situation.NO_REVIEW && situation != Situation.FINISH_PENDING) {
                        return@run StartRunResult.Stale
                    }
                    val argv = actionToArgv("startReview", ActionParams.Start(intent, branch))
                    val result = service.cliInvoker.invoke(argv.verb, argv.args, cwd, network = true)
                    service.refreshNow()
                    if (result.exitCode == 0 && !result.timedOut) {
                        val note = flattenCliMessage(result.stderr)
                        StartRunResult.Ok(note.takeIf { it.isNotEmpty() })
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

    /**
     * @param showFailure when false, the caller handles non-zero exits (undo-force path).
     * @param showStale when false, the caller handles the stale toast.
     */
    fun runSimple(
        action: String,
        params: ActionParams = ActionParams.Empty,
        showFailure: Boolean = true,
        showStale: Boolean = true,
        progressTitle: String? = null,
        onDone: ((MutationDone) -> Unit)? = null,
    ) {
        val cwd = cwdOrNull()
        if (cwd == null) {
            onDone?.invoke(MutationDone(ok = false, stderr = "", stdout = "", noCwd = true))
            return
        }
        val token = captureToken(service.currentState())
        val title = progressTitle ?: "git review $action"
        Bg.async(
            project,
            title,
            work = {
                service.mutationLock.run {
                    service.refreshNow()
                    if (!tokenStillValid(token, service.currentState())) {
                        return@run SimpleOutcome.Stale
                    }
                    val argv = actionToArgv(action, params)
                    if (argv.verb.isEmpty()) return@run SimpleOutcome.Done(MutationDone(false))
                    val result = service.cliInvoker.invoke(
                        argv.verb,
                        argv.args,
                        cwd,
                        network = argv.network,
                    )
                    service.refreshNow()
                    SimpleOutcome.Done(
                        MutationDone(
                            ok = result.exitCode == 0 && !result.timedOut,
                            stderr = result.stderr,
                            stdout = result.stdout,
                        ),
                    )
                } ?: SimpleOutcome.Discarded
            },
            then = { outcome ->
                when (outcome) {
                    SimpleOutcome.Discarded -> {
                        // FR-036: discard toast is owned by GitReviewService.onDidDiscard.
                        onDone?.invoke(MutationDone(ok = false, discarded = true))
                    }
                    SimpleOutcome.Stale -> {
                        if (showStale) {
                            UiMessages.info(project, UserCopy.STALE)
                        }
                        onDone?.invoke(MutationDone(ok = false, stale = true))
                    }
                    is SimpleOutcome.Done -> {
                        if (!outcome.done.ok && showFailure && !outcome.done.discarded) {
                            UiMessages.cliError(
                                project,
                                outcome.done.stderr,
                                UserCopy.failureFallback(action, params),
                                outcome.done.stdout,
                            )
                        }
                        onDone?.invoke(outcome.done)
                    }
                }
            },
        )
    }

    fun runNextPrev(verb: String) {
        if (service.currentState().situation != Situation.REVIEW) return
        val before = service.currentState().state?.position
        runSimple(
            if (verb == "prev") "prev" else "next",
            showFailure = false,
        ) { done ->
            if (done.stale || done.discarded || done.noCwd) return@runSimple
            if (!done.ok) {
                // VS Code uses information (not error) for next/prev failures.
                val text = cliErrorText(done.stderr, done.stdout, UserCopy.navigateFailed(verb))
                UiMessages.info(project, text)
                return@runSimple
            }
            val after = service.currentState().state?.position
            if (after == before) {
                val message = firstCliLine(done.stdout)
                if (message.isNotEmpty()) {
                    UiMessages.info(project, message)
                }
            }
        }
    }

    fun runHousekeeping(action: HousekeepingAction) {
        runSimple("cleanReview", ActionParams.Housekeeping(action))
    }

    /**
     * Finish with VS Code success toasts derived from refreshed state only
     * (never from finish human stdout).
     */
    fun runFinish(ontoSource: Boolean, onDone: (String?) -> Unit) {
        val stateRec = service.currentState().state
        if (stateRec == null) {
            onDone(null)
            return
        }
        if (service.currentState().readonly == true) {
            UiMessages.info(project, UserCopy.READONLY_FINISH)
            onDone(null)
            return
        }
        val reviewBranch = stateRec.branch
        val source = stateRec.source
        runSimple(
            "finishReview",
            ActionParams.FinishOnto(ontoSource),
            progressTitle = UserCopy.finishingProgress(source),
        ) { done ->
            if (!done.ok) {
                onDone(null)
                return@runSimple
            }
            val destination = UserCopy.finishDestination(ontoSource, source)
            val outcome = finishOutcome(service.currentState(), reviewBranch)
            val msg = UserCopy.finishSuccess(destination, outcome)
            onDone(msg)
        }
    }

    fun requireReadable(): Boolean = isReviewReadable(service.currentState().situation)

    private fun cwdOrNull(): String? = pickSoleGitRoot(project)?.rootPath
}

/** Result of a [MutationActions.runSimple] attempt, delivered on the EDT. */
data class MutationDone(
    val ok: Boolean,
    val stderr: String = "",
    val stdout: String = "",
    val stale: Boolean = false,
    val discarded: Boolean = false,
    val noCwd: Boolean = false,
)

/** What a [MutationActions.runSimple] attempt ended up doing, before it reaches the EDT. */
private sealed class SimpleOutcome {
    data object Discarded : SimpleOutcome()
    data object Stale : SimpleOutcome()
    data class Done(val done: MutationDone) : SimpleOutcome()
}

sealed class StartRunResult {
    data class Ok(val note: String? = null) : StartRunResult()
    data object Busy : StartRunResult()
    data object Stale : StartRunResult()
    data object NoCwd : StartRunResult()
    data class Network(val command: String, val args: List<String>, val stderr: String) : StartRunResult()
    data class Failed(val stderr: String) : StartRunResult()
}

/** Exposed for tests: pending vs residual toast after a successful finish. */
fun finishSuccessCopy(ontoSource: Boolean, source: String, outcome: FinishOutcome): String =
    UserCopy.finishSuccess(UserCopy.finishDestination(ontoSource, source), outcome)
