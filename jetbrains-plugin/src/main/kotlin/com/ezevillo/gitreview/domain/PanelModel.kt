package com.ezevillo.gitreview.domain

enum class WhyState {
    LOADING, PRESENT, ABSENT, FAILED;

    val id: String
        get() = when (this) {
            LOADING -> "loading"
            PRESENT -> "present"
            ABSENT -> "absent"
            FAILED -> "failed"
        }
}

data class PanelWhy(
    val state: WhyState,
    val text: String? = null,
)

data class PanelEntry(
    val position: Int,
    val display: String,
    val essential: Boolean,
    val annotated: Boolean,
    val banked: Boolean,
    val subject: String? = null,
    val author: String? = null,
)

data class PanelReview(
    val name: String,
    val saved: Boolean,
    val current: Boolean,
    val orphan: Boolean,
    val mode: ReviewMode? = null,
    val position: Int? = null,
    val total: Int? = null,
    val resumable: Boolean,
    val finish: BranchFinish? = null,
)

/**
 * A row of the empty state's draft block: a reading order the reviewer started
 * and has not paused. Flat projection, with nothing derived — the progress is
 * counted by the CLI and the path is resolved by the CLI.
 */
data class PanelDraft(
    val branch: String,
    val path: String,
    val annotated: Int,
    val total: Int,
    /**
     * Whether *Validate and start* can be **invoked** for this row: only when
     * the CLI knows the origin and range the draft was generated with. With
     * `UNKNOWN` (the instruction block was deleted by hand) invoking with the
     * defaults would fail with a drift error every time.
     *
     * The control is drawn either way, switched off: off guesses the flags no
     * more than absent did -- it still cannot be invoked -- and unlike absent it
     * can say why in its tooltip. The row also keeps its four cells, so it does
     * not change shape with its state.
     */
    val startable: Boolean,
    /**
     * Whether its review is over. A draft outlives the review it was written
     * for -- clean does not touch hand-written prose -- but it stops being work
     * in progress, so it leaves the block at the top for a collapsed section
     * with the two controls that still make sense: open it and discard it. The
     * CLI decides it; nothing is inferred here.
     */
    val spent: Boolean,
)

/**
 * A row of the authoring-guide block: prose about the CONTENT of a walkthrough,
 * not about its format.
 *
 * BOTH rows are always drawn, whether or not either file exists, and what the
 * state changes is the enabled of the controls, never their presence -- the same
 * rule as the draft rows, and for the same reason: two rows with different
 * button sets do not line up with each other.
 *
 * [label] and [badge] are derived here because they are panel copy; [path]
 * comes from the CLI, and the client **opens it, never rebuilds it**.
 */
data class PanelGuide(
    val kind: GuideKind,
    /** The row name: the shared committed one, or yours from outside the tree. */
    val label: String,
    /** Absolute, reported by the CLI. On disk only when `state != ABSENT`. */
    val path: String,
    val state: GuideState,
    /** Badge text: the state the CLI reported, in prose. */
    val badge: String,
    /** The file is there (in force or empty): it can be opened, and if it is yours, discarded. */
    val exists: Boolean,
    /**
     * Yours only. The shared one is a tracked file, so removing it is `git rm`
     * plus a commit: a decision about what goes into the PR, which is not this
     * button's to make. The CLI says the same from its side, refusing
     * `--delete --team`.
     */
    val discardable: Boolean,
)

/**
 * The author's own walkthrough row: what state it is in, how much of it is
 * written, and what can be done with it without leaving the panel.
 *
 * It exists because a walkthrough is written once, when the PR is finished, and
 * then the PR keeps moving. The row is the only surface that says so without
 * anybody remembering to ask, which is why the badge is deliberately cautious:
 * "may be out of date" and not "out of date". The exact answer is `build`'s,
 * which is what the button beside it runs.
 *
 * [label], [badge] and [actionLabel] are panel copy and are derived here; [path]
 * comes from the CLI, and the client **opens it, never rebuilds it**.
 */
data class PanelWalkthrough(
    /**
     * What the row is called: **the branch** this walkthrough annotates, as the
     * CLI reported it. Falls back to "Walkthrough" only when the record omitted
     * the field, which is what a detached `HEAD` does.
     */
    val label: String,
    /** Absolute, reported by the CLI. On disk only when `state != ABSENT`. */
    val path: String,
    val state: WalkthroughState,
    /** Badge text: the state the CLI reported, in prose. */
    val badge: String,
    /** Finished entries, and everything build requires (entries plus the heads-up). */
    val annotated: Int,
    val total: Int,
    /** The file is there: it can be opened, and there is something to hand an agent. */
    val exists: Boolean,
    /** What the control that invokes `walkthrough init` is called -- it creates AND updates. */
    val actionLabel: String,
)

data class PanelModel(
    val situation: Situation,
    val busy: Boolean,
    val repoLabel: String? = null,
    val reviews: List<PanelReview> = emptyList(),
    /**
     * Same rule as [reviews]: only with `NO_REVIEW`, empty in any other
     * situation. A review in progress is always the most important thing the
     * panel has to say, and another branch's draft does not compete for the body.
     */
    val drafts: List<PanelDraft> = emptyList(),
    /**
     * Both authoring guides, in the CLI's order (shared, yours). Same rule as
     * [drafts]: only with `NO_REVIEW`, empty in any other situation -- inside a
     * review the panel has more urgent things to say, and creating the shared one
     * there is refused by the CLI anyway.
     */
    val guides: List<PanelGuide> = emptyList(),
    /**
     * The author's walkthrough, when the CLI reported its row. Null against a CLI
     * older than the record, and then the block is not drawn.
     */
    val walkthrough: PanelWalkthrough? = null,
    val pendingFinish: PendingFinish? = null,
    val noBaseConfigured: Boolean = false,
    val configuredBase: String? = null,
    val configuredRemote: String? = null,
    val mode: ReviewMode? = null,
    val branch: String? = null,
    val source: String? = null,
    val tip: String? = null,
    val base: String? = null,
    val position: Int? = null,
    val total: Int? = null,
    val baseMoved: Boolean = false,
    val atFirst: Boolean = false,
    val atLast: Boolean = false,
    val navigationLocked: Boolean = false,
    val degraded: Boolean = false,
    val readonly: Boolean = false,
    val keysOnly: Boolean = false,
    /** 011: el orden de lectura es el borrador del revisor (registro `draft`). */
    val draft: Boolean = false,
    val current: PanelEntry? = null,
    val entryCount: Int = 0,
    val files: List<PanelEntry> = emptyList(),
    val lastOpened: String? = null,
    val why: PanelWhy? = null,
    val stderr: String? = null,
)

data class PendingFinish(
    val branch: String,
    val onto: Boolean,
)

data class PanelInputs(
    val busy: Boolean,
    val repoLabel: String? = null,
    val why: PanelWhy? = null,
    val lastOpened: String? = null,
)

data class PickLabel(
    val label: String,
    val description: String,
)

private fun displayOf(id: Any): String = when (id) {
    is PathRef -> id.display
    is String -> id
    else -> id.toString()
}

private fun toPanelEntry(
    entry: EntryRecord,
    subjects: Map<Int, String>?,
    authors: Map<Int, String>?,
): PanelEntry {
    val panelEntry = PanelEntry(
        position = entry.position,
        display = displayOf(entry.id),
        essential = entry.essential == true,
        annotated = entry.annotated != false,
        banked = entry.banked == true,
        subject = subjects?.get(entry.position),
        author = authors?.get(entry.position),
    )
    return panelEntry
}

private fun pad(position: Int): String =
    if (position < 10) "0$position" else position.toString()

fun entryPickLabel(entry: EntryRecord, position: Int?, subject: String?): PickLabel {
    val marks = ArrayList<String>()
    if (entry.position == position) marks.add("current")
    if (entry.essential == true) marks.add("key")
    if (entry.annotated == false) marks.add("uncovered")
    if (entry.banked == true) marks.add("banked edits")
    val id = displayOf(entry.id)
    val label = if (!subject.isNullOrEmpty()) {
        "${pad(entry.position)}  $id  $subject"
    } else {
        "${pad(entry.position)}  $id"
    }
    return PickLabel(label = label, description = marks.joinToString(" · "))
}

fun currentEntry(entries: List<EntryRecord>, position: Int?): EntryRecord? {
    if (position == null) return null
    return entries.find { it.position == position }
}

private fun toPanelReviews(branches: List<BranchRecord>): List<PanelReview> {
    val active = branches.filter { !it.saved }.map { sourceOf(it) }.toSet()
    return branches.map { branch ->
        PanelReview(
            name = branch.name,
            saved = branch.saved,
            current = branch.current,
            orphan = branch.orphan,
            mode = branch.mode,
            position = if (branch.position != null && branch.total != null) branch.position else null,
            total = if (branch.position != null && branch.total != null) branch.total else null,
            resumable = branch.saved && !branch.orphan && sourceOf(branch) !in active,
            finish = branch.finish,
        )
    }
}

/**
 * Projects the `draft` records of `config --porcelain`, one to one and in the
 * CLI's order. A paused review's draft never gets here — the CLI does not
 * report it, because save moved its file to the archived namespace.
 */
fun toPanelDrafts(drafts: List<DraftRecord>): List<PanelDraft> =
    drafts.map { draft ->
        PanelDraft(
            branch = draft.src,
            path = draft.path,
            annotated = draft.annotated,
            total = draft.total,
            startable = draft.source != DraftSource.UNKNOWN && draft.range != DraftRange.UNKNOWN,
            spent = draft.state == DraftState.REVIEWED,
        )
    }

/**
 * The badge for each state: two are the CLI's values; `absent` reads
 * "none", because "empty" and "absent" look like synonyms at a glance and are
 * not -- `empty` is "the file is there, it says nothing" and `absent` is "there
 * is no file", which is what decides whether the button beside it opens or
 * creates.
 */
private fun guideBadge(state: GuideState): String = when (state) {
    GuideState.IN_FORCE -> "in force"
    GuideState.EMPTY -> "empty"
    GuideState.ABSENT -> "none"
}

private fun guideLabel(kind: GuideKind): String = when (kind) {
    GuideKind.TEAM -> "Repository guide"
    GuideKind.OWN -> "Your guide"
}

/**
 * Projects the `guide` records, one to one and in the CLI's order, without
 * filling in a missing one: a record that did not arrive is a row that is not
 * drawn. Against a CLI that does not know the record none arrive and the whole
 * block disappears, which is the same degradation the draft block has.
 */
fun toPanelGuides(guides: List<GuideRecord>): List<PanelGuide> {
    return guides.map { guide ->
        PanelGuide(
            kind = guide.kind,
            label = guideLabel(guide.kind),
            path = guide.path,
            state = guide.state,
            badge = guideBadge(guide.state),
            exists = guide.state != GuideState.ABSENT,
            discardable = guide.kind == GuideKind.OWN && guide.state != GuideState.ABSENT,
        )
    }
}

private fun walkthroughBadge(state: WalkthroughState): String = when (state) {
    WalkthroughState.IN_SYNC -> "up to date"
    WalkthroughState.STALE -> "may be out of date"
    WalkthroughState.SUPERSEDED -> "from a merged PR"
    WalkthroughState.UNKNOWN -> "state unknown"
    WalkthroughState.ABSENT -> "none"
}

/**
 * Projects the `walkthrough` record. One row, **always**: `init` and `build` are
 * this row's buttons, so drawing it only sometimes would leave the two verbs
 * without a surface sometimes. With no record -- malformed, or a CLI old enough
 * that the client already rejected it by version -- the row arrives as
 * `UNKNOWN`, which is the state the CLI defines as "the question has no answer":
 * it invents neither a badge nor a path.
 *
 * The row is named after the BRANCH it annotates, not the word "Walkthrough":
 * the section is already called that, and saying it twice added no fact.
 *
 * Everything that decides what can be pressed comes from the state the CLI
 * reported. In particular the action label, which is NOT keyed on staleness:
 * the same verb creates and updates, so the only thing that changes is what it
 * is called, and "Create" over a file full of prose is a promise the CLI does
 * not keep -- nor should it.
 */
fun toPanelWalkthrough(record: WalkthroughRecord?): PanelWalkthrough {
    // With no record there is neither a path nor a state, and neither is made
    // up: UNKNOWN already means "cannot be told" on the CLI's side, and an empty
    // path turns off the two controls that need the file.
    val state = record?.state ?: WalkthroughState.UNKNOWN
    return PanelWalkthrough(
        label = record?.branch ?: "Walkthrough",
        path = record?.path ?: "",
        state = state,
        badge = walkthroughBadge(state),
        annotated = record?.annotated ?: 0,
        total = record?.total ?: 0,
        exists = record != null && state != WalkthroughState.ABSENT,
        // Three labels for one verb. SUPERSEDED is not a flavour of "fell
        // behind": the file is another PR's, and what the CLI does there is
        // start over on its own -- so the button says what will happen instead
        // of promising a reconciliation that does not occur.
        actionLabel = when {
            // No record: nothing is known about the file, so the button keeps
            // the verb's default name. "Update" would promise reconciling
            // something nobody can say is there.
            record == null -> "Create"
            state == WalkthroughState.ABSENT -> "Create"
            state == WalkthroughState.SUPERSEDED -> "Start over"
            else -> "Update"
        },
    )
}

/**
 * The guide row at [index], resolved against the HOST's state. Same role as
 * [draftAt]: what ends up in the CLI does not come from the panel.
 */
fun guideAt(guides: List<GuideRecord>, index: Any?): GuideRecord? {
    if (index !is Int) return null
    return guides.getOrNull(index)
}

/**
 * The draft row at [index], resolved against the HOST's state. Same role as
 * [resumableSourceAt]: what ends up in the CLI does not come from the panel.
 */
fun draftAt(drafts: List<DraftRecord>, index: Any?): DraftRecord? {
    if (index !is Int) return null
    return drafts.getOrNull(index)
}

fun resumableSourceAt(branches: List<BranchRecord>, index: Any?): String? {
    if (index !is Int) return null
    val branch = branches.getOrNull(index) ?: return null
    val review = toPanelReviews(branches).getOrNull(index) ?: return null
    if (!review.resumable) return null
    return sourceOf(branch)
}

fun buildPanelModel(state: ReviewState, inputs: PanelInputs): PanelModel {
    var model = PanelModel(
        situation = state.situation,
        busy = inputs.busy,
        reviews = if (state.situation == Situation.NO_REVIEW) toPanelReviews(state.branches) else emptyList(),
        drafts = if (state.situation == Situation.NO_REVIEW) toPanelDrafts(state.drafts ?: emptyList()) else emptyList(),
        // They only arrive by config --porcelain, that is, only outside a review:
        // the footer is where they are drawn and a review has no footer.
        guides = toPanelGuides(state.guides ?: emptyList()),
        // Only in NO_REVIEW: that is where the section lives, and inside a
        // review the panel draws the guides and nothing else of this block. The
        // row is built even when the record is missing -- see toPanelWalkthrough.
        walkthrough = if (state.situation == Situation.NO_REVIEW) {
            toPanelWalkthrough(state.walkthrough)
        } else {
            null
        },
        noBaseConfigured = state.situation == Situation.NO_REVIEW &&
            state.config != null &&
            state.config.base == null,
        baseMoved = false,
        atFirst = false,
        atLast = false,
        navigationLocked = state.situation == Situation.FINISH_CONFLICT,
        degraded = false,
        readonly = false,
        keysOnly = false,
        draft = false,
        entryCount = 0,
        files = emptyList(),
        repoLabel = inputs.repoLabel,
        stderr = state.stderr?.takeIf { it.trim().isNotEmpty() },
    )

    if (state.situation == Situation.NO_REVIEW && state.config != null) {
        model = model.copy(
            configuredRemote = state.config.remote,
            configuredBase = state.config.base,
        )
    }
    if (state.situation == Situation.FINISH_PENDING) {
        val pending = state.branches.find { it.finish?.state == "pending" }
        if (pending?.finish != null) {
            model = model.copy(
                pendingFinish = PendingFinish(branch = pending.name, onto = pending.finish.onto),
            )
        }
    }

    val review = state.state
    if ((state.situation != Situation.REVIEW && state.situation != Situation.FINISH_CONFLICT) || review == null) {
        return model
    }

    model = model.copy(
        mode = review.mode,
        branch = review.branch,
        source = review.source,
        tip = review.tip,
        degraded = review.walkthrough == WalkthroughStatus.DEGRADED,
        readonly = state.readonly == true,
        keysOnly = state.keysOnly == true,
        draft = state.draft == true,
        entryCount = state.entries.size,
    )

    if (review.mode == ReviewMode.WHOLE) {
        val files = state.entries.map { toPanelEntry(it, state.subjects, state.authors) }
        val lastOpened = inputs.lastOpened?.takeIf { lo -> files.any { it.display == lo } }
        return model.copy(
            base = state.base,
            files = files,
            lastOpened = lastOpened,
        )
    }

    var atFirst = review.position != null && review.position <= 1
    var atLast = review.position != null && review.total != null && review.position >= review.total
    if (model.navigationLocked) {
        atFirst = false
        atLast = false
    }

    val current = currentEntry(state.entries, review.position)
    // Step: file inventory of the commit under the cursor (`file` records).
    val stepFiles = if (review.mode == ReviewMode.STEP) {
        state.files.map { toPanelEntry(it, state.subjects, state.authors) }
    } else {
        emptyList()
    }
    val stepLastOpened = if (review.mode == ReviewMode.STEP) {
        inputs.lastOpened?.takeIf { lo -> stepFiles.any { it.display == lo } }
    } else {
        null
    }
    model = model.copy(
        position = review.position,
        total = review.total,
        baseMoved = review.recorded != null && review.total != null && review.total < review.recorded,
        atFirst = atFirst,
        atLast = atLast,
        current = current?.let { toPanelEntry(it, state.subjects, state.authors) },
        files = stepFiles,
        lastOpened = stepLastOpened,
        why = if (review.mode == ReviewMode.WALK && current != null) {
            inputs.why ?: PanelWhy(WhyState.LOADING)
        } else null,
    )
    return model
}
