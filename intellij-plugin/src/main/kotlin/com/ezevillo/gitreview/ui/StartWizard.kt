package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.ReviewIntent
import com.ezevillo.gitreview.domain.ReviewRange
import com.ezevillo.gitreview.domain.ReviewSource
import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.branchPickerItems
import com.ezevillo.gitreview.domain.branchPickerLabel
import com.ezevillo.gitreview.domain.buildLayoutItems
import com.ezevillo.gitreview.domain.deltaForSource
import com.ezevillo.gitreview.domain.formatCommandLine
import com.ezevillo.gitreview.domain.intentToArgs
import com.ezevillo.gitreview.domain.offerConfigFlags
import com.ezevillo.gitreview.domain.parseConfigPorcelain
import com.ezevillo.gitreview.domain.resolveDefaultSource
import com.ezevillo.gitreview.domain.SourcePreferenceLevels
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

/**
 * Multi-step start wizard (dialogs). Branch list comes from
 * `git review config --porcelain` candidates — same source as the VS Code
 * start assistant — not free-text input. Confirm / error copy matches VS Code.
 */
object StartWizard {
    fun run(project: Project) {
        val service = GitReviewService.getInstance(project)
        val cwd = pickSoleGitRoot(project)?.rootPath
        if (cwd == null) {
            UiMessages.error(project, UserCopy.NO_SOLE_ROOT)
            return
        }

        // Fresh config --porcelain (config + candidates), not the panel cache.
        val bootstrap = Bg.sync(project, "git review config") {
            service.cliInvoker.invoke("config", listOf("--porcelain"), cwd)
        }
        if (bootstrap.exitCode != 0 || bootstrap.timedOut) {
            val text = bootstrap.stderr.trim().ifEmpty { UserCopy.COULD_NOT_READ_CONFIG }
            UiMessages.error(project, text)
            return
        }
        val parsed = try {
            parseConfigPorcelain(bootstrap.stdout)
        } catch (e: Exception) {
            UiMessages.error(project, e.message ?: UserCopy.COULD_NOT_PARSE_CONFIG)
            return
        }

        if (parsed.config.base == null) {
            UiMessages.error(project, UserCopy.CONFIGURE_BASE_FIRST)
            return
        }

        val branches = branchPickerItems(parsed.candidates)
        if (branches.isEmpty()) {
            UiMessages.error(project, UserCopy.NO_BRANCHES_FOR_REVIEW)
            return
        }
        val branchLabels = branches.map { branchPickerLabel(it) }.toTypedArray()
        val branchIdx = UiMessages.choose(
            project,
            UserCopy.START_BRANCH_PLACEHOLDER,
            UserCopy.START_BRANCH_TITLE,
            branchLabels,
        )
        if (branchIdx < 0) return
        val branch = branches[branchIdx].name

        val defaultSrc = resolveDefaultSource(
            SourcePreferenceLevels(globalValue = GitReviewSettings.getInstance().defaultSource),
        )
        val sourceLabels = UserCopy.SOURCE_LABELS.map { it.second }.toTypedArray()
        val defaultLabel = UserCopy.SOURCE_LABELS.first { it.first == defaultSrc }.second
        val sourceIdx = UiMessages.choose(
            project,
            UserCopy.START_ORIGIN_PLACEHOLDER,
            UserCopy.START_ORIGIN_TITLE,
            sourceLabels,
            defaultLabel,
        )
        if (sourceIdx < 0) return
        val source = UserCopy.SOURCE_LABELS[sourceIdx].first

        // Range only when a delta marker exists for this source (same as VS Code).
        var range = ReviewRange.FULL
        val deltaProbe = Bg.sync(project, "git review config") {
            service.cliInvoker.invoke(
                "config",
                listOf("--porcelain", "--", branch),
                cwd,
            )
        }
        var deltas = if (deltaProbe.exitCode == 0) {
            try {
                parseConfigPorcelain(deltaProbe.stdout).deltas
            } catch (_: Exception) {
                null
            }
        } else {
            null
        }
        val hasDelta = deltaForSource(deltas, source.id) != null
        if (hasDelta) {
            val rangeLabels = UserCopy.RANGE_LABELS.map { it.second }.toTypedArray()
            val rangeIdx = UiMessages.choose(
                project,
                UserCopy.START_RANGE_PLACEHOLDER,
                UserCopy.START_RANGE_TITLE,
                rangeLabels,
            )
            if (rangeIdx < 0) return
            range = UserCopy.RANGE_LABELS[rangeIdx].first
        }

        // Offers for layout (depend on source + range tip context).
        val flags = offerConfigFlags(source, range).toMutableList()
        flags.add(0, "--porcelain")
        flags.add("--")
        flags.add(branch)
        val cfgResult = Bg.sync(project, "git review config") {
            service.cliInvoker.invoke("config", flags, cwd)
        }
        val offers = if (cfgResult.exitCode == 0) {
            try {
                val report = parseConfigPorcelain(cfgResult.stdout)
                if (report.deltas != null) deltas = report.deltas
                report.offers
            } catch (_: Exception) {
                null
            }
        } else {
            null
        }
        if (cfgResult.exitCode != 0) {
            val text = cfgResult.stderr.trim().ifEmpty { UserCopy.COULD_NOT_READ_OFFERS }
            UiMessages.error(project, text)
            return
        }

        val items = buildLayoutItems(offers)
        val labels = items.map { item ->
            if (item.description.isNotEmpty()) "${item.label} — ${item.description}" else item.label
        }.toTypedArray()
        val layoutIdx = UiMessages.choose(
            project,
            UserCopy.START_LAYOUT_PLACEHOLDER,
            UserCopy.START_LAYOUT_TITLE,
            labels,
        )
        if (layoutIdx < 0) return
        val layout = items[layoutIdx].layout

        val intent = ReviewIntent(
            branch = branch,
            layout = layout,
            range = range,
            source = source,
        )

        val delta = deltaForSource(deltas, source.id)
        val validation = validateIntent(intent, IntentValidationContext(delta = delta))
        if (validation is IntentValidationResult.Fail) {
            UiMessages.error(project, validation.reason)
            return
        }

        val args = intentToArgs(intent, branch)
        val base = parsed.config.base
        if (!UiMessages.confirm(
                project,
                UserCopy.startConfirmTitle(branch, layout),
                UserCopy.startConfirmDetail(args, base),
                UserCopy.START_CONFIRM_BUTTON,
            )
        ) {
            return
        }

        MutationActions(project, service).runStart(intent, branch) { result ->
            when (result) {
                is StartRunResult.Ok -> {
                    // Successful start can still emit notes on stderr (FR-031).
                    if (result.note != null) {
                        UiMessages.info(project, result.note)
                    }
                }
                StartRunResult.Busy -> UiMessages.info(project, UserCopy.DISCARD_BUSY)
                StartRunResult.Stale -> UiMessages.info(project, UserCopy.START_STALE_RUN)
                StartRunResult.NoCwd -> UiMessages.error(project, UserCopy.NO_SOLE_ROOT)
                is StartRunResult.Network -> {
                    val text = result.stderr.trim().ifEmpty { UserCopy.START_FAILED }
                    val line = formatCommandLine(result.command, result.args)
                    UiMessages.error(
                        project,
                        "$text\n\nTo retry with credentials, run in Terminal:\n$line",
                    )
                }
                is StartRunResult.Failed -> {
                    val text = result.stderr.trim().ifEmpty { UserCopy.START_FAILED }
                    UiMessages.error(project, text)
                }
            }
        }
    }
}
