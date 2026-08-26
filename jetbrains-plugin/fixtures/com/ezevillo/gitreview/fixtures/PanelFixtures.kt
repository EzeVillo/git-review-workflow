package com.ezevillo.gitreview.fixtures

import com.ezevillo.gitreview.domain.BranchFinish
import com.ezevillo.gitreview.domain.BranchRecord
import com.ezevillo.gitreview.domain.EffectiveConfig
import com.ezevillo.gitreview.domain.EntryRecord
import com.ezevillo.gitreview.domain.PanelInputs
import com.ezevillo.gitreview.domain.PanelModel
import com.ezevillo.gitreview.domain.PanelWhy
import com.ezevillo.gitreview.domain.PendingFinish
import com.ezevillo.gitreview.domain.ReviewMode
import com.ezevillo.gitreview.domain.ReviewState
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.StateRecord
import com.ezevillo.gitreview.domain.WalkthroughStatus
import com.ezevillo.gitreview.domain.WhyState
import com.ezevillo.gitreview.domain.buildPanelModel
import com.ezevillo.gitreview.domain.parseConfigPorcelain
import com.ezevillo.gitreview.domain.parseListFixes
import com.ezevillo.gitreview.domain.parseListPorcelain
import com.ezevillo.gitreview.domain.parsePorcelain
import com.ezevillo.gitreview.domain.toPathRef

/**
 * Shared [PanelModel] fixtures for tests and `runPanelPreview`.
 * Built from porcelain sample text via [parsePorcelain] / [buildPanelModel].
 */
object PanelFixtures {
    fun all(): List<Pair<String, PanelModel>> = listOf(
        "cli-missing" to cliMissing(),
        "cli-outdated" to cliOutdated(),
        "no-review setup" to noReviewSetup(),
        "no-review ready" to noReviewReady(),
        "no-review one draft" to noReviewOneDraft(),
        "no-review drafts" to noReviewDrafts(),
        "no-review spent draft" to noReviewSpentDraft(),
        "no-review fixes" to noReviewFixes(),
        "no-review guides" to noReviewGuides(),
        "no-review guide empty" to noReviewGuideEmpty(),
        "no-review walkthrough stale" to noReviewWalkthroughStale(),
        "no-review walkthrough absent" to noReviewWalkthroughAbsent(),
        "no-review walkthrough superseded" to noReviewWalkthroughSuperseded(),
        "no-review no walkthrough record" to noReviewNoWalkthroughRecord(),
        "finish-pending" to finishPending(),
        "out-of-range" to outOfRange(),
        "error" to error(),
        "review walk" to reviewWalk(),
        "review step" to reviewStep(),
        "review whole" to reviewWhole(),
        "finish-conflict" to finishConflict(),
        "review walk draft" to reviewWalkDraft(),
        "review walk busy" to reviewWalk(busy = true),
        "review walk empty cursor" to reviewWalkEmptyCursor(),
        "review whole empty" to reviewWholeEmpty(),
    )

    fun cliMissing(): PanelModel = buildPanelModel(
        ReviewState(situation = Situation.CLI_MISSING, stderr = "not found"),
        PanelInputs(busy = false),
    )

    fun cliOutdated(): PanelModel = buildPanelModel(
        ReviewState(situation = Situation.CLI_OUTDATED, stderr = "0.3.0"),
        PanelInputs(busy = false),
    )

    fun noReviewSetup(): PanelModel = buildPanelModel(
        ReviewState(
            situation = Situation.NO_REVIEW,
            config = EffectiveConfig(base = null, remote = "origin"),
        ),
        PanelInputs(busy = false),
    )

    fun noReviewReady(): PanelModel {
        val listPorcelain = """
            branch	review-saved/feature	1	0	0	walk	2	5
            branch	review/other	0	0	1	step
        """.trimIndent()
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                branches = parseListPorcelain(listPorcelain),
            ),
            PanelInputs(busy = false),
        )
    }

    /**
     * The four rows of "Edits you extracted" at once, with a live review above so
     * the two sections show together. The `current` row is the only one with no
     * control: the CLI skips it, so the panel does not offer it.
     */
    fun noReviewFixes(): PanelModel {
        val listPorcelain = """
            branch	review/feature/checkout	0	0	0	walk	3	9
            fixes	review-fixes/feature/checkout	0	1	unmerged
            fixes	review-fixes/fix/quoting	1	0	empty
            fixes	review-fixes/perf/index	0	0	merged
            fixes	review-fixes/docs/readme	0	0	unknown
        """.trimIndent()
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                branches = parseListPorcelain(listPorcelain),
                fixes = parseListFixes(listPorcelain),
            ),
            PanelInputs(busy = false),
        )
    }

    /**
     * One reading order started and not paused: the block on top, the usual
     * empty-state body whole underneath.
     */
    fun noReviewOneDraft(): PanelModel = buildPanelModel(
        ReviewState(
            situation = Situation.NO_REVIEW,
            config = EffectiveConfig(base = "main", remote = "origin"),
            drafts = parseConfigPorcelain(
                "draft	feature/pagos	/repo/.git/review-walkthrough/feature/pagos.md	0	5	remote	full",
            ).drafts,
        ),
        PanelInputs(busy = false),
    )

    /**
     * Two drafts with different progress, plus the inventory below. The second
     * row does NOT offer *Validate and start*: its instruction block was deleted
     * by hand, so the CLI reports `unknown` and the flags cannot be replicated.
     */
    fun noReviewDrafts(busy: Boolean = false): PanelModel {
        val cfg = """
            draft	feature/telemetry	/repo/.git/review-walkthrough/feature/telemetry.md	3	9	local	delta
            draft	feature/pagos	/repo/.git/review-walkthrough/feature/pagos.md	0	5	unknown	unknown
            draft	feature/legacy	/repo/.git/review-walkthrough/feature/legacy.md	1	1	remote	full
        """.trimIndent()
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                branches = parseListPorcelain("branch	review-saved/feature	1	0	0	walk	2	5"),
                drafts = parseConfigPorcelain(cfg).drafts,
            ),
            PanelInputs(busy = busy),
        )
    }

    /**
     * One reading order still ahead of its review and one whose review is over.
     * The second leaves the block on top for the collapsed section at the
     * bottom, and keeps only the two glyphs: the pair with labels is the flow of
     * writing the order and starting the review, and both already happened.
     */
    fun noReviewSpentDraft(): PanelModel {
        val cfg = """
            draft	feature/telemetry	/repo/.git/review-walkthrough/feature/telemetry.md	3	9	local	delta	fresh
            draft	feature/pagos	/repo/.git/review-walkthrough/feature/pagos.md	6	6	remote	full	reviewed
        """.trimIndent()
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                drafts = parseConfigPorcelain(cfg).drafts,
            ),
            PanelInputs(busy = false),
        )
    }

    /** El mismo estado con una mutación en curso: lo único que deshabilita la fila. */
    fun noReviewDraftsBusy(): PanelModel = noReviewDrafts(busy = true)

    /**
     * Both authoring guides, each in a different state: the shared one in force
     * (Open yes, Create no) and the reviewer's absent (Create yes, Open and
     * Discard no). It is the state that shows both rows are always drawn and
     * only the enabled changes.
     */
    fun noReviewGuides(): PanelModel {
        val cfg = """
            walkthrough	in-sync	/repo/.review/walkthrough.md	6	6	feature/checkout
            guide	team	/repo/.review/walkthrough-guide.md	in-force
            guide	own	/repo/.git/review-walkthrough-guide.md	absent
        """.trimIndent()
        val parsed = parseConfigPorcelain(cfg)
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                guides = parsed.guides,
                walkthrough = parsed.walkthrough,
            ),
            PanelInputs(busy = false),
        )
    }

    /**
     * The other half: the reviewer's created and still empty (Open and Discard
     * yes, Create no), and a repository that has no shared guide.
     */
    fun noReviewGuideEmpty(): PanelModel {
        val cfg = """
            walkthrough	unknown	/repo/.review/walkthrough.md	2	4	feature/checkout
            guide	team	/repo/.review/walkthrough-guide.md	absent
            guide	own	/repo/.git/review-walkthrough-guide.md	empty
        """.trimIndent()
        val parsed = parseConfigPorcelain(cfg)
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                guides = parsed.guides,
                walkthrough = parsed.walkthrough,
            ),
            PanelInputs(busy = false),
        )
    }

    /**
     * The one case where the CLI reports no walkthrough row at all: a malformed
     * record. The row is drawn anyway -- init and build hang off it -- in the
     * state the CLI itself calls "cannot be told".
     */
    fun noReviewNoWalkthroughRecord(): PanelModel {
        val cfg = """
            guide	team	/repo/.review/walkthrough-guide.md	absent
            guide	own	/repo/.git/review-walkthrough-guide.md	absent
        """.trimIndent()
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                guides = parseConfigPorcelain(cfg).guides,
            ),
            PanelInputs(busy = false),
        )
    }

    /**
     * The author's own walkthrough, stale and half-written: the PR was finished,
     * annotated, and then touched again, which is the situation the row exists
     * for. Two files entered the range and nobody has numbered them yet.
     */
    fun noReviewWalkthroughStale(): PanelModel {
        val cfg = """
            walkthrough	stale	/repo/.review/walkthrough.md	4	6	feature/checkout
            guide	team	/repo/.review/walkthrough-guide.md	absent
            guide	own	/repo/.git/review-walkthrough-guide.md	absent
        """.trimIndent()
        val parsed = parseConfigPorcelain(cfg)
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                guides = parsed.guides,
                walkthrough = parsed.walkthrough,
            ),
            PanelInputs(busy = false),
        )
    }

    /** No walkthrough at all: the row offers creating one, and nothing else. */
    fun noReviewWalkthroughAbsent(): PanelModel {
        val cfg = """
            walkthrough	absent	/repo/.review/walkthrough.md	0	0	feature/checkout
            guide	team	/repo/.review/walkthrough-guide.md	absent
            guide	own	/repo/.git/review-walkthrough-guide.md	absent
        """.trimIndent()
        val parsed = parseConfigPorcelain(cfg)
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                guides = parsed.guides,
                walkthrough = parsed.walkthrough,
            ),
            PanelInputs(busy = false),
        )
    }

    /**
     * The walkthrough of a PR that already merged: it travelled into the base
     * with the merge, so it is not this PR's reading order at all. Nothing about
     * it fell behind -- it belongs to a range that closed -- and the CLI starts
     * a new one on its own there.
     */
    fun noReviewWalkthroughSuperseded(): PanelModel {
        val cfg = """
            walkthrough	superseded	/repo/.review/walkthrough.md	3	3	feature/login
            guide	team	/repo/.review/walkthrough-guide.md	absent
            guide	own	/repo/.git/review-walkthrough-guide.md	absent
        """.trimIndent()
        val parsed = parseConfigPorcelain(cfg)
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                guides = parsed.guides,
                walkthrough = parsed.walkthrough,
            ),
            PanelInputs(busy = false),
        )
    }

    /** Configured, with nothing in the repository yet: the bare empty state. */
    fun noReviewEmpty(): PanelModel = buildPanelModel(
        ReviewState(
            situation = Situation.NO_REVIEW,
            config = EffectiveConfig(base = "main", remote = "origin"),
        ),
        PanelInputs(busy = false),
    )

    fun finishPending(): PanelModel {
        val branches = listOf(
            BranchRecord(
                name = "review/feature",
                saved = false,
                current = true,
                orphan = false,
                finish = BranchFinish(state = "pending", onto = false),
            ),
        )
        return buildPanelModel(
            ReviewState(situation = Situation.FINISH_PENDING, branches = branches),
            PanelInputs(busy = false),
        ).let { m ->
            if (m.pendingFinish != null) m
            else m.copy(pendingFinish = PendingFinish(branch = "review/feature", onto = false))
        }
    }

    fun outOfRange(): PanelModel = buildPanelModel(
        ReviewState(situation = Situation.OUT_OF_RANGE, stderr = "base moved"),
        PanelInputs(busy = false),
    )

    fun error(): PanelModel = buildPanelModel(
        ReviewState(
            situation = Situation.ERROR,
            stderr = "Open a single-folder workspace that is a git repository. git review uses one root (like the CLI cwd); multi-root is not supported.",
        ),
        PanelInputs(busy = false),
    )

    fun reviewWalk(
        busy: Boolean = false,
        why: PanelWhy = PanelWhy(WhyState.PRESENT, "Because it matters."),
        atFirst: Boolean = true,
        atLast: Boolean = false,
        position: Int = 1,
    ): PanelModel {
        val walkPorcelain = """
            state	review/feature	feature	deadbeefcafebabe	walk	applied	$position	3	3	"src/a.kt"	1
            entry	1	src/a.kt	1	1
            entry	2	src/b.kt	0	1
            entry	3	src/c.kt	0	0
        """.trimIndent()
        val walkParsed = parsePorcelain(walkPorcelain)
        val walkState = ReviewState(
            situation = Situation.REVIEW,
            state = walkParsed.state,
            entries = walkParsed.entries,
        )
        val model = buildPanelModel(walkState, PanelInputs(busy = busy, why = why))
        return model.copy(atFirst = atFirst, atLast = atLast || position >= (model.total ?: 0))
    }

    /**
     * 011: la misma review walk, leída sobre el borrador del revisor. El
     * registro `draft` viaja por el porcelain como cualquier otro, así que el
     * badge sale del mismo camino que en la extensión.
     */
    fun reviewWalkDraft(): PanelModel {
        val porcelain = """
            state	review/feature	feature	deadbeefcafebabe	walk	applied	1	3	3	"src/a.kt"	0
            entry	1	src/a.kt	0	1
            entry	2	src/b.kt	0	1
            entry	3	src/c.kt	0	0
            draft
        """.trimIndent()
        val parsed = parsePorcelain(porcelain)
        val state = ReviewState(
            situation = Situation.REVIEW,
            state = parsed.state,
            entries = parsed.entries,
            draft = parsed.draft,
        )
        val model = buildPanelModel(
            state,
            PanelInputs(busy = false, why = PanelWhy(WhyState.PRESENT, "Because I read it first.")),
        )
        return model.copy(atFirst = true, atLast = false)
    }

    fun reviewWalkEmptyCursor(): PanelModel {
        val m = reviewWalk(position = 1)
        return m.copy(current = null, position = 99, total = 3)
    }

    fun reviewStep(
        busy: Boolean = false,
        position: Int = 2,
        withFiles: Boolean = true,
    ): PanelModel {
        val stepFiles = if (withFiles) {
            listOf(
                EntryRecord(1, toPathRef("src/a.kt")),
                EntryRecord(2, toPathRef("src/b.kt")),
            )
        } else {
            emptyList()
        }
        return buildPanelModel(
            ReviewState(
                situation = Situation.REVIEW,
                state = StateRecord(
                    "review/f", "f", "tipsha01", ReviewMode.STEP, WalkthroughStatus.NONE,
                    position = position, total = 4, recorded = 4, current = "abc1234",
                ),
                entries = listOf(
                    EntryRecord(1, "aaa1111", banked = false),
                    EntryRecord(2, "abc1234", banked = true),
                    EntryRecord(3, "ccc3333", banked = false),
                    EntryRecord(4, "ddd4444", banked = false),
                ),
                files = stepFiles,
                subjects = mapOf(2 to "Fix the thing"),
                authors = mapOf(2 to "Ada"),
            ),
            PanelInputs(
                busy = busy,
                lastOpened = if (withFiles) "src/a.kt" else null,
            ),
        )
    }

    fun reviewWhole(fileCount: Int = 2): PanelModel {
        val entries = (1..fileCount).map { i ->
            EntryRecord(i, toPathRef("file$i.kt"))
        }
        return buildPanelModel(
            ReviewState(
                situation = Situation.REVIEW,
                state = StateRecord(
                    "review/f", "f", "tipsha01", ReviewMode.WHOLE, WalkthroughStatus.NONE,
                ),
                entries = entries,
                base = "main",
            ),
            PanelInputs(
                busy = false,
                lastOpened = entries.firstOrNull()?.let {
                    when (val id = it.id) {
                        is com.ezevillo.gitreview.domain.PathRef -> id.display
                        else -> id.toString()
                    }
                },
            ),
        )
    }

    fun reviewWholeEmpty(): PanelModel = buildPanelModel(
        ReviewState(
            situation = Situation.REVIEW,
            state = StateRecord(
                "review/f", "f", "tipsha01", ReviewMode.WHOLE, WalkthroughStatus.NONE,
            ),
            entries = emptyList(),
            base = "main",
        ),
        PanelInputs(busy = false),
    )

    fun finishConflict(): PanelModel = buildPanelModel(
        ReviewState(
            situation = Situation.FINISH_CONFLICT,
            state = StateRecord(
                "review/f", "f", "tipsha01", ReviewMode.WALK, WalkthroughStatus.APPLIED,
                position = 1, total = 2, recorded = 2, current = toPathRef("a.kt"),
            ),
            entries = listOf(EntryRecord(1, toPathRef("a.kt"), essential = true, annotated = true)),
        ),
        PanelInputs(busy = false, why = PanelWhy(WhyState.PRESENT, "conflict entry")),
    )
}
