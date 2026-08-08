package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.host.GitReviewService
import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.project.Project
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
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

        project.messageBus.connect(content).subscribe(
            ToolWindowManagerListener.TOPIC,
            object : ToolWindowManagerListener {
                override fun stateChanged(toolWindowManager: com.intellij.openapi.wm.ToolWindowManager) {
                    service.setPanelVisible(toolWindow.isVisible)
                }
            },
        )
        // Content is built at create, but first refresh only when shown.
        if (toolWindow.isVisible) {
            service.setPanelVisible(true)
        }
    }
}
