package com.ezevillo.gitreview.vcs

import com.ezevillo.gitreview.domain.pickSoleTarget
import com.intellij.openapi.project.Project
import git4idea.repo.GitRepository
import git4idea.repo.GitRepositoryManager

data class RepositoryTarget(
    val rootPath: String,
    val repository: GitRepository,
)

fun listGitRoots(project: Project): List<RepositoryTarget> {
    val manager = GitRepositoryManager.getInstance(project)
    return manager.repositories.mapNotNull { repo ->
        val path = repo.root.path
        if (path.isNullOrBlank()) null else RepositoryTarget(rootPath = path, repository = repo)
    }
}

fun pickSoleGitRoot(project: Project): RepositoryTarget? =
    pickSoleTarget(listGitRoots(project))

/**
 * Re-read Git4Idea's repository model after a CLI mutation. Repository.update()
 * publishes the change event consumed by IntelliJ's native branch widget and
 * must run off the EDT; MutationActions provides that background-thread boundary.
 */
fun refreshIdeRepository(project: Project) {
    pickSoleGitRoot(project)?.repository?.update()
}
