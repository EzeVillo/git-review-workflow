using System.IO;
using System.Text;
using System.Windows;
using GitReview.Domain;
using GitReview.VS.ToolWindows;
using GitReview.VS.Wizards;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace GitReview.VS.Vsix;

/// <summary>
/// The half of the action matrix only a real IDE can do: open a file, open a diff,
/// show the why, run the start wizard. Everything else — confirmations, staleness,
/// which CLI verb an action maps to — stays in <see cref="ActionDispatcher"/>, shared
/// with the standalone build.
/// </summary>
public sealed class VsHostActions
{
    private readonly IServiceProvider _serviceProvider;
    private readonly GitReviewPanelController _panel;
    private readonly Func<IReadOnlyList<string>> _roots;
    private readonly string _scratch;

    public VsHostActions(
        IServiceProvider serviceProvider,
        GitReviewPanelController panel,
        Func<IReadOnlyList<string>> roots)
    {
        _serviceProvider = serviceProvider;
        _panel = panel;
        _roots = roots;
        _scratch = Path.Combine(
            Path.GetTempPath(),
            "git-review-vs",
            System.Diagnostics.Process.GetCurrentProcess().Id.ToString());
    }

    public ActionDispatcher Attach() =>
        new(
            _panel,
            OpenFileAsync,
            OpenDiffAsync,
            OpenAllDiffsAsync,
            OpenTextAsync,
            RunStartWizardAsync,
            PreviewEditsAsync);

    private string? Cwd() => SoleTarget.PickSoleTarget(_roots());

    private string? FullPath(string display)
    {
        var cwd = Cwd();
        if (cwd is null) return null;
        return Path.GetFullPath(Path.Combine(cwd, display.Replace('/', Path.DirectorySeparatorChar)));
    }

    private async Task OpenFileAsync(string display)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var full = FullPath(display);
        if (full is null)
        {
            MessageBox.Show(UserCopy.NoSoleRoot, UserCopy.ProductTitle);
            return;
        }
        if (!File.Exists(full))
        {
            // Deleted by the pull request under review: there is no file to open.
            MessageBox.Show($"{display} is not in the working tree.", UserCopy.ProductTitle);
            return;
        }

        VsShellUtilities.OpenDocument(_serviceProvider, full);
    }

    private async Task OpenDiffAsync(string display, string? before, string? after)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var cwd = Cwd();
        var full = FullPath(display);
        if (cwd is null || full is null)
        {
            MessageBox.Show(UserCopy.NoSoleRoot, UserCopy.ProductTitle);
            return;
        }

        var right = File.Exists(full) ? full : await EmptyFileAsync(display).ConfigureAwait(true);
        var left = await BaseCopyAsync(cwd, display, File.Exists(full) ? full : null).ConfigureAwait(true);
        if (left is null) return;

        if (_serviceProvider.GetService(typeof(SVsDifferenceService)) is not IVsDifferenceService diff)
        {
            // No differencing service (shouldn't happen in a real VS): open the file.
            await OpenFileAsync(display).ConfigureAwait(true);
            return;
        }

        var name = Path.GetFileName(display);
        diff.OpenComparisonWindow2(
            left,
            right,
            $"{name} — review",
            display,
            "Base (HEAD)",
            "Working tree",
            display,
            null,
            (uint)__VSDIFFSERVICEOPTIONS.VSDIFFOPT_LeftFileIsTemporary);
    }

    private async Task OpenAllDiffsAsync(IReadOnlyList<(string Path, string? Before, string? After)> files)
    {
        foreach (var file in files)
            await OpenDiffAsync(file.Path, file.Before, file.After).ConfigureAwait(true);
    }

    private async Task OpenTextAsync(string text)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var path = Path.Combine(_scratch, "why.md");
        WriteScratch(path, text.EndsWith("\n", StringComparison.Ordinal) ? text : text + "\n");
        VsShellUtilities.OpenDocument(_serviceProvider, path);
    }

    private async Task RunStartWizardAsync()
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var cwd = Cwd();
        if (cwd is null)
        {
            MessageBox.Show(UserCopy.NoSoleRoot, UserCopy.ProductTitle);
            return;
        }

        var started = await StartWizard.RunAsync(
            _panel.Cli,
            _panel.Mutations,
            cwd,
            _panel.State.Current).ConfigureAwait(true);
        if (started) await _panel.RefreshAsync().ConfigureAwait(true);
    }

    /// <summary>
    /// `git review preview [--stat]` as a read-only document, the same as the other
    /// two clients show it. It reads the banked edits and mutates nothing, so it goes
    /// straight to the invoker rather than through the mutation lock.
    /// </summary>
    private async Task PreviewEditsAsync(bool stat)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var state = _panel.State.Current;
        if (!SituationIds.IsReviewReadable(state.Situation) || state.State is null)
        {
            MessageBox.Show(UserCopy.NoActivePreview, UserCopy.ProductTitle);
            return;
        }

        var cwd = Cwd();
        if (cwd is null)
        {
            MessageBox.Show(UserCopy.NoSoleRoot, UserCopy.ProductTitle);
            return;
        }

        var args = stat ? new[] { "--stat" } : Array.Empty<string>();
        var result = await _panel.Cli.InvokeAsync("preview", args, cwd).ConfigureAwait(true);
        if (result.ExitCode != 0)
        {
            MessageBox.Show(
                CliMessage.CliErrorText(result.Stderr, result.Stdout, UserCopy.PreviewFailed),
                UserCopy.ProductTitle,
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        // Warnings on success (skipped edits in step mode, say) are notes, not state.
        var note = result.Stderr.Trim();
        if (note.Length > 0) MessageBox.Show(CliMessage.FirstCliLine(note), UserCopy.ProductTitle);

        var body = result.Stdout.Length > 0 ? result.Stdout : UserCopy.PreviewEmpty + "\n";
        var path = Path.Combine(_scratch, stat ? "preview-stat.txt" : "preview.diff");
        WriteScratch(path, body);
        VsShellUtilities.OpenDocument(_serviceProvider, path);
    }

    /// <summary>
    /// The left side of a diff: the file as the base commit has it. In a review the
    /// pull request lives in the working tree as uncommitted changes and HEAD sits at
    /// the merge-base, so `git show HEAD:path` is exactly the "before".
    /// </summary>
    private async Task<string?> BaseCopyAsync(string cwd, string display, string? workingTreePath)
    {
        var gitPath = display.Replace('\\', '/');
        var result = await _panel.Cli.InvokeResolvedAsync(
            new ResolvedCommand("git", new[] { "show", $"HEAD:{gitPath}" }),
            cwd,
            network: false,
            timeoutMs: TimeoutClass.SupportGitTimeoutMs).ConfigureAwait(true);

        // Exit != 0 means the path is not in the base commit at all: the review adds
        // it, and an empty left side is the honest diff.
        var text = result.ExitCode == 0 ? result.Stdout : "";
        var path = Path.Combine(_scratch, "base", gitPath.Replace('/', Path.DirectorySeparatorChar));
        WriteScratch(path, MatchLineEndings(text, workingTreePath));
        return path;
    }

    private async Task<string> EmptyFileAsync(string display)
    {
        var path = Path.Combine(
            _scratch,
            "deleted",
            display.Replace('/', Path.DirectorySeparatorChar));
        WriteScratch(path, "");
        return await Task.FromResult(path).ConfigureAwait(true);
    }

    /// <summary>
    /// The CLI host reassembles captured output line by line, so it comes back with
    /// this platform's newlines. Rewrite them to whatever the checked-out file uses,
    /// or the diff would mark every line as changed.
    /// </summary>
    private static string MatchLineEndings(string text, string? workingTreePath)
    {
        var normalized = text.Replace("\r\n", "\n");
        var crlf = workingTreePath is not null && UsesCrlf(workingTreePath);
        return crlf ? normalized.Replace("\n", "\r\n") : normalized;
    }

    private static bool UsesCrlf(string path)
    {
        try
        {
            using var reader = new StreamReader(path, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            var buffer = new char[4096];
            var read = reader.Read(buffer, 0, buffer.Length);
            for (var i = 0; i < read; i++)
            {
                if (buffer[i] != '\n') continue;
                return i > 0 && buffer[i - 1] == '\r';
            }
        }
        catch
        {
            // Unreadable or binary: LF is the safer guess.
        }
        return false;
    }

    private static void WriteScratch(string path, string content)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        File.WriteAllText(path, content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }
}
