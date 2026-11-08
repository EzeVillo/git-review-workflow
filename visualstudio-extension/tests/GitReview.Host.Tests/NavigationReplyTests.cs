using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;

public class NavigationReplyTests
{
    [Fact] public void Inline_prose_preserves_escaping_and_invalid_or_missing_data_stays_unknown()
    {
        const string wire="why\tpresent\t3\nwhy-line\t1\tcafé \\t \\\\n\nwhy-line\t2\t\nwhy-line\t3\tA\\rB  \n";
        Assert.Equal("café \t \\n\n\nA\rB  \n",NavigationReply.InlineWhy(wire));
        Assert.Equal("",NavigationReply.InlineWhy("why\tabsent\t0\n"));
        foreach(var bad in new[]{"", "why\tabsent\t1", "why\tpresent\t0", "why\tpresent\t2\nwhy-line\t1\tone",
            "why\tpresent\t1\nwhy-line\t2\tone", "why\tpresent\t1\nwhy-line\t1\tbad\\x",
            "why\tpresent\t1\nwhy-line\t1\tbad\\", "why\tabsent\t0\nwhy\tabsent\t0"}) Assert.Null(NavigationReply.InlineWhy(bad));
    }

    [Fact] public async Task The_primary_navigation_state_carries_its_exact_prose()
    {
        var cli=new DeferredComments();
        var manager=new ReviewStateManager(cli,()=>new[]{"/repo"});
        var state=await manager.RefreshPrimaryAsync(navigationOutput:Reply()+"why\tpresent\t1\nwhy-line\t1\tfrom this snapshot\n");
        Assert.Equal("from this snapshot\n",state.InlineWhy);
        Assert.Equal(new[]{"comments"},cli.Calls);
        cli.Pending.SetResult(new InvokeResult("","",0));
    }
    private static string Reply(char guard = 'a', int position = 1) =>
        $"state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t{position}\t2\t2\ta.txt\t0\n" +
        "entry\t1\ta.txt\t0\t1\nentry\t2\tb.txt\t0\t1\ncapability\tnavigation-state\n" +
        "guard\t" + new string(guard,40) + "\nnavigation\tmoved\n";

    private sealed class DeferredComments : CliInvoker
    {
        public List<string> Calls {get;} = new();
        public TaskCompletionSource<InvokeResult> Pending {get;} = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override Task<InvokeResult> InvokeAsync(string verb, IReadOnlyList<string> args, string cwd,
            bool network=false, long? timeoutMs=null, CancellationToken cancellationToken=default)
        {
            Calls.Add(verb);
            return Pending.Task;
        }
    }

    [Fact] public async Task A_navigation_reply_publishes_primary_state_without_waiting_for_comments()
    {
        var cli = new DeferredComments();
        var manager = new ReviewStateManager(cli, () => new[]{"/repo"});
        var pending = manager.RefreshPrimaryAsync(navigationOutput:Reply());
        var state = await pending.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(new[]{"comments"},cli.Calls);
        Assert.Equal(1,state.State!.Position);
        Assert.True(state.NavigationState);
        Assert.True(state.Comments!.Loading);
        var complete = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        manager.StateChanged += next => { if (next.Comments?.Loading == false) complete.TrySetResult(true); };
        cli.Pending.SetResult(new InvokeResult("", "", 0));
        await complete.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.False(manager.Current.Comments!.Loading);
    }

    [Fact] public async Task Old_comments_cannot_overwrite_a_newer_navigation()
    {
        var cli = new DeferredComments();
        var manager = new ReviewStateManager(cli, () => new[]{"/repo"});
        await manager.RefreshPrimaryAsync(navigationOutput:Reply());
        await manager.RefreshPrimaryAsync(navigationOutput:Reply('b',2));
        var done = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        manager.StateChanged += next => { if (next.Comments?.Loading == false) done.TrySetResult(true); };
        cli.Pending.SetResult(new InvokeResult("", "", 0));
        await done.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(2,manager.Current.State!.Position);
        Assert.Equal(new string('b',40),manager.Current.Guard);
    }

    [Fact] public async Task Missing_or_invalid_replies_fall_back_to_the_full_read()
    {
        var cli = new FakeCliInvoker().Answer("status",Reply());
        var manager = new ReviewStateManager(cli, () => new[]{"/repo"});
        await manager.RefreshPrimaryAsync(navigationOutput:Reply().Replace("navigation\tmoved","navigation\tunknown"));
        Assert.Equal(new[]{"--version","status","comments"},cli.Verbs);
        Assert.False(NavigationReply.IsValid(Reply()+"navigation\tmoved\n"));
        Assert.False(NavigationReply.IsValid(Reply().Replace("capability\tnavigation-state\n","")));
    }

    [Fact] public async Task The_mutation_runner_requests_and_consumes_the_reply_without_a_status_refresh()
    {
        var cli = new FakeCliInvoker().Answer("status",Reply()).Answer("--expect-state",Reply('b',2));
        var manager = new ReviewStateManager(cli, () => new[]{"/repo"});
        await manager.RefreshAsync();
        cli.Calls.Clear();
        var runner = new MutationRunner(cli,manager,() => "/repo");
        var result = await runner.RunActionAsync("next");
        Assert.Equal(0,result!.ExitCode);
        Assert.Equal(new[]{"--expect-state","comments"},cli.Verbs);
        Assert.Equal(new[]{new string('a',40),"next","--porcelain"},cli.Calls[0].Args);
        Assert.Equal(2,manager.Current.State!.Position);
        Assert.Equal(new string('b',40),manager.Current.Guard);
    }
}
