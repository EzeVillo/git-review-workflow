package com.ezevillo.gitreview.domain

/** Interval for background `--version` probe while panel shows cli-missing/outdated. */
const val CLI_PROBE_INTERVAL_MS: Long = 10_000

/** `true` when a background CLI version probe is useful. */
fun shouldProbeCli(situation: Situation, panelVisible: Boolean): Boolean =
    panelVisible && (situation == Situation.CLI_MISSING || situation == Situation.CLI_OUTDATED)
/**
 * What one `git review --version` run found, which is three things and not two:
 * between "it is there and answers" and "it is not there" lives "could not
 * tell". Startup is where the third one shows up — the host is still coming up,
 * the disk is busy, the process is slow or dies without saying why — and
 * reading it as absence is what put the install-the-CLI screen on top of a CLI
 * that was installed.
 */
enum class CliVerdict { OK, MISSING, UNKNOWN }

/**
 * What a shell or a JVM says when the executable really is not there. Matched
 * lowercased and as a substring: the point is the evidence, not each host's
 * exact wording. `error=2` is how the JVM reports it on Windows
 * (`CreateProcess error=2`), which is the form this plugin sees.
 */
private val ABSENCE_MARKERS = listOf(
    "is not a git command",
    "not found",
    "no such file",
    "cannot find",
    "enoent",
    "error=2",
)

private fun namesAbsence(text: String): Boolean {
    val lower = text.lowercase()
    return ABSENCE_MARKERS.any { lower.contains(it) }
}

/**
 * Classifies that run. The only evidence of absence is a failure that NAMES it;
 * a timeout is the opposite of a missing CLI (a process that does not exist
 * does not take long not to exist), and any other exit code without that text
 * says nothing on its own. OK means the CLI answered, not that it said its
 * version -- stdout is not part of this at all: a build that prints the version
 * somewhere else carries on to the status instead of coming out of the panel as
 * an outdated CLI nobody ever read (`isOutdated("")` is true).
 */
fun versionVerdict(
    stderr: String,
    exitCode: Int?,
    errorCode: String? = null,
    timedOut: Boolean = false,
): CliVerdict {
    if (timedOut) return CliVerdict.UNKNOWN
    if (errorCode != null || exitCode != 0) {
        return if (namesAbsence("${errorCode.orEmpty()} $stderr")) CliVerdict.MISSING else CliVerdict.UNKNOWN
    }
    return CliVerdict.OK
}

/**
 * Retries of the probe on an UNKNOWN verdict, before publishing anything. The
 * panel stays on its waiting surface meanwhile: a slower startup costs less
 * than a screen that has to be taken back ten seconds later. Bounded on
 * purpose — an answer that never comes still has to end up as something.
 */
const val CLI_PROBE_RETRIES: Int = 2
const val CLI_PROBE_RETRY_DELAY_MS: Long = 400
