package com.ezevillo.gitreview.domain

data class EffectiveConfig(
    val base: String? = null,
    val remote: String,
)

data class CandidateBranch(
    val name: String,
    val origin: String, // "remote" | "local"
    val current: Boolean,
)

data class CandidateRemote(
    val name: String,
    val current: Boolean,
)

enum class DeltaOrigin {
    REMOTE, LOCAL;

    val id: String get() = when (this) {
        REMOTE -> "remote"
        LOCAL -> "local"
    }

    companion object {
        fun parse(raw: String?): DeltaOrigin? = when (raw) {
            "remote" -> REMOTE
            "local" -> LOCAL
            else -> null
        }
    }
}

data class DeltaRecord(
    val name: String,
    val tip: String,
    val origin: DeltaOrigin,
)

/**
 * 011: DRAFT / DRAFT_RESUME no son formas de lectura sino el camino para
 * conseguir una — el revisor se escribe el orden que el PR no trae. Viajan por
 * el mismo registro porque se eligen en el mismo paso del asistente, y son
 * mutuamente excluyentes entre sí.
 */
enum class OfferId {
    WALK, KEYS, DRAFT, DRAFT_RESUME, STEP, WHOLE;

    val id: String
        get() = when (this) {
            WALK -> "walk"
            KEYS -> "keys"
            DRAFT -> "draft"
            DRAFT_RESUME -> "draft-resume"
            STEP -> "step"
            WHOLE -> "whole"
        }

    companion object {
        fun parse(raw: String?): OfferId? = when (raw) {
            "walk" -> WALK
            "keys" -> KEYS
            "draft" -> DRAFT
            "draft-resume" -> DRAFT_RESUME
            "step" -> STEP
            "whole" -> WHOLE
            else -> null
        }
    }
}

enum class OfferRank {
    RECOMMENDED, AVAILABLE;

    val id: String
        get() = when (this) {
            RECOMMENDED -> "recommended"
            AVAILABLE -> "available"
        }

    companion object {
        fun parse(raw: String?): OfferRank? = when (raw) {
            "recommended" -> RECOMMENDED
            "available" -> AVAILABLE
            else -> null
        }
    }
}

data class ReadingOffer(
    val id: OfferId,
    val rank: OfferRank,
)

/**
 * With which origin and range a draft was generated, read back out of the
 * instruction block inside the file itself. `UNKNOWN` when that block was
 * deleted by hand, which is allowed: the flags cannot be replicated then, so
 * the row does not offer *Validate and start* rather than guessing them.
 */
enum class DraftSource {
    REMOTE,
    LOCAL,
    OFFLINE,
    UNKNOWN,
    ;

    companion object {
        fun parse(raw: String?): DraftSource = when (raw) {
            "remote" -> REMOTE
            "local" -> LOCAL
            "offline" -> OFFLINE
            else -> UNKNOWN
        }
    }
}

enum class DraftRange {
    FULL,
    DELTA,
    UNKNOWN,
    ;

    companion object {
        fun parse(raw: String?): DraftRange = when (raw) {
            "full" -> FULL
            "delta" -> DELTA
            else -> UNKNOWN
        }
    }
}

/**
 * A loose walkthrough draft: it exists in the gitdir's ACTIVE namespace, which
 * is to say the reviewer started it and has not paused its review.
 *
 * Nothing here is derived: every field comes straight from the CLI. [path] in
 * particular — the client opens it and never builds one.
 */
data class DraftRecord(
    val src: String,
    val path: String,
    val annotated: Int,
    val total: Int,
    val source: DraftSource,
    val range: DraftRange,
)

data class ConfigPorcelainResult(
    val config: EffectiveConfig,
    val candidates: List<CandidateBranch>,
    val remotes: List<CandidateRemote>,
    val deltas: List<DeltaRecord>? = null,
    val offers: List<ReadingOffer>? = null,
    val drafts: List<DraftRecord> = emptyList(),
)

private fun toBool(field: String?): Boolean = field == "1"

/**
 * A non-negative count, or null: a malformed field invalidates the record.
 *
 * Not a bare [String.toIntOrNull], which accepts "-3" and "+3". The CLI emits
 * neither, so a field of that shape is a record this client did not understand,
 * and the three clients have to agree on that -- otherwise the same porcelain
 * line draws a row in two of them and is dropped by the third. toIntOrNull is
 * still what rejects a count too large for an Int.
 */
private fun parseCount(raw: String?): Int? {
    if (raw.isNullOrEmpty()) return null
    if (raw.any { it < '0' || it > '9' }) return null
    return raw.toIntOrNull()
}

fun parseConfigPorcelain(stdout: String): ConfigPorcelainResult {
    var base: String? = null
    var remote: String? = null
    val candidates = ArrayList<CandidateBranch>()
    val remotes = ArrayList<CandidateRemote>()
    val deltas = ArrayList<DeltaRecord>()
    val offers = ArrayList<ReadingOffer>()
    val drafts = ArrayList<DraftRecord>()

    for (line in stdout.split(Regex("\r?\n"))) {
        if (line.isEmpty()) continue
        val fields = line.split("\t")
        when (fields[0]) {
            "config" -> {
                val key = fields.getOrNull(1)
                val value = fields.getOrNull(2) ?: continue
                when (key) {
                    "base" -> base = value
                    "remote" -> remote = value
                }
            }
            "remote-candidate" -> {
                val name = fields.getOrNull(1)
                if (name.isNullOrEmpty()) continue
                remotes.add(CandidateRemote(name = name, current = toBool(fields.getOrNull(2))))
            }
            "candidate" -> {
                val name = fields.getOrNull(1)
                val origin = fields.getOrNull(2)
                if (name == null || (origin != "remote" && origin != "local")) continue
                candidates.add(
                    CandidateBranch(name = name, origin = origin, current = toBool(fields.getOrNull(3))),
                )
            }
            "delta" -> {
                val name = fields.getOrNull(1)
                val tip = fields.getOrNull(2)
                val origin = DeltaOrigin.parse(fields.getOrNull(3))
                if (name != null && tip != null && origin != null) {
                    deltas.add(DeltaRecord(name = name, tip = tip, origin = origin))
                }
            }
            "draft" -> {
                val src = fields.getOrNull(1)
                val path = fields.getOrNull(2)
                val annotated = parseCount(fields.getOrNull(3))
                val total = parseCount(fields.getOrNull(4))
                // A malformed record is ignored whole, like any unknown one:
                // half a progress pair would be worse than none.
                if (!src.isNullOrEmpty() && !path.isNullOrEmpty() && annotated != null && total != null) {
                    drafts.add(
                        DraftRecord(
                            src = src,
                            path = path,
                            annotated = annotated,
                            total = total,
                            source = DraftSource.parse(fields.getOrNull(5)),
                            range = DraftRange.parse(fields.getOrNull(6)),
                        ),
                    )
                }
            }
            "offer" -> {
                val id = OfferId.parse(fields.getOrNull(1))
                val rank = OfferRank.parse(fields.getOrNull(2))
                if (id != null && rank != null) {
                    offers.add(ReadingOffer(id = id, rank = rank))
                }
            }
            else -> { /* ignore unknown */ }
        }
    }

    val config = EffectiveConfig(base = base, remote = remote ?: "origin")
    return ConfigPorcelainResult(
        config = config,
        candidates = candidates,
        remotes = remotes,
        deltas = deltas.takeIf { it.isNotEmpty() },
        offers = offers.takeIf { it.isNotEmpty() },
        drafts = drafts,
    )
}

/**
 * Branches for the start-review picker (parity with VS Code `pickBranch`).
 *
 * Porcelain may emit both a remote and a local row for the same name; origin
 * is chosen later as the wizard source step, so the picker collapses to one
 * entry per name. Prefer the row marked `current` when present. Current branch
 * sorts first (FR-011 / research.md Decision 9).
 */
fun branchPickerItems(candidates: List<CandidateBranch>): List<CandidateBranch> {
    val byName = LinkedHashMap<String, CandidateBranch>()
    for (c in candidates) {
        val prev = byName[c.name]
        if (prev == null || (c.current && !prev.current)) {
            byName[c.name] = c
        }
    }
    return byName.values.sortedWith(
        compareByDescending<CandidateBranch> { it.current }.thenBy { it.name },
    )
}

/** Label for the start / set-base branch list: name, with `(current)` when applicable. */
fun branchPickerLabel(candidate: CandidateBranch): String =
    if (candidate.current) "${candidate.name}  (current)" else candidate.name

/**
 * Delta marker usable for a start source: remote → remote row;
 * local and offline → local row.
 */
fun deltaForSource(
    deltas: List<DeltaRecord>?,
    source: String, // "remote" | "local" | "offline"
): DeltaRecord? {
    if (deltas.isNullOrEmpty()) return null
    val origin = if (source == "remote") DeltaOrigin.REMOTE else DeltaOrigin.LOCAL
    return deltas.find { it.origin == origin }
}
