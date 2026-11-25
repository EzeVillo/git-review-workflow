package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.UserCopy
import com.intellij.ide.impl.OpenProjectTask
import com.intellij.ide.impl.ProjectUtil
import com.intellij.openapi.project.Project
import java.nio.file.Path

fun openReviewCheckout(project: Project, path: String) {
    val opened = ProjectUtil.openOrImport(Path.of(path), OpenProjectTask.build().withForceOpenInNewFrame(true))
    if (opened == null) UiMessages.info(project, UserCopy.reviewCheckoutAvailable(path))
}
