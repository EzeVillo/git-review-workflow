using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;

public class StateGuardTests
{
    [Fact] public async Task Confirmation_scopes_preserve_the_original_guard_across_async_work()
    {
        var scope = new MutationExpectation();
        var original = new ReviewState(Situation.NoReview, Guard: new string('a',40));
        using (scope.Capture(original))
        {
            await Task.Yield();
            Assert.Equal(original.Guard, scope.Current!.Guard);
            await Task.Run(async () => {
                using (scope.Capture(original with {Guard=new string('b',40)}))
                {
                    await Task.Yield();
                    Assert.Equal(new string('b',40), scope.Current!.Guard);
                }
            });
            Assert.Equal(original.Guard, scope.Current!.Guard);
        }
        Assert.Null(scope.Current);
    }

    [Fact] public async Task A_CLI_guard_avoids_the_full_pre_mutation_read_and_is_sent_to_the_CLI()
    {
        var guard = new string('a', 40);
        var cli = new FakeCliInvoker().Answer("status", "state\treview/feature\tfeature\tdeadbeef\twhole\tnone\nguard\t" + guard);
        var state = new ReviewStateManager(cli, () => new[]{"/repo"});
        var published = await state.RefreshAsync();
        cli.Calls.Clear();
        Assert.Equal(guard, published.Guard);
        Assert.Same(published, await state.ReadForMutationAsync());
        Assert.Empty(cli.Calls);
        cli.Answer("--expect-state", new InvokeResult("", "error: review state changed", 4));
        var runner = new MutationRunner(cli, state, () => "/repo");
        var result = await runner.RunActionAsync("next");
        Assert.Equal(4, result!.ExitCode);
        Assert.Equal(UserCopy.Stale, result.Stderr);
        Assert.Equal("--expect-state", cli.Calls[0].Verb);
        Assert.Equal(new[]{guard, "next"}, cli.Calls[0].Args);
        Assert.Contains(cli.Calls, call => call.Verb == "status");
    }

    [Fact] public void Guards_are_not_inferred_and_ambiguous_reports_fall_back()
    {
        Assert.Null(StaleGuard.Parse("state\treview/feature"));
        Assert.Null(StaleGuard.Parse("guard\tbad"));
        Assert.Null(StaleGuard.Parse("guard\t" + new string('a', 40) + "\nguard\t" + new string('b', 40)));
        Assert.Equal(new string('a', 64), StaleGuard.Parse("guard\t" + new string('a', 64) + "\r\n"));
        var initial = new ReviewState(Situation.NoReview, Guard: new string('a', 40));
        Assert.False(StaleGuard.TokenStillValid(StaleGuard.CaptureToken(initial), initial with {Guard=new string('b',40)}));
    }
}
