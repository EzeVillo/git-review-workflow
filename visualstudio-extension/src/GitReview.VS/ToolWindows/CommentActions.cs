using GitReview.Domain;
using GitReview.Host;

namespace GitReview.VS.ToolWindows;

public sealed partial class ActionDispatcher
{
    private Task<bool> SaveSessionCommentDocumentsAsync(string action,ActionParams? parameters) =>
        _host.SaveCommentPath is null || Cwd is not string cwd ? Task.FromResult(true) :
            SessionCommentSave.SaveAsync(_panel.Cli,cwd,State,action,parameters,_host.HasUnsavedDocuments,_host.SaveCommentPath);

    private CommentsActions CommentFlow() => new(_panel.Cli,_panel.Mutations.Lock,
        _host.SaveCommentPath ?? (_ => Task.FromResult(true)), async()=>await _panel.RefreshAsync().ConfigureAwait(true));
    private static string? CommentFailure(InvokeResult? result) => result is null ? CommentsCopy.failed : result.ExitCode==0 ? null : result.ExitCode==4 ? UserCopy.Stale : result.Stderr.Trim().Length>0 ? result.Stderr.Trim() : CommentsCopy.failed;
    private async Task AddCommentAsync()
    {
        var cwd=Cwd;if(cwd is null || State.Situation is not (Situation.Review or Situation.FinishConflict))return;
        var capture=_host.CaptureComment is null ? null : await _host.CaptureComment().ConfigureAwait(true);
        if(State.Situation==Situation.FinishConflict)capture=null;
        var flow=CommentFlow();var initial=await flow.ReadAsync(cwd).ConfigureAwait(true);if(initial.Guard is null || initial.Destinations().Count==0)return;
        string? contextChoice=null;
        if(initial.Records("comments-identity").Any(i=>i[0]=="ambiguous")) {
            var candidates=initial.Records("comments-candidate").ToArray();
            var choices=new[]{CommentsCopy.newContext+" — "+CommentsCopy.newContextDetail}
                .Concat(candidates.Select(c=>CommentsCopy.continueContext+": "+c[1]+" — "+CommentsCopy.continueContextDetail+" "+c.ElementAtOrDefault(2))).ToArray();
            var hint=initial.Destinations().Contains("shared")?CommentsCopy.contextHint:CommentsCopy.localContextHint;
            var pick=GitReviewDialogs.Choose(CommentsCopy.chooseContext,hint,choices);
            if(pick<0)return;contextChoice=pick==0 ? "" : candidates[pick-1][0];
        }
        new CommentsComposer(capture,initial.Destinations(),async(kind,text,scope)=>{
            var before=await flow.ReadAsync(cwd).ConfigureAwait(true);
            var born=!before.Documents.Any(d=>d.Presence=="present");
            var result=await flow.RunAsync(cwd,"add",kind,null,initial.Guard,input:text,capture:scope=="general"?null:capture is null?null:capture with {IncludeLines=scope=="selection"},contextChoice:contextChoice).ConfigureAwait(true);
            var error=CommentFailure(result);
            if(error is null && born) PanelReveal.Reveal(ControlId.AddComment,_host,commentsBlockBorn:true);
            return error;
        }).Show();
    }
    private async Task CommentRowAsync(string action,int? index)
    {
        var docs=State.Comments?.Documents;var cwd=Cwd;
        if(cwd is null || docs is null || index is null || index<0 || index>=docs.Count)return;
        var doc=docs[index.Value];
        if (action == "copyCommentPath") {
            if (doc.Kind != "local" || doc.Presence != "present") return;
            System.Windows.Clipboard.SetText(doc.Path);
            _panel.View.ShowCommentPathCopied(index.Value);
            return;
        }
        if(action=="openComments") {if(_host.OpenPath is not null)await _host.OpenPath(doc.Path).ConfigureAwait(true);return;}
        if(action=="deleteComments" && !GitReviewDialogs.Confirm(ControlId.DeleteComments,CommentsCopy.deleteTitle,CommentsCopy.deleteDetail,CommentsCopy.delete))return;
        var flow=CommentFlow();var initial=await flow.ReadAsync(cwd,doc.Context).ConfigureAwait(true);
        var guard=CommentsActions.Guard(initial,doc.Context);if(guard is null)return;
        if(action=="openCommentDiff") {
            var entries=await flow.RunAsync(cwd,"entries",doc.Kind,doc.Context,guard).ConfigureAwait(true);
            if(CommentFailure(entries) is string error){GitReviewDialogs.Error(error);return;}
            var report=Comments.Parse(entries!.Stdout);var rows=report.Records("comment-entry").ToArray();
            if(rows.Length==0){GitReviewDialogs.Info(CommentsCopy.empty);return;}
            var canDelete = initial.Records("comments-context").Any(c => c[0] == doc.Context && (c[2] == "active" || c[2] == "result" || c[2] == "repository" && doc.Kind == "local"));
            new CommentsBrowser(rows.Select(entry=>CommentPresentations.Present(report,entry)).ToArray(), async comment => {
                if (!comment.CanOpenDiff) return;
                var revision=report.Documents.Single().Revision;
                var recipe=await flow.RunAsync(cwd,"diff",doc.Kind,doc.Context,guard,ordinal:comment.Ordinal,expectedRevision:revision,porcelain:true).ConfigureAwait(true);
                if(CommentFailure(recipe) is string recipeError)throw new InvalidOperationException(recipeError);
                var resolved=Comments.Parse(recipe!.Stdout);
                resolved=new CommentsReport(resolved.Rows.Concat(report.Rows.Where(r=>r.Tag.StartsWith("comment-",StringComparison.Ordinal) && r.Fields[0]==comment.Ordinal.ToString())).ToArray());
                if(resolved.Records("comment-blob").Any() && _host.OpenCommentBlobs is not null)await _host.OpenCommentBlobs(resolved).ConfigureAwait(true);
                else {
                    var rendered=await flow.RunAsync(cwd,"diff",doc.Kind,doc.Context,guard,ordinal:comment.Ordinal,expectedRevision:revision).ConfigureAwait(true);
                    if(CommentFailure(rendered) is string renderError)throw new InvalidOperationException(renderError);
                    if(_host.OpenText is not null)await _host.OpenText(comment.Location+"\n"+comment.Version+"\n"+comment.Warning+"\n\n"+comment.Body+"\n\n"+rendered!.Stdout).ConfigureAwait(true);
                }
            }, canDelete ? async comment => {
                var revision = report.Documents.Single().Revision;
                var deleted = await flow.RunAsync(cwd, "delete", doc.Kind, doc.Context, guard, ordinal: comment.Ordinal, expectedRevision: revision).ConfigureAwait(true);
                if (CommentFailure(deleted) is string deleteError) throw new InvalidOperationException(deleteError);
                var updated = await flow.RunAsync(cwd, "entries", doc.Kind, doc.Context, guard).ConfigureAwait(true);
                if (CommentFailure(updated) is string readError) throw new InvalidOperationException(readError);
                report = Comments.Parse(updated!.Stdout);
                return report.Records("comment-entry").Select(entry => CommentPresentations.Present(report, entry)).ToArray();
            } : null).Show();
            return;
        }
        IReadOnlyList<string>? deliverySavePaths=null;
        if(action=="prepareSharedComments") {
            var pick=GitReviewDialogs.Choose(CommentsCopy.deliveryTitle,CommentsCopy.deliveryTitle,new[]{CommentsCopy.compareDelivery,CommentsCopy.retryDelivery});
            if(pick<0)return;
            var check=await flow.RunAsync(cwd,"prepare","shared",doc.Context,guard,porcelain:true,check:true).ConfigureAwait(true);
            if(CommentFailure(check) is string checkError){GitReviewDialogs.Error(checkError);return;}
            var files=Comments.Parse(check!.Stdout);
            if(pick==0) {
                if(_host.OpenCommentDelivery is not null)await _host.OpenCommentDelivery(files).ConfigureAwait(true);
                else if(_host.OpenText is not null){var text=await flow.RunAsync(cwd,"prepare","shared",doc.Context,guard,check:true).ConfigureAwait(true);if(CommentFailure(text) is string textError)GitReviewDialogs.Error(textError);else await _host.OpenText(text!.Stdout).ConfigureAwait(true);}
                return;
            }
            deliverySavePaths=files.Records("comments-delivery-file").Where(f=>f[1]!="baseline").Select(f=>f[0]).ToArray();
        }
        var operation=action=="deleteComments" ? "delete" : action=="initComments" ? "init" : action=="renumberComments" ? "renumber" : "prepare";
        var result=await flow.RunAsync(cwd,operation,doc.Kind,doc.Context,guard,expectedRevision:action=="deleteComments"?doc.Revision:null,additionalSavePaths:deliverySavePaths).ConfigureAwait(true);
        var failure=CommentFailure(result);if(failure is not null)GitReviewDialogs.Error(failure);
    }
}
