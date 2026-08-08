package com.ezevillo.gitreview.ui.actions

import com.ezevillo.gitreview.host.GitReviewService
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.project.DumbAware

class RefreshAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        GitReviewService.getInstance(project).scheduleRefresh()
    }
}

class ShowCliLogAction : AnAction(), DumbAware {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val lines = com.ezevillo.gitreview.host.CliLogSink.snapshot()
        val text = if (lines.isEmpty()) "(no CLI invocations yet)" else lines.joinToString("\n")
        com.intellij.openapi.ui.Messages.showInfoMessage(project, text, "Git Review CLI Log")
    }
}
