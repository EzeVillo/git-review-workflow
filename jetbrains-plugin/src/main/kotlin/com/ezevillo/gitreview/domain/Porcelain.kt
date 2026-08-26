package com.ezevillo.gitreview.domain

enum class ReviewMode {
    WHOLE, STEP, WALK;

    val id: String
        get() = when (this) {
            WHOLE -> "whole"
            STEP -> "step"
            WALK -> "walk"
        }

    companion object {
        fun parse(field: String?): ReviewMode? = when (field) {
            "whole" -> WHOLE
            "step" -> STEP
            "walk" -> WALK
            else -> null
        }
    }
}

enum class WalkthroughStatus {
    NONE, APPLIED, DEGRADED;

    val id: String
        get() = when (this) {
            NONE -> "none"
            APPLIED -> "applied"
            DEGRADED -> "degraded"
        }

    companion object {
        fun parse(field: String?): WalkthroughStatus? = when (field) {
            "none" -> NONE
            "applied" -> APPLIED
            "degraded" -> DEGRADED
            else -> null
        }
    }
}

data class StateRecord(
    val branch: String,
    val source: String,
    val tip: String,
    val mode: ReviewMode,
    val walkthrough: WalkthroughStatus,
    val position: Int? = null,
    val total: Int? = null,
    val recorded: Int? = null,
    /** Short SHA (step) or [PathRef] (walk). */
    val current: Any? = null,
    val essential: Boolean? = null,
)

data class EntryRecord(
    val position: Int,
    /** Short SHA (step) or [PathRef] (walk/whole). */
    val id: Any,
    val essential: Boolean? = null,
    val annotated: Boolean? = null,
    val banked: Boolean? = null,
)

data class StatusFinishRecord(
    val state: String = "conflict",
    val onto: Boolean,
)

data class PorcelainResult(
    val state: StateRecord,
    val entries: List<EntryRecord>,
    /**
     * Step-mode inventory of files in the *current* commit (`file` records).
     * Position is 1-based within that commit. Empty when the CLI emits none
     * (empty commit, or walk/whole where `file` is not used).
     */
    val files: List<EntryRecord> = emptyList(),
    val finish: StatusFinishRecord? = null,
    val readonly: Boolean? = null,
    val keysOnly: Boolean? = null,
    /**
     * 011: el orden de lectura es el borrador del revisor, no el walkthrough
     * del autor. Sólo se da en walk; nunca se infiere, llega por el registro.
     */
    val draft: Boolean? = null,
    /**
     * 012: la ruta absoluta de ese borrador, tal como la reportó la CLI en el
     * campo del registro. Aparte del booleano: la presencia sigue siendo la
     * presencia, y un registro sin campo (una CLI anterior) no la apaga.
     */
    val draftPath: String? = null,
    val subjects: Map<Int, String>? = null,
    val authors: Map<Int, String>? = null,
    val base: String? = null,
)

data class BranchFinish(
    val state: String, // "pending" | "conflict"
    val onto: Boolean,
)

data class BranchRecord(
    val name: String,
    val saved: Boolean,
    val current: Boolean,
    val orphan: Boolean,
    val mode: ReviewMode? = null,
    val position: Int? = null,
    val total: Int? = null,
    val finish: BranchFinish? = null,
)

/**
 * How much work dropping a `review-fixes/` branch would cost.
 *
 * `empty` is not a flavour of "safe": an untouched fixes branch sits at the PR
 * tip and holds NOTHING of yours, which is a different thing from being already
 * integrated. `unknown` does not fold into `unmerged` either -- with no base
 * configured the question has no answer, and giving the worse of the two paints
 * a branch that may be empty as dangerous.
 */
enum class FixesState {
    EMPTY,
    MERGED,
    UNMERGED,
    UNKNOWN,
    ;

    companion object {
        fun parse(field: String?): FixesState = when (field) {
            "empty" -> EMPTY
            "merged" -> MERGED
            "unmerged" -> UNMERGED
            // Anything we do not understand reads as "cannot tell", never as one
            // of the three: this badge is the only thing between dropping an
            // empty branch and dropping unpushed work.
            else -> UNKNOWN
        }
    }
}

/** A `fixes` record of `git review list --porcelain`: one `review-fixes/` branch. */
data class FixesRecord(
    val name: String,
    val current: Boolean,
    val session: Boolean,
    val state: FixesState,
)

private fun toBool(field: String?): Boolean = field == "1"

private fun toInt(field: String?): Int = field?.toIntOrNull() ?: 0

private fun toOptionalInt(field: String?): Int? {
    if (field.isNullOrEmpty()) return null
    return field.toIntOrNull()
}

/**
 * Free-text field: everything after the `skip`-th tab (subject/author may
 * contain literal tabs).
 */
private fun restAfterTab(line: String, skip: Int): String? {
    var index = -1
    repeat(skip) {
        index = line.indexOf('\t', index + 1)
        if (index == -1) return null
    }
    return line.substring(index + 1)
}

/**
 * Tokenizes `git review status --porcelain`. Mode on the state record is read
 * first and decides arity of following lines.
 */
fun parsePorcelain(stdout: String): PorcelainResult {
    val lines = stdout.split(Regex("\r?\n")).filter { it.isNotEmpty() }
    if (lines.isEmpty()) {
        throw IllegalArgumentException("porcelain output has no state record")
    }

    var state: StateRecord? = null
    val entries = ArrayList<EntryRecord>()
    val files = ArrayList<EntryRecord>()
    var subjects: MutableMap<Int, String>? = null
    var authors: MutableMap<Int, String>? = null
    var base: String? = null
    var finish: StatusFinishRecord? = null
    var isReadonly: Boolean? = null
    var isKeysOnly: Boolean? = null
    var isDraft: Boolean? = null
    var draftPath: String? = null

    for (line in lines) {
        val fields = line.split("\t")
        when (fields[0]) {
            "state" -> {
                val mode = ReviewMode.parse(fields.getOrNull(4))
                    ?: throw IllegalArgumentException(
                        "porcelain state has invalid mode: ${fields.getOrNull(4)?.let { "\"$it\"" } ?: "(missing)"}",
                    )
                val walkthrough = WalkthroughStatus.parse(fields.getOrNull(5))
                    ?: WalkthroughStatus.NONE
                val record = if (mode == ReviewMode.STEP || mode == ReviewMode.WALK) {
                    val current: Any? = if (mode == ReviewMode.WALK) {
                        toPathRef(fields.getOrNull(9) ?: "")
                    } else {
                        fields.getOrNull(9)
                    }
                    StateRecord(
                        branch = fields.getOrNull(1) ?: "",
                        source = fields.getOrNull(2) ?: "",
                        tip = fields.getOrNull(3) ?: "",
                        mode = mode,
                        walkthrough = walkthrough,
                        position = toInt(fields.getOrNull(6)),
                        total = toInt(fields.getOrNull(7)),
                        recorded = toInt(fields.getOrNull(8)),
                        current = current,
                        essential = if (mode == ReviewMode.WALK) toBool(fields.getOrNull(10)) else null,
                    )
                } else {
                    StateRecord(
                        branch = fields.getOrNull(1) ?: "",
                        source = fields.getOrNull(2) ?: "",
                        tip = fields.getOrNull(3) ?: "",
                        mode = mode,
                        walkthrough = walkthrough,
                    )
                }
                state = record
            }
            "entry" -> {
                val st = state ?: throw IllegalArgumentException("entry record before state record")
                val position = toInt(fields.getOrNull(1))
                val rawId = fields.getOrNull(2) ?: ""
                val id: Any = if (st.mode == ReviewMode.STEP) rawId else toPathRef(rawId)
                val entry = when (st.mode) {
                    ReviewMode.WALK -> EntryRecord(
                        position = position,
                        id = id,
                        essential = toBool(fields.getOrNull(3)),
                        annotated = toBool(fields.getOrNull(4)),
                    )
                    ReviewMode.STEP -> EntryRecord(
                        position = position,
                        id = id,
                        banked = toBool(fields.getOrNull(3)),
                    )
                    ReviewMode.WHOLE -> EntryRecord(position = position, id = id)
                }
                entries.add(entry)
            }
            // Step: files of the current commit only (path as PathRef, like whole).
            "file" -> {
                state ?: throw IllegalArgumentException("file record before state record")
                val position = toInt(fields.getOrNull(1))
                val rawPath = fields.getOrNull(2)
                if (rawPath.isNullOrEmpty()) continue
                files.add(EntryRecord(position = position, id = toPathRef(rawPath)))
            }
            "subject", "author" -> {
                val position = toOptionalInt(fields.getOrNull(1))
                val text = restAfterTab(line, 2)
                if (position == null || text == null) continue
                if (fields[0] == "subject") {
                    subjects = (subjects ?: mutableMapOf()).also { it[position] = text }
                } else {
                    authors = (authors ?: mutableMapOf()).also { it[position] = text }
                }
            }
            "base" -> {
                val text = restAfterTab(line, 1)
                if (text != null) base = text
            }
            "finish" -> {
                if (fields.getOrNull(1) == "conflict") {
                    finish = StatusFinishRecord(onto = toBool(fields.getOrNull(2)))
                }
            }
            "readonly" -> isReadonly = true
            "keys" -> isKeysOnly = true
            "draft" -> {
                isDraft = true
                fields.getOrNull(1)?.takeIf { it.isNotEmpty() }?.let { draftPath = it }
            }
            else -> { /* unknown tag: ignore (FR-003) */ }
        }
    }

    val st = state ?: throw IllegalArgumentException("porcelain output has no state record")
    return PorcelainResult(
        state = st,
        entries = entries,
        files = files,
        finish = finish,
        readonly = isReadonly,
        keysOnly = isKeysOnly,
        draft = isDraft,
        draftPath = draftPath,
        subjects = subjects,
        authors = authors,
        base = base,
    )
}

/**
 * Source name of a review branch: strips `review-saved/` or `review/` prefix.
 */
fun sourceOf(branch: BranchRecord): String {
    for (prefix in listOf("review-saved/", "review/")) {
        if (branch.name.startsWith(prefix)) {
            return branch.name.removePrefix(prefix)
        }
    }
    return branch.name
}

/**
 * The `fixes` records of the same output, in a function of their own rather than
 * a second return value of [parseListPorcelain]: these are branches of *edits*,
 * not reviews -- there is nothing to resume or abort on them -- and every
 * existing consumer of the inventory keeps asking for exactly what it asked for.
 */
fun parseListFixes(stdout: String): List<FixesRecord> {
    val fixes = ArrayList<FixesRecord>()
    for (line in stdout.split(Regex("\r?\n"))) {
        if (line.isEmpty()) continue
        val fields = line.split("\t")
        if (fields[0] != "fixes") continue
        val name = fields.getOrNull(1)
        if (name.isNullOrEmpty()) continue
        fixes.add(
            FixesRecord(
                name = name,
                current = toBool(fields.getOrNull(2)),
                session = toBool(fields.getOrNull(3)),
                state = FixesState.parse(fields.getOrNull(4)),
            )
        )
    }
    return fixes
}

/** Tokenizes `git review list --porcelain`. Empty output is valid. */
fun parseListPorcelain(stdout: String): List<BranchRecord> {
    val branches = ArrayList<BranchRecord>()
    val finishByBranch = HashMap<String, BranchFinish>()

    for (line in stdout.split(Regex("\r?\n"))) {
        if (line.isEmpty()) continue
        val fields = line.split("\t")
        when (fields[0]) {
            "finish" -> {
                val branchName = fields.getOrNull(1)
                val state = fields.getOrNull(2)
                if (branchName != null && (state == "pending" || state == "conflict")) {
                    finishByBranch[branchName] = BranchFinish(state = state, onto = toBool(fields.getOrNull(3)))
                }
            }
            "branch" -> {
                val record = BranchRecord(
                    name = fields.getOrNull(1) ?: "",
                    saved = toBool(fields.getOrNull(2)),
                    current = toBool(fields.getOrNull(3)),
                    orphan = toBool(fields.getOrNull(4)),
                    mode = if (!toBool(fields.getOrNull(4))) {
                        ReviewMode.parse(fields.getOrNull(5) ?: "whole")
                    } else null,
                    position = if (!toBool(fields.getOrNull(4))) {
                        val p = toOptionalInt(fields.getOrNull(6))
                        val t = toOptionalInt(fields.getOrNull(7))
                        if (p != null && t != null) p else null
                    } else null,
                    total = if (!toBool(fields.getOrNull(4))) {
                        val p = toOptionalInt(fields.getOrNull(6))
                        val t = toOptionalInt(fields.getOrNull(7))
                        if (p != null && t != null) t else null
                    } else null,
                )
                branches.add(record)
            }
        }
    }

    return branches.map { b ->
        val f = finishByBranch[b.name]
        if (f != null) b.copy(finish = f) else b
    }
}
