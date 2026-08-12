package com.ezevillo.gitreview.domain

/** Keep in sync with contracts/client-product-surface.yaml. */
const val NPM_INSTALL_CMD: String = "npm install -g git-review-workflow"
const val NPM_UPDATE_CMD: String = "npm install -g git-review-workflow@latest"

enum class CliInstallKind {
    INSTALL, UPDATE,
}

fun npmCommandFor(kind: CliInstallKind): String =
    if (kind == CliInstallKind.UPDATE) NPM_UPDATE_CMD else NPM_INSTALL_CMD
