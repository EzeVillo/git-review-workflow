namespace GitReview.Domain;

/// <summary>
/// Allowlist ids and URLs for the panel Support section (openSupport).
/// Mirrors vscode SUPPORT_URLS and contracts/client-product-surface.yaml.
/// </summary>
public static class SupportLinks
{
    public const string Star = "star";
    public const string Bug = "bug";

    public const string StarUrl = "https://github.com/EzeVillo/git-review-workflow";
    public const string BugUrl =
        "https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml";

    private static readonly Dictionary<string, string> Urls = new()
    {
        [Star] = StarUrl,
        [Bug] = BugUrl,
    };

    public static string? UrlFor(string? linkId) =>
        linkId is not null && Urls.TryGetValue(linkId, out var url) ? url : null;
}
