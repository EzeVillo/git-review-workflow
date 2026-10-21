package com.ezevillo.gitreview.diff

import com.intellij.diff.chains.SimpleDiffRequestChain
import com.intellij.diff.editor.ChainDiffVirtualFile
import com.intellij.diff.editor.DiffEditorTabFilesManager
import com.intellij.diff.requests.DiffRequest
import com.intellij.openapi.project.Project

/** Open in the current IDE even when requested from the modeless comments dialog. */
fun openEditorDiffs(project: Project, requests: List<DiffRequest>) {
    if (requests.isEmpty()) return
    val file = ChainDiffVirtualFile(SimpleDiffRequestChain(requests), requests.first().title.orEmpty())
    DiffEditorTabFilesManager.getInstance(project).showDiffFile(file, true, true)
}
