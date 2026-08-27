package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.DeltaRecord
import com.ezevillo.gitreview.domain.DraftFlowEvent
import com.ezevillo.gitreview.domain.MutationLock
import com.ezevillo.gitreview.domain.DraftFlowState
import com.ezevillo.gitreview.domain.DraftRange
import com.ezevillo.gitreview.domain.DraftRecord
import com.ezevillo.gitreview.domain.DraftSource
import com.ezevillo.gitreview.domain.DraftStep
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
import com.ezevillo.gitreview.domain.draftOutcomeText
import com.ezevillo.gitreview.domain.draftConfigArgs
import com.ezevillo.gitreview.domain.offersIncludeKeys
import com.ezevillo.gitreview.domain.formatCommandLine
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
import com.intellij.openapi.application.ReadAction
import com.intellij.openapi.application.WriteAction
import com.intellij.openapi.editor.Document
import com.intellij.openapi.fileEditor.FileDocumentManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.io.FileUtil

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
        var offers: List<ReadingOffer>? = null
        if (cfgResult.exitCode == 0) {
            try {
                val report = parseConfigPorcelain(cfgResult.stdout)
                if (report.deltas != null) deltas = report.deltas
                offers = report.offers
            } catch (_: Exception) {
                // Sin ofertas se cae al fallback de siempre.
            }
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
     * ahí con el borrador intacto y la oferta ya recalculada por la CLI.
     */
    private fun layoutStep(
        ctx: WizardContext,
        offers: List<ReadingOffer>?,
    ) {
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
        // Sin preguntar nada: cuál de los tres caminos del borrador corresponde
        // ya lo decidió la CLI al elegir qué oferta emitir, que es la única que
        // puede —la pregunta es si el orden sigue cubriendo el rango, y para eso
        // hacen falta los dos tips.
        runDraftFlow(ctx, initialDraftFlowState(draftStep))
    }

    /**
     * Lo que queda del camino del borrador (012). Las decisiones viven en
     * `DraftFlow`; acá sólo está el vehículo: una invocación y el cierre.
     *
     * No abre el borrador y no deja ningún diálogo esperando. La continuación
     * —llenarlo, validarlo, arrancar la review— vive en el bloque de borradores
     * del panel, sobre un estado que sobrevive a cerrar el IDE.
     */
    private fun runDraftFlow(ctx: WizardContext, start: DraftFlowState) {
        val service = GitReviewService.getInstance(ctx.project)
        var state = start
        while (true) {
            when (val current = state) {
                is DraftFlowState.Create -> {
                    val outcome = invokeDraft(ctx, service, current.force)
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

                is DraftFlowState.Done -> {
                    // El refresco post-mutación trae la fila del borrador al
                    // panel, con su ruta. Nada más que hacer acá.
                    service.scheduleRefresh()
                    return
                }

                is DraftFlowState.Back -> {
                    if (current.error != null) {
                        UiMessages.error(ctx.project, current.error)
                    }
                    // Con las ofertas al día: si se creó el borrador, la de
                    // armarlo ya es la de continuarlo.
                    val reloaded = loadOffers(ctx, service)
                    layoutStep(ctx, reloaded.offers)
                    return
                }
            }
        }
    }

    private data class DraftOutcome(val ok: Boolean, val text: String)

    /**
     * La creación del borrador. Sólo la creación: validarlo es cosa del panel
     * desde 012, con los flags que la CLI grabó en el archivo.
     */
    private fun invokeDraft(
        ctx: WizardContext,
        service: GitReviewService,
        force: Boolean,
    ): DraftOutcome {
        // Under the mutation lock, like every other CLI invocation this plugin
        // makes — and like the extension's own invokeDraft. Drafting touches no
        // git state, but it runs with the panel and its refreshes live, and one
        // client holding a lock the other does not is a difference in behaviour
        // between the two IDEs rather than a detail of either.
        val result = service.mutationLock.run {
            Bg.sync(ctx.project, UserCopy.draftProgress(ctx.branch, build = false)) {
                service.cliInvoker.invoke(
                    "walkthrough",
                    draftArgs(ctx.branch, ctx.source, ctx.range, build = false, force = force),
                    ctx.cwd,
                )
            }
        } ?: return DraftOutcome(ok = false, text = MutationLock.DISCARD_REASON)
        val ok = result.exitCode == 0 && !result.timedOut
        return DraftOutcome(
            ok = ok,
            // En verde, lo que hizo el verbo (stdout) más sus notas; en rojo,
            // sólo el error, que es lo que la CLI pone en stderr.
            text = if (ok) {
                draftOutcomeText(result.stdout, result.stderr)
            } else {
                UiMessages.flatten(result.stderr)
            },
        )
    }

    /** Ofertas para el contexto ya resuelto (misma invocación que el paso 4). */
    /** Las ofertas para este contexto. Los borradores no se leen aca: cual de
     *  los tres caminos del borrador corresponde ya viene decidido en la oferta. */
    private data class OfferContext(
        val offers: List<ReadingOffer>?,
    )

    private fun loadOffers(ctx: WizardContext, service: GitReviewService): OfferContext {
        val flags = offerConfigFlags(ctx.source, ctx.range).toMutableList()
        flags.add(0, "--porcelain")
        flags.add("--")
        flags.add(ctx.branch)
        val result = Bg.sync(ctx.project, "git review config") {
            service.cliInvoker.invoke("config", flags, ctx.cwd)
        }
        if (result.exitCode != 0) return OfferContext(null)
        return try {
            val report = parseConfigPorcelain(result.stdout)
            OfferContext(report.offers)
        } catch (_: Exception) {
            OfferContext(null)
        }
    }

    /**
     * *Validate and start* de una fila del bloque de borradores (012): los mismos
     * cuatro pasos que la extensión, con los flags de ESA fila.
     *
     * Vive acá y no en el despachador porque el paso 4 es el `start` de siempre,
     * con su confirmación, su guarda de staleness y su manejo de errores: una
     * segunda copia de eso sería una segunda forma de arrancar una review.
     */
    fun startFromDraft(project: Project, draft: DraftRecord) {
        if (draft.source == DraftSource.UNKNOWN || draft.range == DraftRange.UNKNOWN) {
            // Sin los flags con los que se generó no hay nada que replicar, y
            // adivinarlos haría fallar el build por deriva sobre un borrador
            // válido. El panel ya no dibuja el control; esta es la guarda del host.
            return
        }
        val service = GitReviewService.getInstance(project)
        val cwd = pickSoleGitRoot(project)?.rootPath ?: run {
            UiMessages.error(project, UserCopy.NO_SOLE_ROOT)
            return
        }
        val source = when (draft.source) {
            DraftSource.LOCAL -> ReviewSource.LOCAL
            DraftSource.OFFLINE -> ReviewSource.OFFLINE
            else -> ReviewSource.REMOTE
        }
        val range = if (draft.range == DraftRange.DELTA) ReviewRange.DELTA else ReviewRange.FULL

        saveDraftDocument(project, draft.path)

        val built = service.mutationLock.run {
            Bg.sync(project, UserCopy.draftProgress(draft.src, build = true)) {
                service.cliInvoker.invoke(
                    "walkthrough",
                    draftArgs(draft.src, source, range, build = true),
                    cwd,
                )
            }
        } ?: run {
            UiMessages.info(project, UserCopy.DISCARD_BUSY)
            return
        }
        if (built.exitCode != 0 || built.timedOut) {
            // El motivo del rechazo lo escribió la CLI: redactarlo de nuevo sería
            // inventar un segundo vocabulario de validación. El panel y el
            // borrador quedan exactamente como estaban.
            UiMessages.error(
                project,
                UiMessages.flatten(built.stderr).ifEmpty { UserCopy.DRAFT_BUILD_FAILED },
            )
            return
        }

        // El borrador ya es legible: lo que se relee es si marcó entradas
        // esenciales, y eso sólo lo sabe la CLI. Con los MISMOS flags — y de
        // paso vuelven los registros `delta`, que es lo que valida un rango
        // incremental antes de invocar start.
        var layout = ReviewLayout.WALK
        var deltas: List<DeltaRecord>? = null
        val report = Bg.sync(project, "git review config") {
            service.cliInvoker.invoke("config", draftConfigArgs(draft.src, source, range), cwd)
        }
        if (report.exitCode == 0) {
            val parsed = try {
                parseConfigPorcelain(report.stdout)
            } catch (_: Exception) {
                null
            }
            deltas = parsed?.deltas
            if (offersIncludeKeys(parsed?.offers)) {
                val labels = UserCopy.DRAFT_KEYS_LABELS.map { it.second }.toTypedArray()
                val idx = UiMessages.choose(
                    project,
                    UserCopy.DRAFT_KEYS_PLACEHOLDER,
                    UserCopy.START_LAYOUT_TITLE,
                    labels,
                )
                if (idx < 0) return
                layout = if (UserCopy.DRAFT_KEYS_LABELS[idx].first) ReviewLayout.KEYS else ReviewLayout.WALK
            }
        }

        confirmAndStart(
            WizardContext(
                project = project,
                cwd = cwd,
                branch = draft.src,
                source = source,
                range = range,
                deltas = deltas,
                base = service.currentState().config?.base,
            ),
            layout,
        )
    }

    /**
     * Guarda el documento del borrador si está abierto y sin guardar, y sólo ése.
     * `walkthrough draft --build` lee el archivo del disco, y el IDE guarda al
     * perder el foco — que es justo lo que no pasa mientras el panel conduce.
     */
    private fun saveDraftDocument(project: Project, path: String) {
        // La VFS no se toca desde acá. Resolver un path es dos operaciones en
        // una: si la VFS nunca vio el archivo hay que crear el nodo y disparar el
        // evento de creación, o sea mutar el modelo de la plataforma, y este
        // handler entra por un JButton del panel — sin write-intent lock (ver
        // `openInEditor`). El borrador vive en el gitdir, que es justamente lo
        // que ningún editor indexa, así que sería siempre ese camino.
        // La pregunta acá es más chica que la que contesta la VFS: ¿hay un
        // documento abierto y sucio para ESTE archivo? Los documentos sucios ya
        // traen su VirtualFile cargado, así que se responde sin ir al disco — y
        // si el archivo no está en la VFS no hay documento abierto, o sea que la
        // respuesta correcta es la misma que daba el `?: return` de antes.
        // Desde 2024.1 el EDT tampoco trae read access implícito, así que el lock
        // lo pide el llamador. `ReadAction`/`WriteAction` y no
        // `WriteIntentReadAction`, que sería el lock justo pero está
        // @ApiStatus.Experimental — el descriptor no tiene until-build, así que
        // API que puede cambiar de forma es un NoSuchMethodError a futuro.
        // El write lock se toma sólo si de verdad hay algo que guardar.
        val fdm = FileDocumentManager.getInstance()
        val unsaved = ReadAction.computeBlocking<Document?, RuntimeException> {
            fdm.unsavedDocuments.firstOrNull { doc ->
                fdm.getFile(doc)?.let { FileUtil.pathsEqual(it.path, path) } == true
            }
        } ?: return
        WriteAction.run<RuntimeException> { fdm.saveDocument(unsaved) }
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
