using GitReview.Domain;
using GitReview.Host;

namespace GitReview.VS.Diff;

/// <summary>
/// Inventory of changes for open-entry / open-all via git name-status (parity with JetBrains RangeChanges).
/// </summary>
public static class RangeChanges
{
    public static async Task<IReadOnlyList<CommitChange>> ForWholeRangeAsync(
        CliInvoker cli,
        string cwd,
        string baseRef,
        string tip,
        CancellationToken ct = default)
    {
        // git diff -z --name-status --no-renames base...tip
        var result = await cli.InvokeResolvedAsync(
            new ResolvedCommand("git", new[] { "diff", "-z", "--name-status", "--no-renames", $"{baseRef}...{tip}" }),
            cwd,
            network: false,
            timeoutMs: TimeoutClass.SupportGitTimeoutMs,
            cancellationToken: ct).ConfigureAwait(false);
        if (result.ExitCode != 0) return Array.Empty<CommitChange>();
        return NameStatus.ParseNameStatus(result.Stdout);
    }

    public static async Task<IReadOnlyList<CommitChange>> ForCommitAsync(
        CliInvoker cli,
        string cwd,
        string sha,
        CancellationToken ct = default)
    {
        var result = await cli.InvokeResolvedAsync(
            new ResolvedCommand("git", new[] { "diff-tree", "-z", "--name-status", "-r", "--no-commit-id", sha }),
            cwd,
            network: false,
            timeoutMs: TimeoutClass.SupportGitTimeoutMs,
            cancellationToken: ct).ConfigureAwait(false);
        if (result.ExitCode != 0) return Array.Empty<CommitChange>();
        return NameStatus.ParseNameStatus(result.Stdout);
    }
}
