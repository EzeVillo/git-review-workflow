package com.ezevillo.gitreview.domain

data class ResolvedCommand(
    val command: String,
    val args: List<String>,
)

private val WINDOWS_NATIVE_EXECUTABLE = Regex("""\.(exe|cmd|bat)$""", RegexOption.IGNORE_CASE)

/**
 * Resolves executable + args for a git-review invocation
 * (contracts/cli-invocation.md § Forma de toda invocación).
 *
 * @param platform `"win32"` or other (POSIX).
 */
fun resolveCommand(
    verb: String,
    args: List<String>,
    gitReviewPath: String?,
    platform: String = System.getProperty("os.name").lowercase().let {
        if (it.contains("win")) "win32" else "posix"
    },
): ResolvedCommand {
    if (gitReviewPath.isNullOrBlank()) {
        return ResolvedCommand(command = "git", args = listOf("review", verb) + args)
    }
    if (platform == "win32" && !WINDOWS_NATIVE_EXECUTABLE.containsMatchIn(gitReviewPath)) {
        return ResolvedCommand(command = "sh", args = listOf(gitReviewPath, verb) + args)
    }
    return ResolvedCommand(command = gitReviewPath, args = listOf(verb) + args)
}
