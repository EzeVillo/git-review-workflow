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
    public static IReadOnlyList<string> GitRoots(IServiceProvider serviceProvider)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        var candidates = new List<string>();

        if (serviceProvider.GetService(typeof(SVsSolution)) is IVsSolution solution)
        {
            // Covers both a .sln and an opened folder; either gives a directory.
            solution.GetSolutionInfo(out var directory, out var file, out _);
            if (!string.IsNullOrWhiteSpace(directory)) candidates.Add(directory);
            if (!string.IsNullOrWhiteSpace(file)) candidates.Add(file);
        }

        if (candidates.Count == 0)
        {
            var active = ActiveDocumentPath(serviceProvider);
            if (active is not null) candidates.Add(active);
        }

        return GitRepoRoots.FromPaths(candidates);
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
