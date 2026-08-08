package com.ezevillo.gitreview.domain

/**
 * Single usable root, like CLI cwd: 0 → none; 1 → that; 2+ → none (no guessing).
 */
fun <T> pickSoleTarget(targets: List<T>): T? =
    if (targets.size == 1) targets[0] else null
