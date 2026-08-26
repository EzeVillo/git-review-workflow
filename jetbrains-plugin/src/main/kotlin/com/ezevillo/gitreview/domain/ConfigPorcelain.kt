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
 * 011: DRAFT / DRAFT_RESUME / DRAFT_UPDATE no son formas de lectura sino el
 * camino para conseguir una — el revisor se escribe el orden que el PR no trae.
 * Viajan por el mismo registro porque se eligen en el mismo paso del asistente,
 * y son mutuamente excluyentes entre sí.
 *
 * Cuál de las tres llega lo decide la CLI y no se deriva acá: DRAFT_UPDATE dice
 * que el borrador quedó desfasado del rango de hoy, que es una pregunta que sólo
 * contesta quien tiene los dos tips. El campo `state` del registro `draft` NO
 * sirve para eso — contesta otra ("¿ya se leyó este orden?"), así que una rama
 * que avanzó después de su review sigue diciendo `reviewed`.
 */
enum class OfferId {
    WALK, KEYS, DRAFT, DRAFT_RESUME, DRAFT_UPDATE, STEP, WHOLE;

    val id: String
        get() = when (this) {
            WALK -> "walk"
            KEYS -> "keys"
            DRAFT -> "draft"
            DRAFT_RESUME -> "draft-resume"
            DRAFT_UPDATE -> "draft-update"
            STEP -> "step"
            WHOLE -> "whole"
        }

    companion object {
        fun parse(raw: String?): OfferId? = when (raw) {
            "walk" -> WALK
            "keys" -> KEYS
            "draft" -> DRAFT
            "draft-resume" -> DRAFT_RESUME
            "draft-update" -> DRAFT_UPDATE
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
 * Whether the review a draft was written for is over (`REVIEWED`) or still
 * ahead of it (`FRESH`). The CLI decides it by comparing the tip the draft
 * itself was generated against with the marker of the last completed review of
 * that branch; nothing is derived here.
 *
 * The file outlives the review either way -- clean does not touch prose -- so
 * this is not "does it exist": it is where it is drawn and what is offered.
 *
 * Anything that is not exactly "reviewed" is FRESH, the missing field included:
 * a CLI older than this record does not emit it, and there the panel has to
 * behave as it behaved rather than hide rows over a datum nobody gave it.
 */
enum class DraftState {
    FRESH,
    REVIEWED,
    ;

    companion object {
        fun parse(raw: String?): DraftState = if (raw == "reviewed") REVIEWED else FRESH
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
    /** Whether its review is over. See [DraftState]. */
    val state: DraftState,
)

/** Which of the two authoring guides a `guide` record is about. */
enum class GuideKind {
    TEAM,
    OWN,
    ;

    companion object {
        fun parse(raw: String?): GuideKind? = when (raw) {
            "team" -> TEAM
            "own" -> OWN
            else -> null
        }
    }
}

/**
 * What state a guide is in. All three are decided by the CLI and none is
 * inferred here: `EMPTY` is not `ABSENT` even though both mean "no conventions
 * are being applied" -- with the file there what is offered is opening it, not
 * creating it, and discarding it is possible where discarding a missing file is
 * not.
 */
enum class GuideState {
    IN_FORCE,
    EMPTY,
    ABSENT,
    ;

    companion object {
        fun parse(raw: String?): GuideState? = when (raw) {
            "in-force" -> IN_FORCE
            "empty" -> EMPTY
            "absent" -> ABSENT
            else -> null
        }
    }
}

/**
 * An authoring guide: prose about the CONTENT of a walkthrough (which entries
 * deserve `> key`, how to write a why, what belongs in the heads-up).
 *
 * The plugin never reads a byte of it -- it opens it and nothing else, exactly
 * as with the reviewer's draft. And `path` comes straight from the CLI: it is
 * **opened, never rebuilt**.
 */
data class GuideRecord(
    val kind: GuideKind,
    /** Absolute, resolved by the CLI. On disk only when `state != ABSENT`. */
    val path: String,
    val state: GuideState,
)

/**
 * A `guide` record from its fields, or null when it is malformed -- ignored
 * whole, like any record: half a guide row would offer to create one that is
 * already there, or open one that is not.
 *
 * Shared because the record arrives by TWO verbs: `config --porcelain` outside a
 * review and `status --porcelain` inside one. One parser per tokenizer would be
 * the same rule written twice, and the second copy would learn about any new
 * field late.
 */
fun parseGuideRecord(fields: List<String>): GuideRecord? {
    val kind = GuideKind.parse(fields.getOrNull(1)) ?: return null
    val path = fields.getOrNull(2)
    if (path.isNullOrEmpty()) return null
    val state = GuideState.parse(fields.getOrNull(3)) ?: return null
    return GuideRecord(kind = kind, path = path, state = state)
}

/**
 * What state the author's own walkthrough is in against the branch they have
 * checked out. All four are decided by the CLI and none is inferred here -- in
 * particular `UNKNOWN`, which is NOT `STALE`: with no instruction block (deleting
 * it by hand is legal) the question has no answer, and giving the worse of the
 * two would send someone to redo a reading order that may be perfectly fine.
 *
 * `SUPERSEDED` is not `STALE` either: the file is the walkthrough of a PR already
 * merged into the base, which travelled in with the merge, so nothing about it
 * fell behind — it belongs to another range. What is offered there is starting
 * over, not reconciling.
 */
enum class WalkthroughState {
    IN_SYNC,
    STALE,
    SUPERSEDED,
    UNKNOWN,
    ABSENT,
    ;

    companion object {
        fun parse(raw: String?): WalkthroughState? = when (raw) {
            "in-sync" -> IN_SYNC
            "stale" -> STALE
            "superseded" -> SUPERSEDED
            "unknown" -> UNKNOWN
            "absent" -> ABSENT
            else -> null
        }
    }
}

/**
 * The committed walkthrough of the branch you are standing on, and whether it
 * still describes what the PR changes today.
 *
 * It exists because a walkthrough is written when the PR is finished and then
 * the PR keeps moving: review comments come back, three files change, and that
 * is exactly the moment nobody is thinking about the walkthrough. `STALE` is a
 * "worth looking at", never a verdict -- the verdict is `build`'s, which is what
 * the row's control runs.
 *
 * `path` comes straight from the CLI, like the draft's and the guides': it is
 * **opened, never rebuilt**.
 */
data class WalkthroughRecord(
    /** Absolute path of `.review/walkthrough.md`, whether or not the file exists. */
    val path: String,
    val state: WalkthroughState,
    /** Entries with a position AND a resolved why, plus the heads-up. */
    val annotated: Int,
    /** Everything `build` requires: one unit per entry plus the heads-up. */
    val total: Int,
    /**
     * The branch this walkthrough annotates -- `HEAD`'s, which is the range
     * `init` and `build` resolve. It is **what the row is called** in the panel.
     * Null with a detached `HEAD`, the one case where the CLI omits the field:
     * the file and both verbs still work there and the only thing without an
     * answer is the name.
     */
    val branch: String? = null,
)

/**
 * A `walkthrough` record from its fields, or null when it is malformed.
 *
 * The annotated/total pair falls back to 0/0 rather than dropping the whole row:
 * the state is what decides what the block offers, and losing it to an
 * unreadable counter would leave the author without the one surface that tells
 * them their reading order fell behind. An unrecognised state does drop the row
 * -- drawing an invented badge is worse than drawing no block.
 */
fun parseWalkthroughRecord(fields: List<String>): WalkthroughRecord? {
    val state = WalkthroughState.parse(fields.getOrNull(1)) ?: return null
    val path = fields.getOrNull(2)
    if (path.isNullOrEmpty()) return null
    return WalkthroughRecord(
        path = path,
        state = state,
        annotated = parseCount(fields.getOrNull(3)) ?: 0,
        total = parseCount(fields.getOrNull(4)) ?: 0,
        branch = fields.getOrNull(5)?.takeIf { it.isNotEmpty() },
    )
}

data class ConfigPorcelainResult(
    val config: EffectiveConfig,
    val candidates: List<CandidateBranch>,
    val remotes: List<CandidateRemote>,
    val deltas: List<DeltaRecord>? = null,
    val offers: List<ReadingOffer>? = null,
    val drafts: List<DraftRecord> = emptyList(),
    /**
     * Both authoring guides, ALWAYS both and in the CLI's order (team, own),
     * whether or not either file exists. Absence is reported rather than implied
     * by silence: without the row the panel could not offer to create the missing
     * one without rebuilding its path, which is what the reported-path rule
     * exists to prevent. Empty against a CLI that does not know the record.
     */
    val guides: List<GuideRecord> = emptyList(),
    /**
     * The author's walkthrough for the branch that is checked out. The CLI emits
     * the row present or absent -- same rule as the guides, for the same reason --
     * so null here means one thing only: a CLI older than the record. The panel
     * draws the block only when there is a row.
     */
    val walkthrough: WalkthroughRecord? = null,
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
    val guides = ArrayList<GuideRecord>()
    var walkthrough: WalkthroughRecord? = null

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
                            state = DraftState.parse(fields.getOrNull(7)),
                        ),
                    )
                }
            }
            "guide" -> parseGuideRecord(fields)?.let { guides.add(it) }
            // One row per invocation. If two arrived the first wins: a second
            // would be the CLI contradicting itself, and taking the last would
            // make the panel depend on emission order.
            "walkthrough" -> if (walkthrough == null) {
                walkthrough = parseWalkthroughRecord(fields)
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
        guides = guides,
        walkthrough = walkthrough,
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
