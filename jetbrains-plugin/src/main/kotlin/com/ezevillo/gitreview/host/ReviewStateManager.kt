package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.CLI_PROBE_RETRIES
import com.ezevillo.gitreview.domain.CLI_PROBE_RETRY_DELAY_MS
import com.ezevillo.gitreview.domain.CliVerdict
import com.ezevillo.gitreview.domain.ReviewState
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.isOutdated
import com.ezevillo.gitreview.domain.parseConfigPorcelain
import com.ezevillo.gitreview.domain.parseListFixes
import com.ezevillo.gitreview.domain.parseListPorcelain
import com.ezevillo.gitreview.domain.parsePorcelain
import com.ezevillo.gitreview.domain.situationFor
import com.ezevillo.gitreview.domain.versionVerdict
import java.util.concurrent.atomic.AtomicLong

/**
 * Coalesced refresh of review state from CLI porcelain. No UI dependency.
 */
class ReviewStateManager(
    private val invoker: CliRunner,
    private val gitReviewPath: () -> String?,
) {
    private val generation = AtomicLong(0)
    @Volatile
    var current: ReviewState = ReviewState(situation = Situation.ERROR, stderr = "not refreshed yet")
        private set

    private var versionCheckedGeneration: Long = -1

    fun invalidateVersion() {
        versionCheckedGeneration = -1
    }

    /**
     * Full refresh. When [cwd] is null → multi-root / no-repo error situation.
     */
    fun refresh(cwd: String?): ReviewState {
        val gen = generation.incrementAndGet()
        if (cwd == null) {
            val state = ReviewState(
                situation = Situation.ERROR,
                stderr = MULTI_ROOT_ERROR,
            )
            if (gen == generation.get()) current = state
            return state
        }

        if (versionCheckedGeneration != gen || current.situation == Situation.CLI_MISSING) {
            // Declaring the CLI missing takes EVIDENCE of absence, not any
            // failure at all: the first invocation of a startup is the one most
            // likely to go wrong for reasons that are not the CLI, and that is
            // where the install screen landed on top of an installed CLI. With
            // no evidence the probe is retried and the panel keeps waiting --
            // it has published nothing yet -- instead of answering.
            var ver = invoker.invoke("--version", emptyList(), cwd)
            var verdict = versionVerdict(ver.stderr, ver.exitCode, ver.errorCode, ver.timedOut)
            var attempt = 0
            while (verdict == CliVerdict.UNKNOWN && attempt < CLI_PROBE_RETRIES) {
                attempt++
                Thread.sleep(CLI_PROBE_RETRY_DELAY_MS)
                ver = invoker.invoke("--version", emptyList(), cwd)
                verdict = versionVerdict(ver.stderr, ver.exitCode, ver.errorCode, ver.timedOut)
            }
            if (verdict != CliVerdict.OK) {
                // A CLI that takes too long is the opposite of a CLI that is not
                // there, and offering "install it with npm" there sends the
                // reviewer to install what is already installed.
                val state = if (ver.timedOut) {
                    ReviewState(
                        situation = Situation.ERROR,
                        stderr = VERSION_TIMEOUT,
                    )
                } else {
                    ReviewState(
                        situation = Situation.CLI_MISSING,
                        stderr = ver.stderr.ifBlank { "CLI not found" },
                    )
                }
                if (gen == generation.get()) {
                    current = state
                    versionCheckedGeneration = gen
                }
                return state
            }
            // No version line means nothing to compare: the CLI answered, and
            // the status that follows judges better than isOutdated(""), which
            // returns true.
            val version = ver.stdout.trim()
            if (version.isNotEmpty() && isOutdated(version)) {
                val state = ReviewState(
                    situation = Situation.CLI_OUTDATED,
                    stderr = "installed version: $version",
                )
                if (gen == generation.get()) {
                    current = state
                    versionCheckedGeneration = gen
                }
                return state
            }
            versionCheckedGeneration = gen
        }

        val status = invoker.invoke("status", listOf("--porcelain"), cwd)
        if (status.timedOut) {
            val state = ReviewState(
                situation = Situation.ERROR,
                stderr = "status --porcelain timed out",
            )
            if (gen == generation.get()) current = state
            return state
        }

        var branches = emptyList<com.ezevillo.gitreview.domain.BranchRecord>()
        var fixes = emptyList<com.ezevillo.gitreview.domain.FixesRecord>()
        var config: com.ezevillo.gitreview.domain.EffectiveConfig? = null
        var candidates: List<com.ezevillo.gitreview.domain.CandidateBranch>? = null
        var remotes: List<com.ezevillo.gitreview.domain.CandidateRemote>? = null
        var drafts: List<com.ezevillo.gitreview.domain.DraftRecord>? = null
        var guides: List<com.ezevillo.gitreview.domain.GuideRecord>? = null
        var walkthrough: com.ezevillo.gitreview.domain.WalkthroughRecord? = null

        val hasFinishConflict = if (status.exitCode == 0) {
            try {
                parsePorcelain(status.stdout).finish != null
            } catch (_: Exception) {
                false
            }
        } else false

        if (status.exitCode == 2) {
            val list = invoker.invoke("list", listOf("--porcelain"), cwd)
            if (list.exitCode == 0 && !list.timedOut) {
                try {
                    // One invocation, two readings: the fixes branches travel in
                    // the same output as the inventory, so the footer section
                    // costs no extra process per refresh.
                    branches = parseListPorcelain(list.stdout)
                    fixes = parseListFixes(list.stdout)
                } catch (_: Exception) {
                    branches = emptyList()
                    fixes = emptyList()
                }
            }
            val cfg = invoker.invoke("config", listOf("--porcelain"), cwd)
            if (cfg.exitCode == 0 && !cfg.timedOut) {
                try {
                    val parsed = parseConfigPorcelain(cfg.stdout)
                    config = parsed.config
                    candidates = parsed.candidates
                    remotes = parsed.remotes
                    drafts = parsed.drafts
                    guides = parsed.guides
                    walkthrough = parsed.walkthrough
                } catch (_: Exception) {
                    // leave null
                }
            }
        }

        val hasFinishPending = branches.any { it.finish?.state == "pending" }
        val situation = situationFor(status.exitCode, hasFinishConflict, hasFinishPending)

        val state = when (situation) {
            Situation.REVIEW, Situation.FINISH_CONFLICT -> {
                try {
                    val porcelain = parsePorcelain(status.stdout)
                    ReviewState(
                        situation = situation,
                        state = porcelain.state,
                        entries = porcelain.entries,
                        files = porcelain.files,
                        branches = emptyList(),
                        subjects = porcelain.subjects,
                        authors = porcelain.authors,
                        base = porcelain.base,
                        finish = porcelain.finish,
                        readonly = porcelain.readonly,
                        keysOnly = porcelain.keysOnly,
                        draft = porcelain.draft,
                        draftPath = porcelain.draftPath,
                    )
                } catch (e: Exception) {
                    ReviewState(
                        situation = Situation.ERROR,
                        stderr = e.message ?: "failed to parse status porcelain",
                    )
                }
            }
            Situation.NO_REVIEW, Situation.FINISH_PENDING -> ReviewState(
                situation = situation,
                branches = branches,
                fixes = fixes,
                config = config,
                candidates = candidates,
                remotes = remotes,
                drafts = drafts,
                guides = guides,
                walkthrough = walkthrough,
            )
            Situation.OUT_OF_RANGE -> ReviewState(
                situation = situation,
                stderr = status.stderr,
            )
            else -> ReviewState(
                situation = situation,
                stderr = status.stderr.ifBlank { "status failed (exit ${status.exitCode})" },
            )
        }

        if (gen == generation.get()) current = state
        return state
    }

    companion object {
        /**
         * A version probe that ran out of time: the CLI is there and slow, not
         * absent, so what the panel says is where to look.
         */
        const val VERSION_TIMEOUT: String =
            "`git review --version` did not finish in time and was stopped. " +
                "Run it in a terminal to see how long it takes. " +
                "See the git review log in Help > Show Log."

        const val MULTI_ROOT_ERROR: String =
            "Open a single-folder workspace that is a git repository. git review uses " +
                "one root (like the CLI cwd); multi-root is not supported."
    }
}
