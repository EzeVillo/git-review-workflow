package com.ezevillo.gitreview.domain

/** Interval for background `--version` probe while panel shows cli-missing/outdated. */
const val CLI_PROBE_INTERVAL_MS: Long = 10_000

/** `true` when a background CLI version probe is useful. */
fun shouldProbeCli(situation: Situation, panelVisible: Boolean): Boolean =
    panelVisible && (situation == Situation.CLI_MISSING || situation == Situation.CLI_OUTDATED)
