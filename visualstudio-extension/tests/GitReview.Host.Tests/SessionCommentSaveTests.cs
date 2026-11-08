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
}
