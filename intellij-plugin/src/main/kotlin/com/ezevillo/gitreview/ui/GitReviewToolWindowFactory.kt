package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.host.GitReviewService
import com.intellij.openapi.actionSystem.ActionGroup
import com.intellij.openapi.actionSystem.ActionManager
import com.intellij.openapi.actionSystem.DefaultActionGroup
import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.project.Project
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
import com.intellij.openapi.wm.ToolWindowManager
import com.intellij.openapi.wm.ex.ToolWindowManagerListener
import com.intellij.ui.content.ContentFactory

/**
 * Tool window factory. Does **not** invoke the CLI in [isApplicable] or before
 * the window is shown (SC-006 / FR-017).
 */
class GitReviewToolWindowFactory : ToolWindowFactory, DumbAware {
    override fun shouldBeAvailable(project: Project): Boolean = true

    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val service = GitReviewService.getInstance(project)
        val panel = ReviewPanel(project, service)
        val content = ContentFactory.getInstance().createContent(panel, "", false)
        toolWindow.contentManager.addContent(content)

        // Title-bar actions: Refresh / Finish / Save / Cancel / Preview edits.
        // Pass the group children (not the group itself) so each gets its own icon button.
        // Never call DefaultActionGroup.getChildren(null) — platform 2024.3+ logs a
        // throwable (use ActionManager or getChildActionsOrStubs instead).
        val actionManager = ActionManager.getInstance()
        when (val titleGroup = actionManager.getAction("GitReview.ToolWindowTitle")) {
            is DefaultActionGroup ->
                toolWindow.setTitleActions(titleGroup.getChildren(actionManager).toList())
            is ActionGroup ->
                toolWindow.setTitleActions(listOf(titleGroup))
        }

        project.messageBus.connect(content).subscribe(
            ToolWindowManagerListener.TOPIC,
            object : ToolWindowManagerListener {
                override fun stateChanged(toolWindowManager: ToolWindowManager) {
                    service.setPanelVisible(toolWindow.isVisible)
                }
            },
        )
        // The content is only built when the window is being shown, so this is
        // still "no CLI before the panel is on screen" (FR-017) — but it no
        // longer hangs on `isVisible`, which the platform may not have flipped
        // yet at create time. When it was false here and the state change had
        // already gone by, nothing ever asked for the first refresh and the
        // panel sat on its seed state until the reviewer hit Refresh.
        service.setPanelVisible(true)
    }
}
