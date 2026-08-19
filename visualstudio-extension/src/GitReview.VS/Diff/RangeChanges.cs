using GitReview.Domain;
using GitReview.Host;

namespace GitReview.VS.Diff;

/// <summary>
/// Inventory of changes for open-entry / open-all via git name-status (parity with JetBrains RangeChanges).
/// <para>
/// Both readers answer <c>null</c> when git could not be read and an empty list when it was
/// read and touches nothing: they are different answers to the caller, which reports the
/// first as an error and the second as a fact about the review. Collapsing them into an
/// empty list makes a failed <c>diff HEAD</c> look like a file the reviewer already reverted.
/// </para>
/// </summary>
public static class RangeChanges
{
    /// <summary>
    /// The files a review's range touches. A review branch keeps HEAD at the merge-base
    /// with the pull request staged on top, so the range is exactly <c>diff HEAD</c> --
    /// plus whatever the reviewer has edited. <c>--no-renames</c> pins the behaviour
    /// instead of inheriting the user's <c>diff.renames</c>, so the same review does not
    /// look different on two machines. Same argv as VS Code's readRangeChanges and the
    /// JetBrains nameStatusHead.
    /// </summary>
    public static async Task<IReadOnlyList<CommitChange>?> ForRangeAsync(
        CliInvoker cli,
        string cwd,
        CancellationToken ct = default)
    {
        var result = await cli.InvokeResolvedAsync(
            new ResolvedCommand("git", new[] { "diff", "--name-status", "-z", "--no-renames", "HEAD" }),
            cwd,
            network: false,
            timeoutMs: TimeoutClass.SupportGitTimeoutMs,
            cancellationToken: ct).ConfigureAwait(false);
        if (result.ExitCode != 0) return null;
        return NameStatus.ParseNameStatus(result.Stdout);
    }

    /// <summary>
    /// The files one commit touches. <c>--root</c> is what makes the repository's first
    /// commit list its files rather than nothing -- without it a review whose range
    /// reaches the root commit answers "no changes" for a commit that added everything.
    /// <c>--no-commit-id</c> keeps the sha out of the -z stream, where the parser would
    /// read the status letter as a path.
    /// </summary>
    public static async Task<IReadOnlyList<CommitChange>?> ForCommitAsync(
        CliInvoker cli,
        string cwd,
        string sha,
        CancellationToken ct = default)
    {
        var result = await cli.InvokeResolvedAsync(
            new ResolvedCommand(
                "git",
                new[] { "diff-tree", "-r", "-z", "--no-commit-id", "--name-status", "--root", sha }),
            cwd,
            network: false,
            timeoutMs: TimeoutClass.SupportGitTimeoutMs,
            cancellationToken: ct).ConfigureAwait(false);
        if (result.ExitCode != 0) return null;
        return NameStatus.ParseNameStatus(result.Stdout);
    }
}
