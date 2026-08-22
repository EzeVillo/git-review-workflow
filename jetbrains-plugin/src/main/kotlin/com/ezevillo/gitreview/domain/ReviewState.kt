package com.ezevillo.gitreview.domain

/**
 * In-memory aggregate after a refresh. Host populates this; domain only
 * holds the shape (data-model.md § ReviewState).
 */
data class ReviewState(
    val situation: Situation,
    val state: StateRecord? = null,
    val entries: List<EntryRecord> = emptyList(),
    /** Step: files of the current commit (`file` porcelain). Empty otherwise. */
    val files: List<EntryRecord> = emptyList(),
    val branches: List<BranchRecord> = emptyList(),
    val config: EffectiveConfig? = null,
    val candidates: List<CandidateBranch>? = null,
    val remotes: List<CandidateRemote>? = null,
    /**
     * 012: borradores de walkthrough sueltos del working tree, del mismo
     * reporte de `config --porcelain` que trae `config` — sin invocaciones
     * nuevas. `null` cuando ese reporte no llegó; vacío si llegó sin ninguno.
     */
    val drafts: List<DraftRecord>? = null,
    /**
     * Both authoring guides (`guide` record of `config --porcelain`), in the
     * CLI's order and always both. Null when that report did not arrive; empty
     * against a CLI that does not know the record.
     */
    val guides: List<GuideRecord>? = null,
    /**
     * The author's walkthrough for the branch that is checked out (`walkthrough`
     * record of `config --porcelain`), from the same report. Null when that
     * report did not arrive, and against a CLI older than the record -- which is
     * the same thing to the panel: no row, no block.
     */
    val walkthrough: WalkthroughRecord? = null,
    val subjects: Map<Int, String>? = null,
    val authors: Map<Int, String>? = null,
    val base: String? = null,
    val finish: StatusFinishRecord? = null,
    val readonly: Boolean? = null,
    val keysOnly: Boolean? = null,
    val draft: Boolean? = null,
    /** 012: ruta absoluta del borrador en vigor, reportada por la CLI. */
    val draftPath: String? = null,
    val stderr: String? = null,
)
