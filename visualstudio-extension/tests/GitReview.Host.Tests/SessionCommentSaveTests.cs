using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;

public class SessionCommentSaveTests
{
    private static readonly ReviewState State = new(Situation.Review, State:new StateRecord("review/x","x","tip",ReviewMode.Whole,WalkthroughStatus.None));
    private const string Report = "comments-owner\tc\tg\treview/x\ncomments-document\t/private.md\tc\tlocal\tpresent\tr\n" +
        "comments-owner\tother\tg\treview/other\ncomments-document\t/other.md\tother\tlocal\tpresent\tr";

    [Fact] public async Task Clean_editor_skips_the_inventory_and_saving()
    {
        var cli = new FakeCliInvoker().Fails("comments","must not run");
        Assert.True(await SessionCommentSave.SaveAsync(cli,"/repo",State,"abortReview",null,
            () => Task.FromResult<bool?>(false), _ => throw new Exception("must not save")));
        Assert.Empty(cli.Calls);
    }

    [Theory] [InlineData(true)] [InlineData(null)]
    public async Task Dirty_or_unknown_editor_saves_only_owned_documents(bool? dirty)
    {
        var cli = new FakeCliInvoker().Answer("comments",Report);
        var paths = new List<string>();
        Assert.True(await SessionCommentSave.SaveAsync(cli,"/repo",State,"finishReview",null,
            () => Task.FromResult(dirty), path => {paths.Add(path);return Task.FromResult(true);}));
        Assert.Equal(new[]{"comments"},cli.Verbs);
        Assert.Equal(new[]{"status","--porcelain","--all"},cli.Calls[0].Args);
        Assert.Equal(new[]{"/private.md"},paths);
    }

    [Fact] public async Task Uncertainty_keeps_the_query_and_failures_keep_the_action_blocked()
    {
        var cli = new FakeCliInvoker().Answer("comments",Report);
        Assert.True(await SessionCommentSave.SaveAsync(cli,"/repo",State,"saveReview",null,
            () => throw new Exception("unknown"), _ => Task.FromResult(true)));
        Assert.Equal(new[]{"comments"},cli.Verbs);
        Assert.False(await SessionCommentSave.SaveAsync(cli,"/repo",State,"saveReview",null,
            () => Task.FromResult<bool?>(true), _ => Task.FromResult(false)));
        cli.Fails("comments","query failed");
        Assert.False(await SessionCommentSave.SaveAsync(cli,"/repo",State,"saveReview",null,
            () => Task.FromResult<bool?>(true), _ => throw new Exception("must not save")));
    }
    [Fact] public async Task Active_closures_use_only_validated_paths_and_legacy_is_explicit()
    {
        var guard=new string('a',40);
        var current=State with {Guard=guard,CommentsPaths=true};
        var wire=$"comments-paths\t1\t{guard}\t{new string('b',40)}\ncomments-path\tlocal\t/private.md\ncomments-path\tshared\t/shared.md\ncomments-paths\tcomplete\n";
        foreach(var action in new[]{"saveReview","abortReview","finishReview","undoFinish","resumeFinish"})
        {
            var cli=new FakeCliInvoker().Answer("comments",wire);
            var paths=new List<string>();
            Assert.True(await SessionCommentSave.SaveAsync(cli,"/repo",current,action,null,()=>Task.FromResult<bool?>(true),p=>{paths.Add(p);return Task.FromResult(true);}));
            Assert.Equal(new[]{"paths","--porcelain"},cli.Calls.Single().Args);
            Assert.Equal(new[]{"/private.md","/shared.md"},paths);
        }
        foreach(var bad in new[]{wire.Replace("complete","truncated"),wire.Replace(guard,new string('c',40)),wire+"comments-paths\tcomplete\n"})
        {
            var cli=new FakeCliInvoker().Answer("comments",bad);
            Assert.False(await SessionCommentSave.SaveAsync(cli,"/repo",current,"saveReview",null,()=>Task.FromResult<bool?>(true),_=>throw new Exception("must not save")));
        }
        var legacy=new FakeCliInvoker().Answer("comments",$"comments-paths\t1\t{guard}\tlegacy\ncomments-paths\tcomplete\n");
        Assert.True(await SessionCommentSave.SaveAsync(legacy,"/repo",current,"saveReview",null,()=>Task.FromResult<bool?>(true),_=>Task.FromResult(true)));
        Assert.Equal(new[]{"paths","--porcelain"},legacy.Calls[0].Args);
        Assert.Equal(new[]{"status","--porcelain","--all"},legacy.Calls[1].Args);
    }
    [Fact] public void Path_encoding_is_literal_and_incomplete_reports_are_not_authorization()
    {
        var guard=new string('a',40);
        var wire=$"comments-paths\t1\t{guard}\t{new string('b',40)}\ncomments-path\tlocal\t/Café + %252F%09%0D%0A%3E\ncomments-path\tshared\t/shared.md\ncomments-paths\tcomplete\n";
        Assert.Equal(new[]{"/Café + %2F\t\r\n>","/shared.md"},CommentPaths.Parse(wire,guard)!.Paths);
        Assert.Null(CommentPaths.Parse(wire.Replace("%09","%GG"),guard));
        Assert.Null(CommentPaths.Parse(wire.Replace("comments-path\tshared\t/shared.md\n",""),guard));
    }

}
