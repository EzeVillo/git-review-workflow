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

enum class OfferId {
    WALK, KEYS, STEP, WHOLE;

    val id: String
        get() = when (this) {
            WALK -> "walk"
            KEYS -> "keys"
            STEP -> "step"
            WHOLE -> "whole"
        }

    companion object {
        fun parse(raw: String?): OfferId? = when (raw) {
            "walk" -> WALK
            "keys" -> KEYS
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

data class ConfigPorcelainResult(
    val config: EffectiveConfig,
    val candidates: List<CandidateBranch>,
    val remotes: List<CandidateRemote>,
    val deltas: List<DeltaRecord>? = null,
    val offers: List<ReadingOffer>? = null,
)

private fun toBool(field: String?): Boolean = field == "1"

fun parseConfigPorcelain(stdout: String): ConfigPorcelainResult {
    var base: String? = null
    var remote: String? = null
    val candidates = ArrayList<CandidateBranch>()
    val remotes = ArrayList<CandidateRemote>()
    val deltas = ArrayList<DeltaRecord>()
    val offers = ArrayList<ReadingOffer>()

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
    )
}

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
