package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.*
import com.intellij.openapi.project.Project

fun confirmCommentsDeletion(project: Project): Boolean = UiMessages.confirm(
    project, ControlId.DELETE_COMMENTS, CommentsCopy.deleteTitle, CommentsCopy.deleteDetail, CommentsCopy.delete,
)
