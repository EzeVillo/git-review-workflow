package com.ezevillo.gitreview.domain

/**
 * Minimum CLI version that ships the porcelain contract used by this plugin.
 * Keep in sync with `contracts/client-product-surface.yaml` (anti-drift CI).
 */
const val MIN_CLI_VERSION: String = "0.6.0"

private fun parseVersion(version: String): Triple<Int, Int, Int>? {
    val parts = version.trim().split(".")
    if (parts.size != 3) return null
    val nums = parts.map { it.toIntOrNull() }
    if (nums.any { it == null || it < 0 }) return null
    return Triple(nums[0]!!, nums[1]!!, nums[2]!!)
}

/**
 * Compares two `X.Y.Z` versions. Negative if `a < b`, positive if `a > b`,
 * zero if equal. `null` if either is not `X.Y.Z` with non-negative integers.
 */
fun compareVersions(a: String, b: String): Int? {
    val va = parseVersion(a) ?: return null
    val vb = parseVersion(b) ?: return null
    if (va.first != vb.first) return va.first - vb.first
    if (va.second != vb.second) return va.second - vb.second
    return va.third - vb.third
}

/** `true` if `version` is older than [minVersion] or has an invalid format. */
fun isOutdated(version: String, minVersion: String = MIN_CLI_VERSION): Boolean {
    val cmp = compareVersions(version, minVersion)
    return cmp == null || cmp < 0
}
