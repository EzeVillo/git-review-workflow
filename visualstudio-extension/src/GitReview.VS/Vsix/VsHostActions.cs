using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using GitReview.Domain;
using GitReview.VS.Settings;
using GitReview.VS.ToolWindows;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.TextManager.Interop;

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
    private readonly Action _revealPanel;
    private readonly string _scratch;
    private readonly Dictionary<string,CommentCapture> _commentLocations = new(StringComparer.OrdinalIgnoreCase);

    public VsHostActions(
        IServiceProvider serviceProvider,
        GitReviewPanelController panel,
        Func<IReadOnlyList<string>> roots,
        Action revealPanel)
    {
        _serviceProvider = serviceProvider;
        _panel = panel;
        _roots = roots;
        _revealPanel = revealPanel;
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
                SaveCommentPath = SaveCommentPathAsync,
                HasUnsavedDocuments = HasUnsavedDocumentsAsync,
                CaptureComment = CaptureCommentAsync,
                OpenCommentBlobs = OpenCommentBlobsAsync,
                OpenCommentDelivery = OpenCommentDeliveryAsync,
                PreviewEdits = PreviewEditsAsync,
                DefaultSource = () => GitReviewOptions.Current.DefaultSource,
                Progress = ShowProgress,
                RevealPanel = _revealPanel,
            });

    /// <summary>
    /// A running mutation, in the shell's own status bar: the text plus the general
    /// activity animation, cleared when the returned handle is disposed. The status bar
    /// is where Visual Studio reports work that is not modal, which is what VS Code's
    /// progress notification and IntelliJ's background task are for the same actions.
    /// Every call is guarded: a shell that will not hand over its status bar must not
    /// take the finish down with it.
    /// </summary>
    private IDisposable ShowProgress(string text)
    {
        IVsStatusbar? bar;
        try
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            bar = _serviceProvider.GetService(typeof(SVsStatusbar)) as IVsStatusbar;
        }
        catch
        {
            bar = null;
        }
        if (bar is null) return new ProgressScope(null);

        try
        {
            bar.FreezeOutput(0);
            bar.SetText(text);
            object icon = (short)Constants.SBAI_General;
            bar.Animation(1, ref icon);
        }
        catch
        {
            return new ProgressScope(null);
        }
        return new ProgressScope(bar);
    }

    /// <summary>Ends one status-bar report. Disposing twice is a no-op.</summary>
    private sealed class ProgressScope : IDisposable
    {
        private IVsStatusbar? _bar;

        public ProgressScope(IVsStatusbar? bar) => _bar = bar;

        public void Dispose()
        {
            var bar = _bar;
            _bar = null;
            if (bar is null) return;
            try
            {
                ThreadHelper.ThrowIfNotOnUIThread();
                object icon = (short)Constants.SBAI_General;
                bar.Animation(0, ref icon);
                bar.FreezeOutput(0);
                bar.Clear();
            }
            catch
            {
                // The status bar is a report, not the operation: a shell that refuses
                // to clear it must not turn a finished mutation into an error dialog.
            }
        }
    }

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
    private async Task SavePathAsync(string path) => await SaveCommentPathAsync(path).ConfigureAwait(true);

    private async Task<bool?> HasUnsavedDocumentsAsync()
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        try
        {
            if (_serviceProvider.GetService(typeof(SVsRunningDocumentTable)) is not IVsRunningDocumentTable rdt ||
                ErrorHandler.Failed(rdt.GetRunningDocumentsEnum(out var documents)) || documents is null) return null;
            var cookies = new uint[1];
            while (true)
            {
                if (ErrorHandler.Failed(documents.Next(1,cookies,out var fetched))) return null;
                if (fetched == 0) return false;
                var hr = rdt.GetDocumentInfo(cookies[0],out _,out _,out _,out _,out _,out _,out var data);
                IVsPersistDocData? persisted = null;
                if (data != IntPtr.Zero)
                {
                    try { persisted = Marshal.GetObjectForIUnknown(data) as IVsPersistDocData; }
                    finally { Marshal.Release(data); }
                }
                if (ErrorHandler.Failed(hr) || persisted is null || ErrorHandler.Failed(persisted.IsDocDataDirty(out var dirty))) return null;
                if (dirty != 0) return true;
            }
        }
        catch (Exception) { return null; }
    }

    private async Task<bool> SaveCommentPathAsync(string path)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        if (_serviceProvider.GetService(typeof(SVsRunningDocumentTable)) is not IVsRunningDocumentTable rdt)
            return false;
        var hr = rdt.FindAndLockDocument(
            (uint)_VSRDTFLAGS.RDT_NoLock,
            path,
            out _,
            out _,
            out var docData,
            out var cookie);
        // FindAndLockDocument AddRefs the doc data even with RDT_NoLock; not releasing it
        // is a document the editor can never close.
        IVsPersistDocData? persisted = null;
        if (docData != IntPtr.Zero) {
            try { persisted = Marshal.GetObjectForIUnknown(docData) as IVsPersistDocData; }
            finally { Marshal.Release(docData); }
        }
        if (ErrorHandler.Failed(hr)) return false;
        if (cookie == 0) return true;
        // The file is not open here at all when there is no cookie — nothing to flush,
        // and the CLI will read what is on disk, which is what the reviewer wrote.
        var saved = rdt.SaveDocuments(
            (uint)__VSRDTSAVEOPTIONS.RDTSAVEOPT_SaveIfDirty,
            null,
            (uint)VSConstants.VSITEMID.Nil,
            cookie);
        if (ErrorHandler.Failed(saved) || persisted is null) return false;
        return ErrorHandler.Succeeded(persisted.IsDocDataDirty(out var dirty)) && dirty == 0;
    }

    private async Task<CommentCapture?> CaptureCommentAsync()
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        if (_serviceProvider.GetService(typeof(SVsTextManager)) is not IVsTextManager manager || ErrorHandler.Failed(manager.GetActiveView(0,null,out var view)) || view is null) return null;
        if (ErrorHandler.Failed(view.GetBuffer(out var buffer)) || buffer is not IPersistFileFormat file || ErrorHandler.Failed(file.GetCurFile(out var path,out _))) return null;
        if (ErrorHandler.Failed(view.GetSelection(out var firstLine,out var firstColumn,out var lastLine,out var lastColumn))) return null;
        var lines=Comments.SelectionCoordinates(firstLine,firstColumn,lastLine,lastColumn);
        var selected=firstLine!=lastLine || firstColumn!=lastColumn;
        var snippet="";
        if(selected)buffer.GetLineText(lines.First-1,lines.StartColumn-1,lines.Last-1,lines.EndColumn-1,out snippet);
        if(snippet.Length>2000)snippet=snippet.Substring(0,2000);
        var dirty=true;
        if(buffer is IVsPersistDocData persisted && ErrorHandler.Succeeded(persisted.IsDocDataDirty(out var changed)))dirty=changed!=0;
        if(_commentLocations.TryGetValue(path,out var original))return original with {First=lines.First,Last=lines.Last,StartColumn=lines.StartColumn,EndColumn=lines.EndColumn,Unversioned=original.Unversioned||dirty,HasSelection=selected,Snippet=snippet};
        var root=Cwd();if(root is null)return null;
        var rootPrefix=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        var full=Path.GetFullPath(path);
        if(!full.StartsWith(rootPrefix,StringComparison.OrdinalIgnoreCase))return null;
        var relative=full.Substring(rootPrefix.Length).Replace('\\','/');
        return new CommentCapture(relative,"head",lines.First,lines.Last,dirty,HasSelection:selected,Snippet:snippet,StartColumn:lines.StartColumn,EndColumn:lines.EndColumn);
    }

    private async Task OpenCommentBlobsAsync(CommentsReport recipe)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        var root=Cwd();if(root is null)return;
        async Task<string> SideAsync(string name)
        {
            var row=recipe.Records("comment-blob").SingleOrDefault(b=>b[1]==name) ?? throw new InvalidOperationException(CommentsCopy.historyFailed);
            if(row[2]=="absent")return "";
            if(row.Count<4 || !System.Text.RegularExpressions.Regex.IsMatch(row[3],"\\A(?:[0-9a-f]{40}|[0-9a-f]{64})\\z"))throw new InvalidOperationException(CommentsCopy.historyFailed);
            var result=await _panel.Cli.InvokeResolvedAsync(new ResolvedCommand("git",new[]{"cat-file","blob",row[3]}),root,false,TimeoutClass.SupportGitTimeoutMs).ConfigureAwait(true);
            if(result.ExitCode!=0)throw new InvalidOperationException(result.Stderr.Length>0?result.Stderr:CommentsCopy.historyFailed);
            return result.Stdout;
        }
        var left=await SideAsync("base").ConfigureAwait(true);var right=await SideAsync("head").ConfigureAwait(true);
        if(_serviceProvider.GetService(typeof(SVsDifferenceService)) is not IVsDifferenceService diff)throw new InvalidOperationException(CommentsCopy.historyFailed);
        var folder=Path.Combine(_scratch,"comments",Guid.NewGuid().ToString("N"));
        var leftPath=WriteScratch(Path.Combine(folder,"base.txt"),left);var rightPath=WriteScratch(Path.Combine(folder,"head.txt"),right);
        var range=recipe.Records("comment-diff").Single();
        foreach(var side in new[]{"base","head"}) {
            var blob=recipe.Records("comment-blob").Single(b=>b[1]==side);
            if(blob[2]!="present")continue;
            var originalPath=System.Text.RegularExpressions.Regex.Replace(blob[0],"%(25|09|0D|0A|3E)",m=>m.Groups[1].Value switch {"25"=>"%","09"=>"\t","0D"=>"\r","0A"=>"\n",_=>">"});
            _commentLocations[side=="base"?leftPath:rightPath]=new CommentCapture(originalPath,side,1,1,false,range[1],range[2]);
        }
        var entry = recipe.Records("comment-entry").First();
        var comment = CommentPresentations.Present(recipe,entry);
        var frame = diff.OpenComparisonWindow2(leftPath,rightPath,comment.Location+" · "+comment.Preview,comment.Body,CommentsCopy.baseSide,CommentsCopy.headSide,comment.Location,null,(uint)(__VSDIFFSERVICEOPTIONS.VSDIFFOPT_LeftFileIsTemporary|__VSDIFFSERVICEOPTIONS.VSDIFFOPT_RightFileIsTemporary));
        var location = recipe.Records("comment-location").FirstOrDefault();
        if(location is not null)CommentDiffSelection.Apply(frame,location,recipe.Records("comment-columns").FirstOrDefault(c=>c[0]==location[0] && c[1]==location[1]));
    }
    private async Task OpenCommentDeliveryAsync(CommentsReport report)
    {
        await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
        if(_serviceProvider.GetService(typeof(SVsDifferenceService)) is not IVsDifferenceService diff)throw new InvalidOperationException(CommentsCopy.historyFailed);
        string Side(string role) {
            var row=report.Records("comments-delivery-file").Single(r=>r[1]==role);
            if(row[2]=="present")return row[0];
            if(row[2]=="absent")return WriteScratch(Path.Combine(_scratch,"delivery",role+"-empty.md"),"");
            throw new InvalidOperationException(CommentsCopy.historyFailed);
        }
        var left=Side("prepared");var right=Side("destination");
        diff.OpenComparisonWindow2(left,right,CommentsCopy.deliveryTitle,CommentsCopy.deliveryTitle,CommentsCopy.shared,CommentsCopy.deliveryTitle,CommentsCopy.deliveryTitle,null,0);
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
            var pair=_panel.State.Current.Comments?.Records("comments-capture").FirstOrDefault();
            if(request.Right.Ref is string rightRef && pair is not null && !pair[2].StartsWith(rightRef,StringComparison.Ordinal))pair=null;
            var leftSide=request.Left;
            var rightSide=request.Right;
            if(pair is not null) {
                if(leftSide.Ref is not null)leftSide=leftSide with {Ref=pair[1]};
                if(rightSide.Ref is not null)rightSide=rightSide with {Ref=pair[2]};
            }
            var workingTree = request.Left.Ref is null || request.Right.Ref is null;
            var left = await ResolveSideAsync(cwd, leftSide, "left", workingTree).ConfigureAwait(true);
            var right = await ResolveSideAsync(cwd, rightSide, "right", workingTree).ConfigureAwait(true);
            if(pair is not null) {
                if(request.Left.Path is string basePath)_commentLocations[left.Path]=new CommentCapture(basePath,"base",1,1,false,pair[1],pair[2],request.Left.Path,request.Right.Path);
                if(request.Right.Path is string headPath)_commentLocations[right.Path]=new CommentCapture(headPath,"head",1,1,false,rightSide.Ref is null?null:pair[1],rightSide.Ref is null?null:pair[2],request.Left.Path,request.Right.Path);
            }
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
