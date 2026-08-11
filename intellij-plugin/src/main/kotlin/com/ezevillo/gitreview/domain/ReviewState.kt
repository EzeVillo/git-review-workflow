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
    val subjects: Map<Int, String>? = null,
    val authors: Map<Int, String>? = null,
    val base: String? = null,
    val finish: StatusFinishRecord? = null,
    val readonly: Boolean? = null,
    val keysOnly: Boolean? = null,
    val draft: Boolean? = null,
    val stderr: String? = null,
)
