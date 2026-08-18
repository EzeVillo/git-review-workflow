using System.IO;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace GitReview.VS.Vsix;

/// <summary>
/// Where the IDE says the workspace is — nothing more. Review state never comes from
/// Visual Studio's own git integration (SC-005): the roots found here are only used
/// as the working directory the CLI is invoked in.
/// </summary>
public static class VsWorkspace
{
    /// <summary>
    /// What the shell can say about the workspace right now: the git roots under it,
    /// and whether it named any directory at all to look under.
    ///
    /// Those are two different answers and only one of them is final. A folder the
    /// shell has named and that git does not call a repository is a real "no root".
    /// A shell that has not named anything yet is a workspace that is still arriving —
    /// which, with the tool window docked, is every Visual Studio start. Collapsed
    /// into one empty list the panel reported the second as the first, and every
    /// start began with "Need a single git repository root." until the retry below
    /// caught up.
    /// </summary>
    public readonly record struct WorkspaceProbe(IReadOnlyList<string> Roots, bool Located);

    public static WorkspaceProbe Probe(IServiceProvider serviceProvider)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        var candidates = new List<string>();
        var located = false;

        if (serviceProvider.GetService(typeof(SVsSolution)) is IVsSolution solution)
        {
            // Covers both a .sln and an opened folder; either gives a directory.
            solution.GetSolutionInfo(out var directory, out var file, out _);
            if (!string.IsNullOrWhiteSpace(directory)) candidates.Add(directory);
            if (!string.IsNullOrWhiteSpace(file)) candidates.Add(file);
            located = candidates.Count > 0;
        }

        if (candidates.Count == 0)
        {
            // A restored document is a guess at where the reviewer is, not the shell
            // saying where the workspace is -- so it feeds the roots but never sets
            // Located. Otherwise a file left open outside any repository, which is
            // exactly what a half-loaded IDE has on screen, would count as the final
            // word and cut the wait short.
            var active = ActiveDocumentPath(serviceProvider);
            if (active is not null) candidates.Add(active);
        }

        return new WorkspaceProbe(GitRepoRoots.FromPaths(candidates), located);
    }

    private static string? ActiveDocumentPath(IServiceProvider serviceProvider)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (serviceProvider.GetService(typeof(SVsUIShellOpenDocument)) is not IVsUIShellOpenDocument)
            return null;
        if (serviceProvider.GetService(typeof(SVsRunningDocumentTable)) is not IVsRunningDocumentTable rdt)
            return null;

        if (rdt.GetRunningDocumentsEnum(out var docs) != 0 || docs is null) return null;
        var cookies = new uint[1];
        while (docs.Next(1, cookies, out var fetched) == 0 && fetched == 1)
        {
            if (rdt.GetDocumentInfo(
                    cookies[0], out _, out _, out _, out var moniker,
                    out _, out _, out _) != 0)
                continue;
            if (!string.IsNullOrWhiteSpace(moniker) && File.Exists(moniker)) return moniker;
        }
        return null;
    }
}
