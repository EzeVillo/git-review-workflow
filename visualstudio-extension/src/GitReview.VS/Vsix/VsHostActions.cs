using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using GitReview.Domain;
using GitReview.VS.Settings;
using GitReview.VS.ToolWindows;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace GitReview.VS.Vsix;

/// <summary>
/// The half of the action matrix only a real IDE can do: open a file, open a comparison
/// window, show text as a document, flush an unsaved buffer. Everything else —
/// confirmations, pickers, staleness, which CLI verb an action maps to — stays in
/// <see cref="ActionDispatcher"/>, shared with the standalone build.
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
            new PanelHost
            {
                Cwd = Cwd,
                OpenEntryFile = OpenEntryFileAsync,
                OpenDiffs = OpenDiffsAsync,
                OpenText = OpenTextAsync,
                OpenPath = OpenPathAsync,
                SavePath = SavePathAsync,
                PreviewEdits = PreviewEditsAsync,
                DefaultSource = () => GitReviewOptions.Current.DefaultSource,
            });

    private string? Cwd() => SoleTarget.PickSoleTarget(_roots());

    private string? FullPath(string display)
    {
        var cwd = Cwd();
        if (cwd is null) return null;
        return Path.GetFullPath(Path.Combine(cwd, display.Replace('/', Path.DirectorySeparatorChar)));
    }

    private async Task OpenEntryFileAsync(string display)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var full = FullPath(display);
        if (full is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        if (!File.Exists(full))
        {
            // Deleted by the pull request under review: there is no file to open.
            GitReviewDialogs.Info($"{display} is not in the working tree.");
            return;
        }

        VsShellUtilities.OpenDocument(_serviceProvider, full);
    }

    /// <summary>
    /// Opens an absolute path (the walkthrough sidecar, the reviewer's draft). False when
    /// it could not be shown — the draft flow reports that rather than swallowing it, so
    /// the reviewer still learns where the file is.
    /// </summary>
    private async Task<bool> OpenPathAsync(string path)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        try
        {
            if (!File.Exists(path)) return false;
            VsShellUtilities.OpenDocument(_serviceProvider, path);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Saves one document if the editor is holding it unsaved — this one, never
    /// "save all": the wizard asked the reviewer to edit a single file.
    /// </summary>
    private async Task SavePathAsync(string path)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        if (_serviceProvider.GetService(typeof(SVsRunningDocumentTable)) is not IVsRunningDocumentTable rdt)
            return;
        var hr = rdt.FindAndLockDocument(
            (uint)_VSRDTFLAGS.RDT_NoLock,
            path,
            out _,
            out _,
            out var docData,
            out var cookie);
        // FindAndLockDocument AddRefs the doc data even with RDT_NoLock; not releasing it
        // is a document the editor can never close.
        if (docData != IntPtr.Zero) Marshal.Release(docData);
        if (ErrorHandler.Failed(hr) || cookie == 0) return;
        // The file is not open here at all when there is no cookie — nothing to flush,
        // and the CLI will read what is on disk, which is what the reviewer wrote.
        rdt.SaveDocuments(
            (uint)__VSRDTSAVEOPTIONS.RDTSAVEOPT_SaveIfDirty,
            null,
            (uint)VSConstants.VSITEMID.Nil,
            cookie);
    }

    /// <summary>
    /// One comparison window per file. Each side is resolved first: a blob at a ref
    /// becomes a scratch file, the working tree is used in place so the reviewer can edit
    /// inside the diff, and a side the change does not have at all becomes an empty pane.
    /// </summary>
    private async Task OpenDiffsAsync(IReadOnlyList<DiffRequest> requests)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var cwd = Cwd();
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        if (_serviceProvider.GetService(typeof(SVsDifferenceService)) is not IVsDifferenceService diff)
        {
            // No differencing service (shouldn't happen in a real VS): open the files.
            foreach (var request in requests)
                if (request.Right.Path is not null)
                    await OpenEntryFileAsync(request.Right.Path).ConfigureAwait(true);
            return;
        }

        foreach (var request in requests)
        {
            var workingTree = request.Left.Ref is null || request.Right.Ref is null;
            var left = await ResolveSideAsync(cwd, request.Left, "left", workingTree).ConfigureAwait(true);
            var right = await ResolveSideAsync(cwd, request.Right, "right", workingTree).ConfigureAwait(true);
            // Temporary is what keeps the shell from treating a scratch copy as a file the
            // reviewer opened: it does not offer to save it, and it cleans it up.
            uint options = 0;
            if (left.Temporary) options |= (uint)__VSDIFFSERVICEOPTIONS.VSDIFFOPT_LeftFileIsTemporary;
            if (right.Temporary) options |= (uint)__VSDIFFSERVICEOPTIONS.VSDIFFOPT_RightFileIsTemporary;
            var name = Path.GetFileName(request.Title);
            diff.OpenComparisonWindow2(
                left.Path,
                right.Path,
                $"{name} — review",
                request.Title,
                request.Left.Label,
                request.Right.Label,
                request.Title,
                null,
                options);
        }
    }

    private sealed record ResolvedSide(string Path, bool Temporary);

    /// <summary>
    /// A side as a path on disk. <c>Ref</c> null is the working-tree file itself (not a
    /// copy — editing inside the diff is the point of a review); a ref is read with
    /// <c>git show</c>; no path at all is an empty file.
    /// </summary>
    private async Task<ResolvedSide> ResolveSideAsync(
        string cwd,
        DiffSide side,
        string slot,
        bool againstWorkingTree)
    {
        if (side.Path is null)
            return new ResolvedSide(WriteScratch(Path.Combine(_scratch, slot, "empty"), ""), true);

        if (side.Ref is null)
        {
            var full = FullPath(side.Path);
            if (full is not null && File.Exists(full)) return new ResolvedSide(full, false);
            return new ResolvedSide(
                WriteScratch(ScratchFor("deleted", side.Path), ""),
                true);
        }

        var gitPath = side.Path.Replace('\\', '/');
        var result = await _panel.Cli.InvokeResolvedAsync(
            new ResolvedCommand("git", new[] { "show", $"{side.Ref}:{gitPath}" }),
            cwd,
            network: false,
            timeoutMs: TimeoutClass.SupportGitTimeoutMs).ConfigureAwait(true);

        // Exit != 0 means the path is not in that ref at all: an empty side is the
        // honest diff.
        var text = result.ExitCode == 0 ? result.Stdout : "";
        // Line endings are matched to the working-tree file only when the other side IS
        // the working tree; two blobs from git already agree with each other.
        var body = againstWorkingTree ? MatchLineEndings(text, FullPathIfExists(side.Path)) : text;
        var scratch = ScratchFor(SafeRefFolder(side.Ref), gitPath);
        return new ResolvedSide(WriteScratch(scratch, body), true);
    }

    private string? FullPathIfExists(string display)
    {
        var full = FullPath(display);
        return full is not null && File.Exists(full) ? full : null;
    }

    private string ScratchFor(string folder, string gitPath) => Path.Combine(
        _scratch,
        folder,
        gitPath.Replace('/', Path.DirectorySeparatorChar));

    /// <summary>
    /// A ref is not a folder name: <c>abc1234^</c> and <c>origin/main</c> both have to
    /// become one, and two different refs must not collapse into the same scratch file or
    /// a commit diff would show a file against itself.
    /// </summary>
    private static string SafeRefFolder(string reference)
    {
        var chars = reference.ToCharArray();
        for (var i = 0; i < chars.Length; i++)
            if (Path.GetInvalidFileNameChars().Contains(chars[i]))
                chars[i] = '_';
        return "ref-" + new string(chars);
    }

    private async Task OpenTextAsync(string text)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var path = Path.Combine(_scratch, "why.md");
        WriteScratch(path, text.EndsWith("\n", StringComparison.Ordinal) ? text : text + "\n");
        VsShellUtilities.OpenDocument(_serviceProvider, path);
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
            GitReviewDialogs.Info(UserCopy.NoActivePreview);
            return;
        }

        var cwd = Cwd();
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }

        var args = stat ? new[] { "--stat" } : Array.Empty<string>();
        var result = await _panel.Cli.InvokeAsync("preview", args, cwd).ConfigureAwait(true);
        if (result.ExitCode != 0)
        {
            GitReviewDialogs.CliError(result.Stderr, UserCopy.PreviewFailed, result.Stdout);
            return;
        }

        // Warnings on success (skipped edits in step mode, say) are notes, not state.
        var note = result.Stderr.Trim();
        if (note.Length > 0) GitReviewDialogs.Info(CliMessage.FirstCliLine(note));

        var body = result.Stdout.Length > 0 ? result.Stdout : UserCopy.PreviewEmpty + "\n";
        var path = Path.Combine(_scratch, stat ? "preview-stat.txt" : "preview.diff");
        WriteScratch(path, body);
        VsShellUtilities.OpenDocument(_serviceProvider, path);
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

    private static string WriteScratch(string path, string content)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        File.WriteAllText(path, content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return path;
    }
}
