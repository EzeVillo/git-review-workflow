package com.ezevillo.gitreview.domain

/**
 * Pure projection of [PanelModel] into an ordered panel layout.
 * Domain-pure: no IntelliJ Platform imports (checkDomainNoIntellij).
 */

/** Loading thresholds (match vscode-extension panelHtml.ts). */
const val SKELETON_DELAY_MS: Long = 120
const val WHY_CEILING_MS: Long = 800

enum class Emphasis {
    PRIMARY, SECONDARY, LINK, ICON;

    val id: String
        get() = when (this) {
            PRIMARY -> "primary"
            SECONDARY -> "secondary"
            LINK -> "link"
            ICON -> "icon"
        }
}

/**
 * Closed set of 26 control ids: 21 body + 5 title bar.
 * Excluded palette-only actions are intentionally not representable here.
 */
enum class ControlId {
    // Body (21)
    OPEN_ENTRY,
    OPEN_CHANGE,
    OPEN_ALL_CHANGES,
    SHOW_WHY,
    NEXT,
    PREV,
    INSTALL_CLI,
    COPY_CLI_INSTALL,
    OUT_OF_RANGE_HELP,
    CONTINUE_REVIEW,
    START_REVIEW,
    SET_BASE,
    SET_REMOTE,
    UNDO_FINISH,
    RESUME_FINISH,
    DISCARD_INVENTORY,
    // Draft block (012): four BODY controls, not product actions. They are not
    // in the action matrix, not in the Tools menu, and the canonical's fixed
    // count of 27 does not move.
    OPEN_DRAFT,
    COPY_DRAFT_PROMPT,
    START_FROM_DRAFT,
    DISCARD_DRAFT,
    OPEN_GUIDE,
    CREATE_GUIDE,
    DISCARD_GUIDE,
    CLEAN_REVIEW,
    COMPARE_REVIEW,
    WALKTHROUGH_INIT,
    WALKTHROUGH_BUILD,
    OPEN_SUPPORT,
    // Title bar (5) — refresh is title-only
    REFRESH,
    FINISH_REVIEW,
    SAVE_REVIEW,
    ABORT_REVIEW,
    PREVIEW_EDITS,
    ;

    val wire: String
        get() = when (this) {
            OPEN_ENTRY -> "openEntry"
            OPEN_CHANGE -> "openChange"
            OPEN_ALL_CHANGES -> "openAllChanges"
            SHOW_WHY -> "showWhy"
            NEXT -> "next"
            PREV -> "prev"
            INSTALL_CLI -> "installCli"
            COPY_CLI_INSTALL -> "copyCliInstall"
            OUT_OF_RANGE_HELP -> "outOfRangeHelp"
            CONTINUE_REVIEW -> "continueReview"
            START_REVIEW -> "startReview"
            SET_BASE -> "setBase"
            SET_REMOTE -> "setRemote"
            UNDO_FINISH -> "undoFinish"
            RESUME_FINISH -> "resumeFinish"
            DISCARD_INVENTORY -> "discardInventory"
            OPEN_DRAFT -> "openDraft"
            COPY_DRAFT_PROMPT -> "copyDraftPrompt"
            START_FROM_DRAFT -> "startFromDraft"
            DISCARD_DRAFT -> "discardDraft"
            OPEN_GUIDE -> "openGuide"
            CREATE_GUIDE -> "createGuide"
            DISCARD_GUIDE -> "discardGuide"
            CLEAN_REVIEW -> "cleanReview"
            COMPARE_REVIEW -> "compareReview"
            WALKTHROUGH_INIT -> "walkthroughInit"
            WALKTHROUGH_BUILD -> "walkthroughBuild"
            OPEN_SUPPORT -> "openSupport"
            REFRESH -> "refresh"
            FINISH_REVIEW -> "finishReview"
            SAVE_REVIEW -> "saveReview"
            ABORT_REVIEW -> "abortReview"
            PREVIEW_EDITS -> "previewEdits"
        }

    companion object {
        fun fromWire(id: String): ControlId? = entries.find { it.wire == id }
    }
}

/** Controls that show a confirmation dialog before mutating (canonical `confirms:`). */
private val CONFIRMING_IDS: Set<ControlId> = setOf(
    ControlId.START_REVIEW,
    ControlId.CONTINUE_REVIEW,
    ControlId.DISCARD_INVENTORY,
    ControlId.START_FROM_DRAFT,
    ControlId.DISCARD_DRAFT,
    ControlId.DISCARD_GUIDE,
    ControlId.CLEAN_REVIEW,
    ControlId.UNDO_FINISH,
    ControlId.COMPARE_REVIEW,
    ControlId.WALKTHROUGH_INIT,
    ControlId.WALKTHROUGH_BUILD,
    ControlId.SAVE_REVIEW,
    ControlId.ABORT_REVIEW,
)

fun requiresConfirmation(id: ControlId): Boolean = id in CONFIRMING_IDS

data class Control(
    val id: ControlId,
    val label: String?,
    val accessibleName: String,
    val emphasis: Emphasis,
    val enabled: Boolean = true,
    val tooltip: String? = null,
    val index: Int? = null,
    /** openSupport allowlist id (`star`, `bug`); null for every other control. */
    val supportLinkId: String? = null,
) {
    init {
        // 1. icon ⟹ accessible name
        if (label == null) {
            require(emphasis == Emphasis.ICON) {
                "Control ${id.wire}: null label requires ICON emphasis"
            }
            require(accessibleName.isNotEmpty()) {
                "Control ${id.wire}: icon controls need a non-empty accessibleName"
            }
        }
        // 4. index only on row items — enforced at Block construction for FileRows/InventoryRows
    }
}

data class FileRow(
    val display: String,
    val index: Int,
    val lastOpened: Boolean,
)

/**
 * A row of the draft block: the branch, the progress exactly as the CLI reports
 * it, and the controls that act on THAT row.
 *
 * One list, two places on the row: the labelled controls are the button pair
 * underneath, and the ICON ones are drawn in the header beside the progress —
 * the pair names their subject, and neither of them moves the flow along. The
 * renderer splits on the emphasis; the order inside each half is this one.
 */
data class DraftRow(
    val name: String,
    val meta: String,
    val controls: List<Control>,
) {
    init {
        for (c in controls) {
            require(c.index != null) {
                "Draft control ${c.id.wire} must carry an index"
            }
        }
    }
}

/**
 * A row of the authoring-guide block: which guide it is, the state the CLI
 * reported as a badge, and the controls that act on THAT row.
 *
 * Same two-place shape as [DraftRow]: the labelled control is the button
 * underneath and the ICON ones are drawn in the header beside the badge. And
 * the same rule about presence -- both rows carry the same controls whatever
 * their state, except Discard, which only the reviewer's own row has at all:
 * the shared guide is a tracked file, so removing it is `git rm` plus a commit.
 */
data class GuideRow(
    val name: String,
    val badge: String,
    val controls: List<Control>,
) {
    init {
        for (c in controls) {
            require(c.index != null) {
                "Guide control ${c.id.wire} must carry an index"
            }
        }
    }
}

data class InventoryRow(
    val name: String,
    val badges: List<String>,
    val meta: String,
    val controls: List<Control>,
    val helpTooltip: String? = null,
) {
    init {
        for (c in controls) {
            require(c.index != null) {
                "Inventory control ${c.id.wire} must carry an index"
            }
        }
        // helpTooltip is required when the row has no controls *and* is not the
        // current active review (which the extension also shows without a "?").
    }
}

enum class SkeletonShape {
    POS, NUM, TITLE, WHY_LINE, BAR,
}

sealed class Block {
    data class IdentityBar(
        val mode: String,
        /**
         * 011: de quién es el orden de lectura. Es una precisión sobre el modo
         * —el mismo "walk (draft)" que escribe la terminal—, no un bloque ni un
         * control nuevo: `panel_layout` no cambia.
         */
        val draft: Boolean = false,
        val name: String,
        val tip: String? = null,
        val position: Int? = null,
        val total: Int? = null,
        val skeleton: Boolean = false,
    ) : Block()

    data class Note(val text: String) : Block()

    /**
     * @param separated a rule above the paragraph, the extension's
     *   `.empty.after-inv`: what separates "you already have these reviews"
     *   from "this is how you start one". Carried by the paragraph and not by
     *   the list, so with no reviews the empty state is untouched.
     */
    data class Paragraph(
        val text: String,
        val muted: Boolean = false,
        val separated: Boolean = false,
    ) : Block()
    data class Heading(val text: String) : Block()

    data class Banner(
        val paragraphs: List<String>,
        val row: Row,
    ) : Block()

    data class CodeCommand(
        val command: String,
        val copy: Control,
    ) : Block()

    data class EntryHead(
        val position: Int,
        val identifier: String? = null,
        val author: String? = null,
        val badge: String? = null,
        val skeleton: Boolean = false,
    ) : Block()

    data class EntryTitle(
        val text: String,
        val muted: Boolean = false,
        val skeleton: Boolean = false,
    ) : Block()

    data class Why(
        val state: WhyState,
        val text: String? = null,
        val uncovered: Boolean = false,
    ) : Block()

    data class Row(val controls: List<Control>) : Block() {
        init {
            require(controls.size in 1..2) {
                "Row must have 1 or 2 controls, got ${controls.size}"
            }
        }
    }

    data class FileRows(val rows: List<FileRow>) : Block()
    data class InventoryRows(val rows: List<InventoryRow>) : Block()
    data class DraftRows(val rows: List<DraftRow>) : Block()

    data class GuideRows(val rows: List<GuideRow>) : Block()

    data class ToolsSection(
        val title: String,
        val blocks: List<Block>,
    ) : Block() {
        init {
            require(blocks.none { it is ToolsSection || it is Banner }) {
                "ToolsSection cannot nest Banner/ToolsSection"
            }
        }
    }

    data class Stderr(val text: String) : Block()

    data class EmptyMessage(
        val text: String,
        val control: Control? = null,
        val stderr: String? = null,
    ) : Block()

    data class Skeleton(val shape: SkeletonShape) : Block()
}

data class PanelLayout(
    val situation: Situation,
    val blocks: List<Block>,
    val titleActions: List<Control>,
    val fillsHeight: Boolean = false,
) {
    init {
        val controls = collectControls()
        // One PRIMARY per situation, counted over the controls that are NOT row
        // controls. A row control is a per-row affordance repeated as many times
        // as there are rows — "the obvious thing to do with THIS draft" — so
        // counting them here would make the rule depend on how many drafts the
        // reviewer happens to have, which is not a property of the layout.
        val primaries = controls.count { it.emphasis == Emphasis.PRIMARY && it.index == null }
        require(primaries <= 1) {
            "At most one PRIMARY control per situation, found $primaries"
        }
        // index allowed only inside InventoryRows: FileRows carries its index on the
        // row (FileRow.index), not on a Control.
        for (c in controls) {
            if (c.index != null) {
                require(hostedByInventory(blocks, c)) {
                    "index only allowed on InventoryRows controls (${c.id.wire})"
                }
            }
        }
    }

    fun collectControls(): List<Control> {
        val out = ArrayList<Control>()
        fun walk(bs: List<Block>) {
            for (b in bs) {
                when (b) {
                    is Block.Row -> out.addAll(b.controls)
                    is Block.Banner -> out.addAll(b.row.controls)
                    is Block.CodeCommand -> out.add(b.copy)
                    is Block.EmptyMessage -> b.control?.let { out.add(it) }
                    is Block.InventoryRows -> b.rows.forEach { out.addAll(it.controls) }
                    is Block.DraftRows -> b.rows.forEach { out.addAll(it.controls) }
                    is Block.ToolsSection -> walk(b.blocks)
                    else -> Unit
                }
            }
        }
        walk(blocks)
        out.addAll(titleActions)
        return out
    }
}

/** Whether [c] is one of the controls of an InventoryRow reachable from [blocks]. */
private fun hostedByInventory(blocks: List<Block>, c: Control): Boolean = blocks.any { b ->
    when (b) {
        is Block.InventoryRows -> b.rows.any { r -> r.controls.any { it === c } }
        is Block.DraftRows -> b.rows.any { r -> r.controls.any { it === c } }
        is Block.ToolsSection -> hostedByInventory(b.blocks, c)
        else -> false
    }
}

private fun ctrl(
    id: ControlId,
    label: String?,
    emphasis: Emphasis,
    enabled: Boolean = true,
    accessibleName: String? = null,
    tooltip: String? = null,
    index: Int? = null,
    supportLinkId: String? = null,
): Control {
    val name = accessibleName
        ?: label
        ?: id.wire
    return Control(
        id = id,
        label = label,
        accessibleName = name,
        emphasis = emphasis,
        enabled = enabled,
        tooltip = tooltip,
        index = index,
        supportLinkId = supportLinkId,
    )
}

private fun pad(position: Int): String =
    if (position < 10) "0$position" else position.toString()

private fun tipShort(tip: String?): String? = tip?.take(7)

private fun entryBadge(entry: PanelEntry, mode: ReviewMode?): String? = when {
    entry.essential -> "key"
    mode == ReviewMode.WALK && !entry.annotated -> "uncovered"
    entry.banked -> "edits"
    else -> null
}

private fun inventoryMeta(r: PanelReview): String = when {
    r.orphan -> "no metadata"
    r.position != null && r.total != null -> "${r.mode?.id ?: "?"} · ${r.position}/${r.total}"
    r.mode != null -> r.mode.id
    else -> "no metadata"
}

private fun inventoryHelp(r: PanelReview): String {
    val finish = r.finish
    if (finish != null) {
        val source = if (r.name.startsWith("review/")) r.name.removePrefix("review/") else r.name
        return if (finish.state == "pending") {
            val dest = if (finish.onto) source else "review-fixes/$source"
            "Finish waiting on $dest — use Undo above."
        } else {
            "Finish stopped mid-conflict — switch to this branch to resolve or undo."
        }
    }
    return "Still active — switch to this branch to work on it."
}

private fun notes(model: PanelModel): List<Block.Note> {
    val out = ArrayList<Block.Note>()
    if (model.readonly) {
        out.add(Block.Note("Read-only compare: finish is not available. Use Cancel when done."))
    }
    if (model.keysOnly) {
        out.add(Block.Note("Keys-only: reading order is restricted to walkthrough entries marked key."))
    }
    if (model.baseMoved) {
        out.add(Block.Note("The base moved: fewer entries remain in range than when the review started."))
    }
    if (model.degraded) {
        out.add(Block.Note("The walkthrough does not cover the review's current range; showing the full range diff."))
    }
    model.base?.let { out.add(Block.Note("Range built against $it.")) }
    return out
}

private fun identityBar(model: PanelModel, skeleton: Boolean = false): Block.IdentityBar {
    val name = model.source ?: model.branch ?: "?"
    val displayName = if (model.repoLabel != null) "$name · ${model.repoLabel}" else name
    return Block.IdentityBar(
        mode = model.mode?.id ?: "?",
        draft = model.draft,
        name = displayName,
        tip = tipShort(model.tip),
        position = if (skeleton) null else model.position,
        total = if (skeleton) null else model.total,
        skeleton = skeleton,
    )
}

private fun openRow(model: PanelModel, enabled: Boolean): Block.Row {
    return if (model.mode == ReviewMode.STEP) {
        Block.Row(listOf(ctrl(ControlId.OPEN_CHANGE, "Diff", Emphasis.SECONDARY, enabled)))
    } else {
        Block.Row(
            listOf(
                ctrl(ControlId.OPEN_ENTRY, "File", Emphasis.SECONDARY, enabled),
                ctrl(ControlId.OPEN_CHANGE, "Diff", Emphasis.SECONDARY, enabled),
            ),
        )
    }
}

private fun navRow(model: PanelModel, enabled: Boolean): Block.Row {
    val baseEnabled = enabled && !model.busy
    return Block.Row(
        listOf(
            ctrl(
                ControlId.PREV,
                label = null,
                emphasis = Emphasis.ICON,
                enabled = baseEnabled && !model.atFirst,
                accessibleName = "Previous entry",
            ),
            ctrl(
                ControlId.NEXT,
                label = null,
                emphasis = Emphasis.ICON,
                enabled = baseEnabled && !model.atLast,
                accessibleName = "Next entry",
            ),
        ),
    )
}

private fun whyBlock(why: PanelWhy, entry: PanelEntry?, mode: ReviewMode?): Block.Why {
    val uncovered = mode == ReviewMode.WALK && entry?.annotated == false
    return when (why.state) {
        WhyState.PRESENT -> Block.Why(WhyState.PRESENT, why.text, uncovered = false)
        WhyState.ABSENT -> Block.Why(
            WhyState.ABSENT,
            text = if (uncovered) {
                "This file changes in the review and the walkthrough does not annotate it."
            } else {
                "This entry has no explanation."
            },
            uncovered = uncovered,
        )
        WhyState.FAILED -> Block.Why(WhyState.FAILED, "Could not read the why for this entry.")
        WhyState.LOADING -> Block.Why(WhyState.LOADING)
    }
}

private fun entryBlocks(model: PanelModel, enabled: Boolean, includeNav: Boolean): List<Block> {
    val current = model.current
    if (current == null) {
        return listOf(
            Block.EmptyMessage("The cursor does not point at any entry in the sequence."),
        )
    }
    val out = ArrayList<Block>()
    val named = model.mode == ReviewMode.STEP && current.subject != null
    out.add(
        Block.EntryHead(
            position = current.position,
            identifier = if (named) current.display else null,
            author = if (named) current.author else null,
            badge = entryBadge(current, model.mode),
        ),
    )
    if (named && current.subject.isEmpty()) {
        out.add(Block.EntryTitle("This commit has no subject.", muted = true))
    } else {
        out.add(Block.EntryTitle(if (named) current.subject else current.display))
    }
    if (model.mode == ReviewMode.WALK) {
        val why = model.why
        if (why != null) {
            out.add(whyBlock(why, current, model.mode))
            if (why.state == WhyState.PRESENT) {
                out.add(
                    Block.Row(
                        listOf(
                            ctrl(ControlId.SHOW_WHY, "open in editor", Emphasis.LINK, enabled),
                        ),
                    ),
                )
            }
        }
    }
    out.add(openRow(model, enabled))
    // Step: file inventory of the current commit under the Diff of the commit
    // (same selectable rows as whole; openChange with index opens one path).
    if (model.mode == ReviewMode.STEP) {
        out.addAll(fileInventoryBlocks(model, enabled, unit = "commit", includeOpenAll = false))
    }
    if (includeNav && !model.navigationLocked) {
        out.add(navRow(model, enabled))
    }
    return out
}

private fun wholeBlocks(model: PanelModel, enabled: Boolean): List<Block> =
    fileInventoryBlocks(model, enabled, unit = "review", includeOpenAll = true)

/**
 * Selectable file list shared by whole (range) and step (current commit).
 * [unit] is "review" or "commit" for the heading / empty copy.
 * [includeOpenAll] is whole-only (step already has Diff on the commit row).
 */
private fun fileInventoryBlocks(
    model: PanelModel,
    enabled: Boolean,
    unit: String,
    includeOpenAll: Boolean,
): List<Block> {
    if (model.files.isEmpty()) {
        val empty = if (unit == "commit") {
            "This commit changes no files."
        } else {
            "This review's range does not touch any files."
        }
        return listOf(Block.EmptyMessage(empty))
    }
    val n = model.files.size
    val heading = if (n == 1) "1 file in this $unit" else "$n files in this $unit"
    val out = ArrayList<Block>()
    out.add(Block.Heading(heading))
    if (includeOpenAll) {
        // Diff opens a single DiffRequestChain window (Prev/Next file), not one tab each.
        out.add(
            Block.Row(
                listOf(
                    ctrl(
                        ControlId.OPEN_ALL_CHANGES,
                        "Diff",
                        Emphasis.SECONDARY,
                        enabled,
                        tooltip = "Open every change in this review at once",
                    ),
                ),
            ),
        )
    }
    out.add(
        Block.FileRows(
            model.files.map { f ->
                FileRow(
                    display = f.display,
                    index = f.position,
                    lastOpened = f.display == model.lastOpened,
                )
            },
        ),
    )
    return out
}

private fun finishConflictBanner(enabled: Boolean): Block.Banner =
    Block.Banner(
        paragraphs = listOf(
            "This finish stopped at a conflict. Resolve the markers, then continue — or undo it to go back to editing.",
        ),
        row = Block.Row(
            listOf(
                ctrl(ControlId.UNDO_FINISH, "Undo", Emphasis.SECONDARY, enabled),
                ctrl(ControlId.RESUME_FINISH, "Continue", Emphasis.SECONDARY, enabled),
            ),
        ),
    )

private fun finishPendingBlocks(model: PanelModel): List<Block> {
    val pending = model.pendingFinish
    var source = "this branch"
    var destination = "review-fixes/..."
    if (pending != null) {
        source = if (pending.branch.startsWith("review/")) {
            pending.branch.removePrefix("review/")
        } else {
            pending.branch
        }
        destination = if (pending.onto) source else "review-fixes/$source"
    }
    val enabled = !model.busy
    return listOf(
        Block.Banner(
            paragraphs = listOf(
                "Finished. Your edits are staged on $destination.",
                "Commit and push them from Source Control. The review branch is kept so you can undo with git review finish --abort, or clean --keep-fixes when you no longer need the undo.",
            ),
            row = Block.Row(
                listOf(
                    ctrl(ControlId.CLEAN_REVIEW, "Clean", Emphasis.PRIMARY, enabled),
                    ctrl(ControlId.UNDO_FINISH, "Undo finish", Emphasis.SECONDARY, enabled),
                ),
            ),
        ),
    )
}

private fun cliBlocks(model: PanelModel, missing: Boolean): List<Block> {
    val title = if (missing) {
        "The git-review CLI ($MIN_CLI_VERSION or newer) was not found."
    } else {
        "The installed git-review CLI is older than $MIN_CLI_VERSION."
    }
    val hint = if (missing) "Install with npm (recommended):" else "Update with npm (recommended):"
    val cmd = if (missing) NPM_INSTALL_CMD else NPM_UPDATE_CMD
    val out = ArrayList<Block>()
    out.add(Block.Paragraph(title))
    // The hint and the reload line are asides around the command, not the
    // message itself (the extension's `.cli-install-hint` / `-reload`).
    out.add(Block.Paragraph(hint, muted = true))
    out.add(
        Block.CodeCommand(
            command = cmd,
            copy = ctrl(
                ControlId.COPY_CLI_INSTALL,
                "Copy",
                Emphasis.SECONDARY,
                accessibleName = "Copy install command",
                tooltip = "Copy to clipboard",
            ),
        ),
    )
    out.add(
        Block.Paragraph(
            "Reload the window after installing, or wait — the panel checks again every few seconds.",
            muted = true,
        ),
    )
    out.add(
        Block.Row(
            listOf(ctrl(ControlId.INSTALL_CLI, "Other install options", Emphasis.LINK)),
        ),
    )
    if (!model.stderr.isNullOrBlank()) {
        out.add(Block.Stderr(model.stderr))
    }
    return out
}

private fun setupBlocks(model: PanelModel): List<Block> {
    val remote = model.configuredRemote ?: "origin"
    val enabled = !model.busy
    return listOf(
        Block.Paragraph("Configure git review for this repository."),
        Block.Row(listOf(ctrl(ControlId.SET_BASE, "Set the base branch", Emphasis.PRIMARY, enabled))),
        Block.Paragraph(
            "The base is where PRs land in this repo (main, develop, …). Full reviews compare the branch under review against it.",
        ),
        Block.Paragraph("Remote: $remote (optional)."),
        Block.Row(listOf(ctrl(ControlId.SET_REMOTE, "Change remote", Emphasis.SECONDARY, enabled))),
    )
}

private fun inventoryRows(model: PanelModel): Block.InventoryRows {
    val enabled = !model.busy
    val rows = model.reviews.mapIndexed { index, r ->
        val badges = buildList {
            if (r.current) add("current")
            if (r.orphan) add("orphan")
        }
        val canDiscard = r.saved || r.orphan
        val controls = ArrayList<Control>()
        if (canDiscard) {
            if (r.saved) {
                val tip = when {
                    r.resumable -> null
                    r.orphan -> "This branch has no review metadata — use Discard"
                    else -> "A review of this branch is already active"
                }
                controls.add(
                    ctrl(
                        ControlId.CONTINUE_REVIEW,
                        "Continue",
                        Emphasis.SECONDARY,
                        enabled = enabled && r.resumable,
                        tooltip = tip,
                        index = index,
                    ),
                )
            }
            val discardLabel = if (r.orphan) "Discard orphan" else "Discard"
            val discardTip = if (r.saved) {
                "git review forget --saved (with confirmation)"
            } else {
                "git review clean (with confirmation)"
            }
            controls.add(
                ctrl(
                    ControlId.DISCARD_INVENTORY,
                    discardLabel,
                    Emphasis.SECONDARY,
                    enabled = enabled,
                    tooltip = discardTip,
                    index = index,
                ),
            )
        }
        InventoryRow(
            name = r.name,
            badges = badges,
            meta = inventoryMeta(r),
            controls = controls,
            helpTooltip = if (!canDiscard && !r.current) inventoryHelp(r) else null,
        )
    }
    return Block.InventoryRows(rows)
}

/**
 * The draft block: reading orders the reviewer started and has not paused, each
 * with its four controls. First block of the empty state, with the usual body
 * whole underneath — it is not a sub-layout that replaces, the way the setup
 * gate is: with no base configured there is nothing else to do in this panel,
 * with a half-written reading order there is.
 */
private fun draftRows(model: PanelModel): Block.DraftRows {
    val enabled = !model.busy
    val rows = model.drafts.mapIndexed { index, d ->
        // One emphatic control per row, and the progress picks which: while
        // entries are missing the next step is writing the order, and only once
        // it is complete is it starting the review. The ORDER is fixed — moving
        // the click target as the state changes slides it under the cursor.
        //
        // total == 0 means "this file declares no entry at all", never
        // "complete": the CLI reports 0/0 both for an emptied draft and for the
        // one an agent is writing right now (the watcher fires on the first
        // Changed, before the first "## N." heading lands). Without the
        // total > 0 the row is drawn as finished and the emphasis goes to
        // Validate and start, which there is usually disabled too (source and
        // range unknown) — the one emphatic control of the row cannot even be
        // clicked, in the very state that most needs Copy for agent to lead.
        val filled = d.total > 0 && d.annotated >= d.total
        val controls = ArrayList<Control>()
        controls.add(
            ctrl(
                ControlId.COPY_DRAFT_PROMPT,
                "Copy for agent",
                if (filled) Emphasis.SECONDARY else Emphasis.PRIMARY,
                enabled = true,
                tooltip = "Copy an instruction naming this file",
                index = index,
            ),
        )
        // Always drawn, switched off for two different reasons, each of which
        // says its own thing. The flags come first: with no instruction block
        // the build fails on drift however complete the order is, so filling it
        // in is not the next step there.
        //
        // Off by progress is what makes the pair honest. The skeleton leaves a
        // placeholder per entry AND one for the heads-up, the pair counts all
        // of them, and build refuses on any of them alike — left on, the one
        // emphatic control of the row offered a start that died on "the
        // heads-up placeholder is still there". The known cost: the count comes
        // off the disk, so a draft open with unsaved edits keeps the control
        // gray until Ctrl+S (the host watches the draft's directory, so saving
        // refreshes the panel on its own), and in exchange nobody starts over a
        // half-written reading order.
        controls.add(
            ctrl(
                ControlId.START_FROM_DRAFT,
                "Validate and start",
                if (filled) Emphasis.PRIMARY else Emphasis.SECONDARY,
                enabled = enabled && d.startable && filled,
                tooltip = if (!d.startable) {
                    "This draft has no instruction block, so the CLI cannot tell how it was generated"
                } else if (filled) {
                    "git review walkthrough draft --build, then start"
                } else {
                    "Every entry needs a number and a why, and the heads-up needs prose or deleting"
                },
                index = index,
            ),
        )
        // The two controls of the ROW, and that is why they leave the button
        // pair: they move nothing along, they are used once in a while, and
        // their subject is the file the progress pair just named. They are
        // drawn as glyphs beside that pair, which leaves two controls below in
        // two columns and a single line. With all four together the row was
        // twice as tall and the irreversible one shared box and weight with the
        // one that starts the review — dropping its fill lowered it a step, but
        // a box-less button among boxed buttons reads as disabled. An icon does
        // not.
        //
        // With no visible label the accessible name IS the name of the control,
        // and it names the row: "Open" on its own repeats once per draft.
        controls.add(
            ctrl(
                ControlId.OPEN_DRAFT,
                null,
                Emphasis.ICON,
                enabled = true,
                accessibleName = "Open the reading order",
                tooltip = "Open the reading order for editing",
                index = index,
            ),
        )
        controls.add(
            ctrl(
                ControlId.DISCARD_DRAFT,
                null,
                Emphasis.ICON,
                enabled = enabled,
                accessibleName = "Discard the reading order",
                tooltip = "git review forget --draft (with confirmation)",
                index = index,
            ),
        )
        DraftRow(name = d.branch, meta = "${d.annotated}/${d.total}", controls = controls)
    }
    return Block.DraftRows(rows)
}

/**
 * The authoring-guide block, inside the Walkthrough section. Two rows, always
 * both, whether or not either file exists: what the state changes is the enabled
 * of each control, never its presence -- two rows that build different button
 * sets do not line up with each other, the same rule the draft rows follow.
 *
 * Discard is the one exception, and it is not forgotten symmetry: the shared
 * guide is a tracked file, so removing it is `git rm` plus a commit -- a
 * decision about what goes into the PR, which is not this button's to make. The
 * CLI says the same from its side, refusing `--delete --team`.
 */
private fun guideRows(model: PanelModel): Block.GuideRows {
    val enabled = !model.busy
    val rows = model.guides.mapIndexed { index, g ->
        val controls = ArrayList<Control>()
        controls.add(
            ctrl(
                ControlId.CREATE_GUIDE,
                "Create",
                Emphasis.SECONDARY,
                enabled = enabled && g.creatable,
                tooltip = if (g.exists) {
                    "It already exists; open it and edit it"
                } else if (g.creatable) {
                    "Create it empty, then write the conventions into it"
                } else {
                    "Not from inside a review: finish extracts the working tree, so this file would leave on review-fixes/"
                },
                index = index,
            ),
        )
        // With no visible label the accessible name IS the name of the control,
        // and it names the row: "Open" on its own repeats once per guide.
        controls.add(
            ctrl(
                ControlId.OPEN_GUIDE,
                null,
                Emphasis.ICON,
                enabled = g.exists,
                accessibleName = "Open the guide",
                tooltip = if (g.exists) g.path else "There is no file to open yet",
                index = index,
            ),
        )
        if (g.kind == GuideKind.OWN) {
            controls.add(
                ctrl(
                    ControlId.DISCARD_GUIDE,
                    null,
                    Emphasis.ICON,
                    enabled = enabled && g.discardable,
                    accessibleName = "Discard the guide",
                    tooltip = "git review walkthrough guide --delete (with confirmation)",
                    index = index,
                ),
            )
        }
        GuideRow(name = g.label, badge = g.badge, controls = controls)
    }
    return Block.GuideRows(rows)
}

private fun noReviewReadyBlocks(model: PanelModel): List<Block> {
    val enabled = !model.busy
    val out = ArrayList<Block>()
    if (model.drafts.isNotEmpty()) {
        out.add(Block.Heading("Reading orders you started"))
        out.add(draftRows(model))
    }
    if (model.reviews.isNotEmpty()) {
        out.add(Block.Heading("Reviews in this repository"))
        out.add(inventoryRows(model))
    }
    out.add(
        Block.Paragraph(
            "No active review on this branch.",
            separated = model.reviews.isNotEmpty() || model.drafts.isNotEmpty(),
        ),
    )
    out.add(
        Block.Row(listOf(ctrl(ControlId.START_REVIEW, "Start a review", Emphasis.PRIMARY, enabled))),
    )
    // Footer tools
    out.add(
        Block.ToolsSection(
            title = "Other actions",
            blocks = listOf(
                Block.Row(
                    listOf(ctrl(ControlId.COMPARE_REVIEW, "Compare revisions", Emphasis.SECONDARY, enabled)),
                ),
            ),
        ),
    )
    // Everything about the walkthrough together: init, build and the two
    // authoring guides. It left "Other actions" when the guides arrived -- four
    // controls about the same noun plus one unrelated (Compare) is not a list of
    // other actions, it is a drawer. Grouped this way the panel says what the CLI
    // says, where all four hang off the walkthrough verb.
    val walkthroughKids = ArrayList<Block>()
    walkthroughKids.add(
        Block.Row(
            listOf(
                ctrl(ControlId.WALKTHROUGH_INIT, "Walkthrough: Init", Emphasis.SECONDARY, enabled),
                ctrl(ControlId.WALKTHROUGH_BUILD, "Walkthrough: Build", Emphasis.SECONDARY, enabled),
            ),
        ),
    )
    if (model.guides.isNotEmpty()) {
        walkthroughKids.add(guideRows(model))
    }
    out.add(Block.ToolsSection(title = "Walkthrough", blocks = walkthroughKids))
    val settingsKids = ArrayList<Block>()
    model.configuredBase?.let { base ->
        settingsKids.add(Block.Paragraph("Base: $base."))
        settingsKids.add(
            Block.Row(listOf(ctrl(ControlId.SET_BASE, "Change the base branch", Emphasis.SECONDARY, enabled))),
        )
    }
    model.configuredRemote?.let { remote ->
        settingsKids.add(Block.Paragraph("Remote: $remote."))
        settingsKids.add(
            Block.Row(listOf(ctrl(ControlId.SET_REMOTE, "Change remote", Emphasis.SECONDARY, enabled))),
        )
    }
    out.add(Block.ToolsSection(title = "Settings", blocks = settingsKids))
    out.add(
        Block.ToolsSection(
            title = "Support",
            blocks = listOf(
                Block.Row(
                    listOf(
                        ctrl(
                            ControlId.OPEN_SUPPORT,
                            "Star on GitHub",
                            Emphasis.SECONDARY,
                            supportLinkId = SupportLinks.STAR,
                        ),
                        ctrl(
                            ControlId.OPEN_SUPPORT,
                            "Report a bug",
                            Emphasis.SECONDARY,
                            supportLinkId = SupportLinks.BUG,
                        ),
                    ),
                ),
            ),
        ),
    )
    return out
}

private fun diagnosticBlocks(model: PanelModel, outOfRange: Boolean): List<Block> {
    val text = if (outOfRange) {
        "The cursor is out of range: the base moved."
    } else {
        "Something went wrong reading the review state."
    }
    val out = ArrayList<Block>()
    out.add(Block.Paragraph(text))
    out.add(
        Block.Row(
            listOf(ctrl(ControlId.OUT_OF_RANGE_HELP, "How to fix it", Emphasis.PRIMARY)),
        ),
    )
    if (!model.stderr.isNullOrBlank()) {
        out.add(Block.Stderr(model.stderr))
    }
    return out
}

private fun skeletonBody(model: PanelModel): List<Block> {
    val out = ArrayList<Block>()
    out.add(identityBar(model, skeleton = true))
    out.addAll(notes(model))
    out.add(Block.EntryHead(position = model.position ?: 0, skeleton = true))
    out.add(Block.EntryTitle("", skeleton = true))
    if (model.mode == ReviewMode.WALK) {
        out.add(Block.Why(WhyState.LOADING))
    }
    // Real controls, all disabled
    out.add(openRow(model, enabled = false))
    if (model.mode == ReviewMode.STEP) {
        out.addAll(fileInventoryBlocks(model, enabled = false, unit = "commit", includeOpenAll = false))
    }
    if (!model.navigationLocked) {
        out.add(navRow(model, enabled = false))
    }
    return out
}

/**
 * Title-bar actions for the tool window, left-to-right.
 * Refresh is always present; the rest follow view/title when-clauses.
 */
fun titleBarActions(model: PanelModel): List<Control> {
    val out = ArrayList<Control>()
    out.add(ctrl(ControlId.REFRESH, "Refresh", Emphasis.SECONDARY, enabled = true))
    val busy = model.busy
    val sit = model.situation
    if (sit == Situation.REVIEW && !model.readonly && !busy) {
        out.add(ctrl(ControlId.FINISH_REVIEW, "Finish", Emphasis.SECONDARY, enabled = true))
    }
    if (sit == Situation.REVIEW && !busy) {
        out.add(ctrl(ControlId.SAVE_REVIEW, "Save", Emphasis.SECONDARY, enabled = true))
    }
    if ((sit == Situation.REVIEW || sit == Situation.FINISH_CONFLICT) && !busy) {
        out.add(ctrl(ControlId.ABORT_REVIEW, "Cancel", Emphasis.SECONDARY, enabled = true))
    }
    if ((sit == Situation.REVIEW || sit == Situation.FINISH_CONFLICT) && !busy) {
        out.add(ctrl(ControlId.PREVIEW_EDITS, "Preview edits", Emphasis.SECONDARY, enabled = true))
    }
    return out
}

/**
 * Pure layout projection. When [loading] is true, returns the skeleton silhouette
 * for review-readable situations (controls disabled).
 */
fun panelLayout(model: PanelModel, loading: Boolean = false): PanelLayout {
    val title = titleBarActions(model)
    if (loading && isReviewReadable(model.situation) && model.mode != ReviewMode.WHOLE) {
        return PanelLayout(
            situation = model.situation,
            blocks = skeletonBody(model),
            titleActions = title.map { it.copy(enabled = false) },
            fillsHeight = false,
        )
    }

    val blocks: List<Block>
    var fills = false
    when (model.situation) {
        Situation.CLI_MISSING -> blocks = cliBlocks(model, missing = true)
        Situation.CLI_OUTDATED -> blocks = cliBlocks(model, missing = false)
        Situation.OUT_OF_RANGE -> blocks = diagnosticBlocks(model, outOfRange = true)
        Situation.ERROR -> blocks = diagnosticBlocks(model, outOfRange = false)
        Situation.FINISH_PENDING -> blocks = finishPendingBlocks(model)
        Situation.NO_REVIEW -> {
            if (model.noBaseConfigured) {
                blocks = setupBlocks(model)
            } else {
                blocks = noReviewReadyBlocks(model)
                fills = true
            }
        }
        Situation.REVIEW, Situation.FINISH_CONFLICT -> {
            val enabled = !model.busy
            val out = ArrayList<Block>()
            out.add(identityBar(model))
            if (model.situation == Situation.FINISH_CONFLICT) {
                out.add(finishConflictBanner(enabled))
            }
            out.addAll(notes(model))
            when (model.mode) {
                ReviewMode.WHOLE -> out.addAll(wholeBlocks(model, enabled))
                ReviewMode.WALK, ReviewMode.STEP, null -> {
                    out.addAll(
                        entryBlocks(
                            model,
                            enabled = enabled,
                            includeNav = model.situation == Situation.REVIEW,
                        ),
                    )
                }
            }
            // The guides inside a review too, folded and last: the walkthrough draft
            // verb is run from in here, which is the likeliest moment to want to write
            // yours. It is the ONLY tools section a review has -- init and build do not
            // belong (they are the author's, standing on their own PR) and neither does
            // the rest of the footer. Not in finish-conflict: that screen is "resolve
            // the markers", and a folded section about writing conventions is noise.
            if (model.situation == Situation.REVIEW && model.guides.isNotEmpty()) {
                out.add(Block.ToolsSection(title = "Walkthrough", blocks = listOf(guideRows(model))))
            }
            blocks = out
        }
    }
    return PanelLayout(
        situation = model.situation,
        blocks = blocks,
        titleActions = title,
        fillsHeight = fills,
    )
}
