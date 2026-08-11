package com.ezevillo.gitreview.domain

/**
 * Allowlist ids and URLs for the panel Support section (`openSupport`).
 * Mirrors vscode-extension SUPPORT_URLS and contracts/client-product-surface.yaml
 * `support.star_url` / `support.bug_url`.
 */
object SupportLinks {
    const val STAR: String = "star"
    const val BUG: String = "bug"

    const val STAR_URL: String = "https://github.com/EzeVillo/git-review-workflow"
    const val BUG_URL: String =
        "https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml"

    private val urls: Map<String, String> = mapOf(
        STAR to STAR_URL,
        BUG to BUG_URL,
    )

    fun urlFor(linkId: String?): String? = linkId?.let { urls[it] }
}
