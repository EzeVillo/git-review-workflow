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
