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
     * Whether *Validate and start* can be offered: only when the CLI knows the
     * origin and range the draft was generated with. With `UNKNOWN` (the
     * instruction block was deleted by hand) invoking with the defaults would
     * fail with a drift error every time, so one control fewer beats one that
     * guesses.
     */
    val startable: Boolean,
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
        )
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
