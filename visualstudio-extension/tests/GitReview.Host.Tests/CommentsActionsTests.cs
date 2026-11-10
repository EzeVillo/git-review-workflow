using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;
public class CommentsActionsTests
{
    [Theory][InlineData(true)][InlineData(false)] public async Task Capture_sends_columns_only_for_selection_scope(bool selection)
    {
        var cli=new ScriptedCli();
        var flow=new CommentsActions(cli,new MutationLock(),_=>Task.FromResult(CommentBufferSave.Unchanged),()=>Task.CompletedTask);
        var result=await flow.RunAsync("/repo","add","local",null,"step1",input:"fragment",capture:new CommentCapture("file","head",1,2,false,HasSelection:true,IncludeLines:selection,StartColumn:2,EndColumn:1));
        Assert.Equal(0,result?.ExitCode);
        var args=cli.LastArgs!.ToList();
        Assert.Equal(selection,args.Contains("--start-column"));
        if(selection){Assert.Equal("2",args[args.IndexOf("--start-column")+1]);Assert.Equal("1",args[args.IndexOf("--end-column")+1]);}
    }
    [Fact] public async Task Individual_delete_keeps_the_captured_document_revision_after_selective_save()
    {
        var cli=new ScriptedCli();
        var flow=new CommentsActions(cli,new MutationLock(),path=>{Assert.Equal("/local.md",path);cli.Local="changed-in-editor";return Task.FromResult(CommentBufferSave.Saved);},()=>Task.CompletedTask);
        var result=await flow.RunAsync("/repo","delete","local","c1","step1",ordinal:2,expectedRevision:"r1");
        Assert.Equal(0,result?.ExitCode);
        var args=cli.LastArgs!.ToList();
        Assert.Equal("delete",args[0]);
        Assert.Equal("2",args[args.IndexOf("--entry")+1]);
        Assert.Equal("r1",args[args.IndexOf("--expect-document")+1]);
        Assert.Equal("step1",args[args.IndexOf("--expect-context")+1]);
        Assert.DoesNotContain("renumber",cli.Trace);
    }
    private sealed class ScriptedCli : CliInvoker
    {
        public string Guard="step1", Local="r1", Shared="r2";
        public readonly List<string> Trace=new();
        public IReadOnlyList<string>? LastArgs;
        public string? Input;
        public bool IncludeOther;
        public bool IncludeLocal = true;
        public bool IncludeShared = true;
        public bool ValidateAddRevision;
        public override Task<InvokeResult> InvokeAsync(string verb,IReadOnlyList<string> args,string cwd,bool network=false,long? timeoutMs=null,CancellationToken cancellationToken=default)
        {
            if(args[0]=="status") {
                Trace.Add("read");
                var text=$"comments-guard\t{Guard}\ncomments-context\tc1\tcompare\tactive\t{Guard}\tCurrent";
                if (IncludeLocal) text += $"\ncomments-document\t/local.md\tc1\tlocal\tpresent\t{Local}";
                if (IncludeShared) text += $"\ncomments-document\t/shared.md\tc1\tshared\tpresent\t{Shared}";
                if(IncludeOther)text+="\ncomments-context\tc2\treview\tresult\told\tOther\ncomments-document\t/other.md\tc2\tlocal\tpresent\told";
                return Task.FromResult(new InvokeResult(text,"",0));
            }
            Trace.Add(args[0]);LastArgs=args.ToArray();return Task.FromResult(new InvokeResult("","",0));
        }
        public override Task<InvokeResult> InvokeWithInputAsync(string verb,IReadOnlyList<string> args,string cwd,string input,CancellationToken cancellationToken=default)
        {
            Input = input;
            var result = InvokeAsync(verb,args,cwd,cancellationToken:cancellationToken);
            if (ValidateAddRevision && args[args.ToList().IndexOf("--expect-document")+1] != Local)
                return Task.FromResult(new InvokeResult("", "error: comments document is stale", 4));
            return result;
        }
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Add_uses_one_read_for_missing_or_clean_documents(bool existing)
    {
        var cli = new ScriptedCli { IncludeLocal = existing, IncludeShared = false };
        var mutationLock = new MutationLock();
        var flow = new CommentsActions(cli, mutationLock, path =>
        {
            cli.Trace.Add("save:" + path);
            return Task.FromResult(CommentBufferSave.Unchanged);
        }, () => { cli.Trace.Add("refresh"); return Task.CompletedTask; });

        var result = await flow.RunAsync("/repo", "add", "local", null, "step1", input: "note", beforeInvoke: report =>
        {
            Assert.True(mutationLock.IsBusy);
            Assert.Equal(existing, report.Documents.Any(d => d.Presence == "present"));
            cli.Trace.Add("before add");
        });

        Assert.Equal(0, result?.ExitCode);
        Assert.Equal(existing ? new[] { "read", "save:/local.md", "before add", "add", "refresh" } :
            new[] { "read", "before add", "add", "refresh" }, cli.Trace);
        Assert.Equal(new[] { "add", "--document", "local", "--expect-context", "step1",
            "--expect-document", existing ? "r1" : "absent", "--stdin" }, cli.LastArgs);
    }

    [Fact]
    public async Task Add_with_clean_editor_uses_the_form_guard_and_skips_the_document_read()
    {
        var cli = new ScriptedCli();
        var mutationLock = new MutationLock();
        var initial = Comments.Parse("comments-guard\tstep1\ncomments-add-reply\t1");
        var flow = new CommentsActions(cli, mutationLock,
            _ => throw new InvalidOperationException("A clean editor has nothing to save"),
            () => Task.CompletedTask,
            hasUnsavedDocuments: () =>
            {
                Assert.True(mutationLock.IsBusy);
                return Task.FromResult<bool?>(false);
            });

        var result = await flow.RunAsync("/repo", "add", "local", null, "step1", input: "note", composerReport: initial);

        Assert.Equal(0, result?.ExitCode);
        Assert.Equal(new[] { "add" }, cli.Trace);
        Assert.Equal(new[] { "add", "--document", "local", "--expect-context", "step1", "--stdin" }, cli.LastArgs);
        Assert.Equal("note", cli.Input);
    }

    [Fact]
    public async Task External_edit_without_a_buffer_save_is_rejected_by_the_CLI_guard()
    {
        var cli = new ScriptedCli { ValidateAddRevision = true };
        var flow = new CommentsActions(cli, new MutationLock(), _ =>
        {
            cli.Local = "external edit";
            return Task.FromResult(CommentBufferSave.Unchanged);
        }, () => Task.CompletedTask);

        var result = await flow.RunAsync("/repo", "add", "local", null, "step1", input: "note");

        Assert.Equal(4, result?.ExitCode);
        Assert.Equal(new[] { "read", "add" }, cli.Trace);
        Assert.Contains("r1", cli.LastArgs!);
    }

    [Fact] public async Task Capture_saves_only_chosen_Markdown_then_reads_fresh_revision_under_lock()
    {
        var cli=new ScriptedCli();var mutationLock=new MutationLock();
        var flow=new CommentsActions(cli,mutationLock,path=>{
            Assert.True(mutationLock.IsBusy);Assert.Equal("/local.md",path);cli.Trace.Add("save:"+path);cli.Local="after-save";return Task.FromResult(CommentBufferSave.Saved);
        },()=>{Assert.True(mutationLock.IsBusy);cli.Trace.Add("refresh");return Task.CompletedTask;});
        const string text="línea\n\n$(do not execute)";
        var result=await flow.RunAsync("/repo","add","local",null,"step1",input:text);
        Assert.Equal(0,result?.ExitCode);
        Assert.Equal(new[]{"read","save:/local.md","read","add","refresh"},cli.Trace);
        Assert.Equal(text,cli.Input);Assert.DoesNotContain(text,cli.LastArgs!);
        var args=cli.LastArgs!.ToList();Assert.Equal("after-save",args[args.IndexOf("--expect-document")+1]);
        Assert.Equal("step1",args[args.IndexOf("--expect-context")+1]);Assert.False(mutationLock.IsBusy);
    }
    [Theory][InlineData(false)][InlineData(true)] public async Task Failed_save_never_invokes_mutation(bool throws)
    {
        var cli=new ScriptedCli();var flow=new CommentsActions(cli,new MutationLock(),_=>throws?Task.FromException<CommentBufferSave>(new IOException("disk")):Task.FromResult(CommentBufferSave.Failed),()=>Task.CompletedTask);
        var result=await flow.RunAsync("/repo","add","shared",null,"step1",input:"keep this");
        Assert.Equal(1,result?.ExitCode);Assert.Null(cli.Input);Assert.Null(cli.LastArgs);Assert.Equal(new[]{"read"},cli.Trace);
    }
    [Fact] public async Task Step_change_during_save_rejects_original_capture_without_mutation()
    {
        var cli=new ScriptedCli();var flow=new CommentsActions(cli,new MutationLock(),_=>{cli.Guard="step2";return Task.FromResult(CommentBufferSave.Saved);},()=>Task.CompletedTask);
        var result=await flow.RunAsync("/repo","add","local",null,"step1",input:"keep this");
        Assert.Equal(4,result?.ExitCode);Assert.Null(cli.Input);Assert.Null(cli.LastArgs);
    }
    [Fact] public async Task Save_comments_does_not_save_another_context()
    {
        var cli=new ScriptedCli{IncludeOther=true};var paths=new List<string>();
        var flow=new CommentsActions(cli,new MutationLock(),p=>{paths.Add(p);return Task.FromResult(CommentBufferSave.Unchanged);},()=>Task.CompletedTask);
        var result=await flow.RunAsync("/repo","save",null,null,"step1");
        Assert.Equal(0,result?.ExitCode);Assert.Equal(new[]{"/local.md","/shared.md"},paths);
    }
    [Fact] public void Selection_normalizes_reverse_zero_column_and_caret()
    {Assert.Equal((3,5),Comments.SelectionLines(5,0,2,4));Assert.Equal((3,3),Comments.SelectionLines(2,4,2,4));}
}
