using System.Text.RegularExpressions;

namespace GitReview.Domain;

public sealed record ResolvedCommand(string Command, IReadOnlyList<string> Args);

public static class ResolveCommand
{
    private static readonly Regex WindowsNativeExecutable =
        new(@"\.(exe|cmd|bat)$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>
    /// Resolves executable + args for a git-review invocation
    /// (contracts/cli-invocation.md).
    /// </summary>
    /// <param name="platform">"win32" or other (POSIX).</param>
    public static ResolvedCommand Resolve(
        string verb,
        IReadOnlyList<string> args,
        string? gitReviewPath,
        string? platform = null)
    {
        platform ??= RuntimeInfo.IsWindows ? "win32" : "posix";
        if (string.IsNullOrWhiteSpace(gitReviewPath))
            return new ResolvedCommand("git", new[] { "review", verb }.Concat(args).ToList());
        if (platform == "win32" && !WindowsNativeExecutable.IsMatch(gitReviewPath))
            return new ResolvedCommand("sh", new[] { gitReviewPath, verb }.Concat(args).ToList());
        return new ResolvedCommand(gitReviewPath, new[] { verb }.Concat(args).ToList());
    }
}
