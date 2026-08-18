using System.Diagnostics;
using System.IO;
using System.Text;
using GitReview.Host;

namespace GitReview.VS;

/// <summary>
/// Discover git repository roots under a solution / folder workspace.
/// Only roots — never read review state from the IDE VCS model (SC-005).
/// </summary>
public static class GitRepoRoots
{
    public static IReadOnlyList<string> FromPaths(IEnumerable<string> candidatePaths)
    {
        var roots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in candidatePaths)
        {
            if (string.IsNullOrWhiteSpace(path)) continue;
            var dir = File.Exists(path) ? Path.GetDirectoryName(path) : path;
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) continue;
            var root = ResolveGitRoot(dir);
            if (root is not null) roots.Add(root);
        }
        return roots.OrderBy(r => r, StringComparer.OrdinalIgnoreCase).ToList();
    }

    public static string? ResolveGitRoot(string startDir)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                WorkingDirectory = startDir,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
            };
            ProcessCompat.AddArgs(psi, "rev-parse", "--show-toplevel");
            using var p = Process.Start(psi);
            if (p is null) return null;
            var output = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit(10_000);
            if (p.ExitCode != 0 || string.IsNullOrEmpty(output)) return null;
            return Path.GetFullPath(output);
        }
        catch
        {
            return null;
        }
    }
}
