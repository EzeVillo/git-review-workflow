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
    private val stateGate = Any()
    @Volatile
    var current: ReviewState = ReviewState(situation = Situation.ERROR, stderr = "not refreshed yet")
        private set

    private var versionCheckedGeneration: Long = -1

    fun invalidateVersion() {
        versionCheckedGeneration = -1
    }

    private fun accept(gen: Long, state: ReviewState, onPrimary: ((ReviewState) -> Unit)? = null) {
        synchronized(stateGate) {
            if (gen != generation.get()) return
            current = state
            // Keep publication and its in-memory notification ordered. Otherwise
            // an older callback could launch prose after a newer primary report.
            onPrimary?.invoke(state)
        }
    }

    /**
     * Full refresh. When [cwd] is null → multi-root / no-repo error situation.
     */
    fun refresh(cwd: String?, onPrimary: ((ReviewState) -> Unit)? = null): ReviewState =
        read(cwd, includeComments = true, publish = true, onPrimary = onPrimary)

    /** The mutation guard needs current product state, not document inventories. */
    fun readForMutation(cwd: String?): ReviewState =
        read(cwd, includeComments = false, publish = false)

    private fun read(cwd: String?, includeComments: Boolean, publish: Boolean, onPrimary: ((ReviewState) -> Unit)? = null): ReviewState {
        val gen = generation.incrementAndGet()
        if (cwd == null) {
            val state = ReviewState(
                situation = Situation.ERROR,
                stderr = MULTI_ROOT_ERROR,
            )
            if (publish) accept(gen, state)
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
                if (publish && gen == generation.get()) {
                    accept(gen, state)
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
                if (publish && gen == generation.get()) {
                    accept(gen, state)
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
            if (publish) accept(gen, state)
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
                        comparison = porcelain.comparison,
                        finish = porcelain.finish,
                        readonly = porcelain.readonly,
                        keysOnly = porcelain.keysOnly,
                        draft = porcelain.draft,
                        draftPath = porcelain.draftPath,
                    )
                } catch (e: Exception) {
                    // Lo que dijo la CLI le gana a lo que dice el parser: una
                    // porcelain ilegible es mas seguido una CLI que ya se
                    // explico que un bug del tokenizador, y sobre lo primero el
                    // revisor puede hacer algo. Los otros dos clientes ya
                    // preferian el stderr; este publicaba el mensaje del parser
                    // y se comia la unica frase accionable.
                    ReviewState(
                        situation = Situation.ERROR,
                        stderr = status.stderr.trim().ifEmpty {
                            e.message ?: "failed to parse status porcelain"
                        },
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

        val complete = if (includeComments && (status.exitCode == 0 || status.exitCode == 2)) {
            if (publish && gen == generation.get()) {
                val primary = state.copy(comments = com.ezevillo.gitreview.domain.CommentsReport(loading = true))
                accept(gen, primary, onPrimary)
            }
            val report = invoker.invoke("comments", listOf("status", "--porcelain"), cwd)
            val parsed = com.ezevillo.gitreview.domain.parseComments(report.stdout)
            state.copy(comments = if (report.exitCode == 0) parsed else parsed.copy(rows = parsed.rows + com.ezevillo.gitreview.domain.CommentRow("comments-diagnostic", listOf("", "read", report.stderr))))
        } else state
        if (publish) accept(gen, complete)
        return complete
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
