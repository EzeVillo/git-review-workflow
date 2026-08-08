package com.ezevillo.gitreview.domain

enum class StartFailureCategory {
    NETWORK,
    REPOSITORY,
}

private val NETWORK_MARKERS = listOf(
    "could not resolve host",
    "could not read from remote repository",
    "connection timed out",
    "connection refused",
    "unable to access",
    "could not read username",
    "could not read password",
    "authentication failed",
    "permission denied (publickey)",
    "terminal prompts disabled",
)

fun classifyStartFailure(stderr: String): StartFailureCategory {
    val text = stderr.lowercase()
    return if (NETWORK_MARKERS.any { text.contains(it) }) {
        StartFailureCategory.NETWORK
    } else {
        StartFailureCategory.REPOSITORY
    }
}

/**
 * Quote an argument for pasting into an integrated terminal.
 * @param platform "win32" for PowerShell-style, anything else POSIX.
 */
fun quoteForTerminal(value: String, platform: String = "linux"): String {
    if (platform == "win32") {
        if (Regex("""^[\w./\\-]+$""").matches(value) && !value.startsWith("-")) {
            return value
        }
        return "'${value.replace("'", "''")}'"
    }
    return if (Regex("""^[\w./][\w./-]*$""").matches(value)) {
        value
    } else {
        "\"${value.replace("\"", "\\\"")}\""
    }
}
