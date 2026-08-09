package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.DeltaRecord
import com.ezevillo.gitreview.domain.DraftFlowEvent
import com.ezevillo.gitreview.domain.DraftFlowState
import com.ezevillo.gitreview.domain.ReadingOffer
import com.ezevillo.gitreview.domain.ReviewIntent
import com.ezevillo.gitreview.domain.ReviewLayout
import com.ezevillo.gitreview.domain.ReviewRange
import com.ezevillo.gitreview.domain.ReviewSource
import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.advanceDraftFlow
import com.ezevillo.gitreview.domain.branchPickerItems
import com.ezevillo.gitreview.domain.branchPickerLabel
import com.ezevillo.gitreview.domain.buildLayoutItems
import com.ezevillo.gitreview.domain.deltaForSource
import com.ezevillo.gitreview.domain.draftArgs
import com.ezevillo.gitreview.domain.formatCommandLine
import com.ezevillo.gitreview.domain.gitdirFromLink
import com.ezevillo.gitreview.domain.initialDraftFlowState
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
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.LocalFileSystem
import java.io.File

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

        layoutStep(
            WizardContext(
                project = project,
                cwd = cwd,
                branch = branch,
                source = source,
                range = range,
                base = parsed.config.base,
                deltas = deltas,
            ),
            offers,
        )
    }

    /**
     * Contexto del asistente desde el paso de forma de lectura en adelante. Se
     * captura en una closure porque el bucle del borrador **corta el flujo**:
     * el aviso de espera es un diálogo no modal, y lo que sigue se reanuda
     * desde su callback, cuando la pila del asistente ya se fue.
     */
    private data class WizardContext(
        val project: Project,
        val cwd: String,
        val branch: String,
        val source: ReviewSource,
        val range: ReviewRange,
        val base: String?,
        val deltas: List<DeltaRecord>?,
    )

    /**
     * Paso de forma de lectura. Se vuelve a él —y sólo por eso es una función
     * aparte— cuando el revisor entra al armado del borrador y cancela: sale de
     * ahí con el borrador intacto y la oferta convertida en `draft-resume`.
     */
    private fun layoutStep(ctx: WizardContext, offers: List<ReadingOffer>?) {
        val items = buildLayoutItems(offers)
        val labels = items.map { item ->
            if (item.description.isNotEmpty()) "${item.label} — ${item.description}" else item.label
        }.toTypedArray()
        val layoutIdx = UiMessages.choose(
            ctx.project,
            UserCopy.START_LAYOUT_PLACEHOLDER,
            UserCopy.START_LAYOUT_TITLE,
            labels,
        )
        if (layoutIdx < 0) return
        val picked = items[layoutIdx]
        val draftStep = picked.draft
        if (draftStep == null) {
            confirmAndStart(ctx, picked.layout)
            return
        }
        runDraftFlow(ctx, initialDraftFlowState(draftStep))
    }

    /**
     * El bucle del borrador (011). Las decisiones viven en `DraftFlow`; acá
     * sólo está el vehículo de cada paso — y el corte: al llegar al aviso de
     * espera la función retorna, y el callback del diálogo la vuelve a entrar
     * con el estado que corresponda.
     */
    private fun runDraftFlow(ctx: WizardContext, start: DraftFlowState) {
        val service = GitReviewService.getInstance(ctx.project)
        var state = start
        while (true) {
            when (val current = state) {
                is DraftFlowState.Create -> {
                    val outcome = invokeDraft(ctx, service, build = false)
                    if (outcome.ok && outcome.text.isNotEmpty()) {
                        // Nota de un verbo exitoso (el borrador tapa el
                        // walkthrough del autor): se muestra, como las de start.
                        UiMessages.info(ctx.project, outcome.text)
                    }
                    state = advanceDraftFlow(
                        current,
                        DraftFlowEvent.Created(
                            ok = outcome.ok,
                            error = if (outcome.ok) null else outcome.text.ifEmpty { UserCopy.DRAFT_FAILED },
                        ),
                    )
                }

                is DraftFlowState.Open -> {
                    openDraft(ctx)
                    state = advanceDraftFlow(current, DraftFlowEvent.Opened)
                }

                is DraftFlowState.Wait -> {
                    // Acá se corta: el diálogo no bloquea, así que el resto del
                    // bucle vive en su callback.
                    DraftWaitDialog(ctx.project, ctx.branch, current.error) { proceed ->
                        runDraftFlow(
                            ctx,
                            advanceDraftFlow(
                                current,
                                if (proceed) DraftFlowEvent.Continue else DraftFlowEvent.Cancel,
                            ),
                        )
                    }.show()
                    return
                }

                is DraftFlowState.Build -> {
                    val outcome = invokeDraft(ctx, service, build = true)
                    state = advanceDraftFlow(
                        current,
                        DraftFlowEvent.Built(
                            ok = outcome.ok,
                            error = if (outcome.ok) null else outcome.text.ifEmpty { UserCopy.DRAFT_BUILD_FAILED },
                        ),
                    )
                }

                is DraftFlowState.Reload -> {
                    // El borrador ya es legible: lo que se relee es si marcó
                    // entradas esenciales, y eso sólo lo sabe la CLI.
                    state = advanceDraftFlow(current, DraftFlowEvent.Offers(loadOffers(ctx, service)))
                }

                is DraftFlowState.PickKeys -> {
                    val labels = UserCopy.DRAFT_KEYS_LABELS.map { it.second }.toTypedArray()
                    val idx = UiMessages.choose(
                        ctx.project,
                        UserCopy.DRAFT_KEYS_PLACEHOLDER,
                        UserCopy.START_LAYOUT_TITLE,
                        labels,
                    )
                    val keysOnly = if (idx < 0) null else UserCopy.DRAFT_KEYS_LABELS[idx].first
                    state = advanceDraftFlow(current, DraftFlowEvent.KeysPicked(keysOnly))
                }

                is DraftFlowState.Done -> {
                    confirmAndStart(ctx, current.layout)
                    return
                }

                is DraftFlowState.Back -> {
                    if (current.error != null) {
                        UiMessages.error(ctx.project, current.error)
                    }
                    // Con las ofertas al día: si se creó el borrador, la de
                    // armarlo ya es la de continuarlo.
                    layoutStep(ctx, loadOffers(ctx, service))
                    return
                }
            }
        }
    }

    private data class DraftOutcome(val ok: Boolean, val text: String)

    private fun invokeDraft(
        ctx: WizardContext,
        service: GitReviewService,
        build: Boolean,
    ): DraftOutcome {
        val result = Bg.sync(ctx.project, UserCopy.draftProgress(ctx.branch, build)) {
            service.cliInvoker.invoke(
                "walkthrough",
                draftArgs(ctx.branch, ctx.source, ctx.range, build),
                ctx.cwd,
            )
        }
        return DraftOutcome(
            ok = result.exitCode == 0 && !result.timedOut,
            text = UiMessages.flatten(result.stderr),
        )
    }

    /** Ofertas para el contexto ya resuelto (misma invocación que el paso 4). */
    private fun loadOffers(ctx: WizardContext, service: GitReviewService): List<ReadingOffer>? {
        val flags = offerConfigFlags(ctx.source, ctx.range).toMutableList()
        flags.add(0, "--porcelain")
        flags.add("--")
        flags.add(ctx.branch)
        val result = Bg.sync(ctx.project, "git review config") {
            service.cliInvoker.invoke("config", flags, ctx.cwd)
        }
        if (result.exitCode != 0) return null
        return try {
            parseConfigPorcelain(result.stdout).offers
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Abre el borrador en el editor. La ruta se arma, no se lee de la salida de
     * la CLI: vive en `<gitdir>/review-walkthrough/<branch>.md`, y `<gitdir>` es
     * `<root>/.git` salvo en worktrees y submódulos, donde `.git` es un archivo
     * que apunta al de verdad. Mostrarlo no es leerlo: el plugin no interpreta
     * un byte de su contenido.
     */
    private fun openDraft(ctx: WizardContext) {
        try {
            val dotGit = File(ctx.cwd, ".git")
            val gitdir = if (dotGit.isDirectory) {
                dotGit
            } else {
                val target = gitdirFromLink(dotGit.readText()) ?: return
                val resolved = File(target)
                if (resolved.isAbsolute) resolved else File(ctx.cwd, target)
            }
            val draft = File(File(gitdir, "review-walkthrough"), "${ctx.branch}.md")
            if (!draft.isFile) return
            val vf = LocalFileSystem.getInstance().refreshAndFindFileByIoFile(draft) ?: return
            FileEditorManager.getInstance(ctx.project).openFile(vf, true)
        } catch (_: Exception) {
            // No se pudo abrir: el bucle sigue igual, y la CLI ya dijo dónde
            // está el archivo.
        }
    }

    private fun confirmAndStart(ctx: WizardContext, layout: ReviewLayout) {
        val project = ctx.project
        val branch = ctx.branch
        val intent = ReviewIntent(
            branch = branch,
            layout = layout,
            range = ctx.range,
            source = ctx.source,
        )
        val service = GitReviewService.getInstance(project)
        val deltas = ctx.deltas
        val base = ctx.base

        val delta = deltaForSource(deltas, ctx.source.id)
        val validation = validateIntent(intent, IntentValidationContext(delta = delta))
        if (validation is IntentValidationResult.Fail) {
            UiMessages.error(project, validation.reason)
            return
        }

        val args = intentToArgs(intent, branch)
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
