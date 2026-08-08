package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.ReviewIntent
import com.ezevillo.gitreview.domain.ReviewRange
import com.ezevillo.gitreview.domain.ReviewSource
import com.ezevillo.gitreview.domain.branchPickerItems
import com.ezevillo.gitreview.domain.branchPickerLabel
import com.ezevillo.gitreview.domain.buildLayoutItems
import com.ezevillo.gitreview.domain.formatCommandLine
import com.ezevillo.gitreview.domain.offerConfigFlags
import com.ezevillo.gitreview.domain.parseConfigPorcelain
import com.ezevillo.gitreview.domain.resolveDefaultSource
import com.ezevillo.gitreview.domain.SourcePreferenceLevels
import com.ezevillo.gitreview.domain.deltaForSource
import com.ezevillo.gitreview.domain.validateIntent
import com.ezevillo.gitreview.domain.IntentValidationContext
import com.ezevillo.gitreview.domain.IntentValidationResult
import com.ezevillo.gitreview.host.Bg
import com.ezevillo.gitreview.host.GitReviewService
import com.ezevillo.gitreview.host.MutationActions
import com.ezevillo.gitreview.host.StartRunResult
import com.ezevillo.gitreview.settings.GitReviewSettings
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages

/**
 * Multi-step start wizard (dialogs). Branch list comes from
 * `git review config --porcelain` candidates — same source as the VS Code
 * start assistant — not free-text input.
 */
object StartWizard {
    fun run(project: Project) {
        val service = GitReviewService.getInstance(project)
        val cwd = pickSoleGitRoot(project)?.rootPath
        if (cwd == null) {
            Messages.showErrorDialog(project, "Need a single git repository root.", "git review")
            return
        }

        // Fresh config --porcelain (config + candidates), not the panel cache.
        val bootstrap = Bg.sync(project, "git review config") {
            service.cliInvoker.invoke("config", listOf("--porcelain"), cwd)
        }
        if (bootstrap.exitCode != 0 || bootstrap.timedOut) {
            val text = bootstrap.stderr.trim().ifEmpty { "Could not read the review configuration." }
            Messages.showErrorDialog(project, text, "git review")
            return
        }
        val parsed = try {
            parseConfigPorcelain(bootstrap.stdout)
        } catch (e: Exception) {
            Messages.showErrorDialog(
                project,
                e.message ?: "Could not parse the review configuration.",
                "git review",
            )
            return
        }

        if (parsed.config.base == null) {
            Messages.showErrorDialog(
                project,
                "Configure a base branch first (git review → Set the Base Branch).",
                "git review",
            )
            return
        }

        val branches = branchPickerItems(parsed.candidates)
        if (branches.isEmpty()) {
            Messages.showErrorDialog(
                project,
                "No branches to pick a review from were found.",
                "git review",
            )
            return
        }
        val branchLabels = branches.map { branchPickerLabel(it) }.toTypedArray()
        val branchIdx = Messages.showChooseDialog(
            project,
            "Branch to review",
            "Start a Review",
            Messages.getQuestionIcon(),
            branchLabels,
            branchLabels.first(),
        )
        if (branchIdx < 0) return
        val branch = branches[branchIdx].name

        val sources = arrayOf("remote", "local", "offline")
        val defaultSrc = resolveDefaultSource(
            SourcePreferenceLevels(globalValue = GitReviewSettings.getInstance().defaultSource),
        ).id
        val sourceIdx = Messages.showChooseDialog(
            project,
            "Source",
            "Start a Review",
            Messages.getQuestionIcon(),
            sources,
            defaultSrc,
        )
        if (sourceIdx < 0) return
        val source = ReviewSource.parse(sources[sourceIdx]) ?: ReviewSource.REMOTE

        // Probe offers for layout
        val flags = offerConfigFlags(source, ReviewRange.FULL).toMutableList()
        flags.add(0, "--porcelain")
        flags.add("--")
        flags.add(branch)
        val cfgResult = Bg.sync(project, "git review config") {
            service.cliInvoker.invoke("config", flags, cwd)
        }
        val offers = if (cfgResult.exitCode == 0) {
            try {
                parseConfigPorcelain(cfgResult.stdout).offers
            } catch (_: Exception) {
                null
            }
        } else null

        val items = buildLayoutItems(offers)
        val labels = items.map { it.label }.toTypedArray()
        val layoutIdx = Messages.showChooseDialog(
            project,
            "Reading layout",
            "Start a Review",
            Messages.getQuestionIcon(),
            labels,
            labels.first(),
        )
        if (layoutIdx < 0) return
        val layout = items[layoutIdx].layout

        val rangeChoice = Messages.showYesNoDialog(
            project,
            "Review only changes since the last tip (--delta)?",
            "Start a Review",
            "Full",
            "Delta",
            Messages.getQuestionIcon(),
        )
        // YesNo: YES=0 (Full), NO=1 (Delta) — inverted labels carefully
        val range = if (rangeChoice == Messages.NO) ReviewRange.DELTA else ReviewRange.FULL

        val intent = ReviewIntent(
            branch = branch,
            layout = layout,
            range = range,
            source = source,
        )

        val delta = if (range == ReviewRange.DELTA) {
            val probe = Bg.sync(project, "git review config") {
                service.cliInvoker.invoke(
                    "config",
                    listOf("--porcelain") + offerConfigFlags(source, range) +
                        listOf("--", branch),
                    cwd,
                )
            }
            if (probe.exitCode == 0) {
                try {
                    deltaForSource(parseConfigPorcelain(probe.stdout).deltas, source.id)
                } catch (_: Exception) {
                    null
                }
            } else null
        } else null

        val validation = validateIntent(intent, IntentValidationContext(delta = delta))
        if (validation is IntentValidationResult.Fail) {
            Messages.showErrorDialog(project, validation.reason, "git review")
            return
        }

        val confirm = Messages.showYesNoDialog(
            project,
            "Start ${layout.name.lowercase()} review of $branch from $source?",
            "Confirm Start",
            Messages.getQuestionIcon(),
        )
        if (confirm != Messages.YES) return

        MutationActions(project, service).runStart(intent, branch) { result ->
            when (result) {
                StartRunResult.Ok -> Messages.showInfoMessage(project, "Review started.", "git review")
                StartRunResult.Busy -> Messages.showWarningDialog(
                    project,
                    "Another operation is already in progress",
                    "git review",
                )
                StartRunResult.Stale -> Messages.showWarningDialog(project, "State changed; try again.", "git review")
                StartRunResult.NoCwd -> Messages.showErrorDialog(project, "No sole git root.", "git review")
                is StartRunResult.Network -> {
                    val line = formatCommandLine(result.command, result.args)
                    Messages.showErrorDialog(
                        project,
                        "Network failure starting the review.\n\n${result.stderr}\n\nRun in Terminal:\n$line",
                        "git review",
                    )
                }
                is StartRunResult.Failed -> Messages.showErrorDialog(project, result.stderr, "git review")
            }
        }
    }
}
