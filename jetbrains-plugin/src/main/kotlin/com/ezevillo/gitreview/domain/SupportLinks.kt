package com.ezevillo.gitreview.domain

/**
 * Allowlist ids and URLs for the panel Support section (`openSupport`).
 * Mirrors vscode-extension SUPPORT_URLS and contracts/client-product-surface.yaml
 * `support` URLs.
 */
object SupportLinks {
    const val STAR: String = "star"
    const val BUG: String = "bug"
    const val SPONSOR: String = "sponsor"
    const val CONTACT: String = "contact"

    const val STAR_URL: String = "https://github.com/EzeVillo/git-review-workflow"
    const val BUG_URL: String =
        "https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml"
    const val SPONSOR_URL: String = "https://github.com/sponsors/EzeVillo"
    const val CONTACT_URL: String = "mailto:ezevillodev@gmail.com"

    private val urls: Map<String, String> = mapOf(
        STAR to STAR_URL,
        BUG to BUG_URL,
        SPONSOR to SPONSOR_URL,
        CONTACT to CONTACT_URL,
    )

    fun urlFor(linkId: String?): String? = linkId?.let { urls[it] }
}
