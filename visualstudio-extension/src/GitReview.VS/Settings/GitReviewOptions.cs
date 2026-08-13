namespace GitReview.VS.Settings;

/// <summary>
/// User settings (mirrors JetBrains GitReviewSettings / vscode gitReview.*).
/// </summary>
public sealed class GitReviewOptions
{
    /// <summary>Optional path to the git-review dispatcher. Empty = use `git review`.</summary>
    public string? Path { get; set; }

    /// <summary>Default start source: remote | local | offline.</summary>
    public string DefaultSource { get; set; } = "remote";

    public static GitReviewOptions Current { get; set; } = new();
}
