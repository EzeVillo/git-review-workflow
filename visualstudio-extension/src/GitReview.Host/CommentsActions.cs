using GitReview.Domain;

namespace GitReview.Host;

public enum CommentBufferSave
{
    Unchanged,
    Saved,
    Failed,
}

/// <summary>Selective saves and CLI guards share the client's mutation lock.</summary>
public sealed class CommentsActions
{
    private readonly CliInvoker _cli;
    private readonly MutationLock _lock;
    private readonly Func<string, Task<CommentBufferSave>> _save;
    private readonly Func<Task> _refresh;
    private readonly ReviewStateManager? _state;
    private readonly Func<Task<bool?>>? _hasUnsavedDocuments;
    public CommentsActions(CliInvoker cli, MutationLock mutationLock, Func<string, Task<CommentBufferSave>> save, Func<Task> refresh, ReviewStateManager? state = null, Func<Task<bool?>>? hasUnsavedDocuments = null)
    { _cli=cli; _lock=mutationLock; _save=save; _refresh=refresh; _state=state; _hasUnsavedDocuments=hasUnsavedDocuments; }

    public async Task<CommentsReport> ReadAsync(string cwd, string? context = null)
    {
        var result = await _cli.InvokeAsync("comments", new[]{"status", "--porcelain"}.Concat(context is null ? Array.Empty<string>() : new[]{"--context",context}).ToArray(), cwd).ConfigureAwait(false);
        var report=Comments.Parse(result.Stdout);
        return result.ExitCode==0 ? report : report with {Rows=report.Rows.Concat(new[]{new CommentRow("comments-diagnostic",new[]{"","read",result.Stderr})}).ToArray()};
    }
    public static string? Guard(CommentsReport report, string? context) => report.Guard ?? report.Records("comments-context").FirstOrDefault(c=>c[0]==context)?[3];

    public Task<InvokeResult?> RunAsync(string cwd, string operation, string? document, string? context, string capturedGuard,
        string? input = null, CommentCapture? capture = null, int? ordinal = null, string? expectedRevision = null, string? contextChoice = null, bool porcelain = false, bool check = false, IReadOnlyList<string>? additionalSavePaths = null,
        Action<CommentsReport>? beforeInvoke = null, CommentsReport? composerReport = null)
        => _lock.RunAsync(async () => {
            var applied = false;
            try
            {
                var useLatestDocument = operation == "add" && document is not null && context is null &&
                    expectedRevision is null && additionalSavePaths is null && composerReport?.SupportsAddReply == true &&
                    composerReport.Guard == capturedGuard && _hasUnsavedDocuments is not null &&
                    await _hasUnsavedDocuments().ConfigureAwait(true) == false;
                var current = useLatestDocument ? composerReport! : await ReadAsync(cwd,context).ConfigureAwait(true);
                if (Guard(current,context)!=capturedGuard) return new InvokeResult("",UserCopy.Stale,4);
                if (!useLatestDocument)
                {
                    var active=new HashSet<string>(current.Records("comments-context").Where(c=>c[2]=="active").Select(c=>c[0]));
                    var affected=current.Documents.Where(d=>(context is null ? active.Contains(d.Context) : d.Context==context) && (operation=="save" || d.Kind==document)).ToArray();
                    var saved = false;
                    foreach (var path in affected.Select(d=>d.Path).Concat(additionalSavePaths ?? Array.Empty<string>()).Distinct(StringComparer.OrdinalIgnoreCase))
                    {
                        var outcome = await _save(path).ConfigureAwait(true);
                        if (outcome == CommentBufferSave.Failed) return new InvokeResult("",CommentsCopy.saveFailed,1);
                        saved |= outcome == CommentBufferSave.Saved;
                    }
                    if (operation != "add" || saved)
                    {
                        current = await ReadAsync(cwd,context).ConfigureAwait(true);
                        if (Guard(current,context)!=capturedGuard) return new InvokeResult("",UserCopy.Stale,4);
                    }
                }
                var args = useLatestDocument ? new List<string>{"add","--document",document!,"--expect-context",capturedGuard}
                    : Comments.Argv(current,operation,document,context,ordinal).ToList();
                if (porcelain) args.Add("--porcelain");
                if (check) args.Add("--check");
                if (expectedRevision is not null) {var i=args.IndexOf("--expect-document");if(i>=0)args[i+1]=expectedRevision;}
                if (contextChoice is not null) {if(contextChoice.Length==0) args.Add("--new-context");else args.AddRange(new[]{"--use-context",contextChoice});}
                if (input is not null) args.Add("--stdin");
                if (capture is not null) {
                    args.AddRange(new[]{"--path",capture.Path,"--side",capture.Side});
                    if(capture.IncludeLines)args.AddRange(new[]{"--start-line",capture.First.ToString(),"--end-line",capture.Last.ToString()});
                    if(capture.IncludeLines && capture.StartColumn.HasValue && capture.EndColumn.HasValue)args.AddRange(new[]{"--start-column",capture.StartColumn.Value.ToString(),"--end-column",capture.EndColumn.Value.ToString()});
                    if(capture.Unversioned)args.Add("--unversioned");
                    if(capture.Base is not null && capture.Head is not null)args.AddRange(new[]{"--base",capture.Base,"--head",capture.Head});
                    if(capture.BasePath is not null)args.AddRange(new[]{"--base-path",capture.BasePath});
                    if(capture.HeadPath is not null)args.AddRange(new[]{"--head-path",capture.HeadPath});
                }
                beforeInvoke?.Invoke(current);
                var snapshot = operation == "add" && document is not null && current.SupportsAddReply ? _state?.CaptureCommentsAdd() : null;
                var wantsReply = snapshot?.State.Guard is not null;
                if (wantsReply && !porcelain) args.Add("--porcelain");
                var result = input is null ? await _cli.InvokeAsync("comments",args,cwd).ConfigureAwait(true) : await _cli.InvokeWithInputAsync("comments",args,cwd,input).ConfigureAwait(true);
                if (wantsReply && result.ExitCode == 0 && !result.TimedOut && Comments.ParseAddReply(result.Stdout, document!) is { } reply)
                    applied = _state!.ApplyCommentsAdd(snapshot!.Value, cwd, reply);
                return result;
            }
            catch(Exception error){return new InvokeResult("",error.Message,1);}
            finally {if (!applied) await _refresh().ConfigureAwait(true);}
        });
}
