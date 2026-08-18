using System.ComponentModel;
using System.Runtime.InteropServices;
using GitReview.VS.Settings;
using Microsoft.VisualStudio.Shell;

namespace GitReview.VS.Vsix;

/// <summary>
/// Tools > Options > git review > General. Same two settings as the VS Code
/// (gitReview.path / gitReview.defaultSource) and JetBrains clients; the values are
/// mirrored into <see cref="GitReviewOptions.Current"/>, which is what the host and
/// the panel actually read.
/// </summary>
[Guid("d5b1c0a7-4e93-4f28-9a61-7c3f8b2e5d40")]
public sealed class GitReviewOptionsPage : DialogPage
{
    [Category("git review")]
    [DisplayName("Path to git-review")]
    [Description(
        "Optional path to the git-review dispatcher (bin/git-review). " +
        "Leave empty to run `git review` from PATH.")]
    public string? Path { get; set; }

    [Category("git review")]
    [DisplayName("Default start source")]
    [Description("Which side a review starts from: remote, local or offline.")]
    public string DefaultSource { get; set; } = "remote";

    public override void LoadSettingsFromStorage()
    {
        base.LoadSettingsFromStorage();
        Publish();
    }

    protected override void OnApply(PageApplyEventArgs e)
    {
        base.OnApply(e);
        Publish();
    }

    private void Publish() =>
        GitReviewOptions.Current = new GitReviewOptions
        {
            Path = Path,
            DefaultSource = string.IsNullOrWhiteSpace(DefaultSource) ? "remote" : DefaultSource,
        };
}
