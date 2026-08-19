using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;

/// <summary>
/// Serialises mutations through the lock and refreshes after each one. What this
/// gets wrong is either a command that runs twice or a panel showing pre-mutation
/// state, and neither is visible until someone hits it by hand.
/// </summary>
public class MutationRunnerTests
{
    private const string WalkStatus =
        "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t3\t3\t\"src/a.kt\"\t1\n" +
        "entry\t1\tsrc/a.kt\t1\t1";

    private static (MutationRunner Runner, FakeCliInvoker Cli, ReviewStateManager State) Build(
        string? cwd = "/repo", FakeCliInvoker? cli = null)
    {
        cli ??= new FakeCliInvoker().Answer("status", WalkStatus);
        var state = new ReviewStateManager(cli, () => cwd is null ? Array.Empty<string>() : new[] { cwd });
        return (new MutationRunner(cli, state, () => cwd), cli, state);
    }

    [Fact]
    public async Task An_action_runs_its_argv_and_then_refreshes()
    {
        var (runner, cli, state) = Build();
        var result = await runner.RunActionAsync("next");

        Assert.NotNull(result);
        Assert.Equal(0, result!.ExitCode);
        // The mutation, then the probe and the status that follow it.
        Assert.Equal(new[] { "next", "--version", "status" }, cli.Verbs);
        Assert.Equal(Situation.Review, state.Current.Situation);
    }

    [Fact]
    public async Task The_argv_comes_from_the_action_table()
    {
        var (runner, cli, _) = Build();
        await runner.RunActionAsync(
            "cleanReview",
            new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.CleanKeepFixes, "feature/x")));
        var call = cli.Calls[0];
        Assert.Equal("clean", call.Verb);
        Assert.Equal(new[] { "--keep-fixes", "feature/x" }, call.Args);
    }

    /// <summary>
    /// The network flag decides the timeout budget and whether askpass is wired in,
    /// and it comes from the action rather than from the caller remembering.
    /// </summary>
    [Fact]
    public async Task The_network_flag_comes_from_the_action_itself()
    {
        var (runner, cli, _) = Build();
        var intent = new ReviewIntent("f", ReviewLayout.Walk, ReviewRange.Full, ReviewSource.Remote);
        await runner.RunActionAsync("startReview", new ActionParams.Start(intent, "main"));
        Assert.True(cli.Calls[0].Network);

        await runner.RunActionAsync("next");
        Assert.False(cli.Calls.First(c => c.Verb == "next").Network);
    }

    /// <summary>A panel-only action spawns nothing, and does not refresh either.</summary>
    [Fact]
    public async Task An_action_with_no_verb_runs_no_process()
    {
        var (runner, cli, _) = Build();
        var result = await runner.RunActionAsync("openEntry");
        Assert.Equal(0, result?.ExitCode);
        Assert.Empty(cli.Calls);
    }

    [Fact]
    public async Task Raw_argv_goes_through_the_same_lock_and_refresh()
    {
        var (runner, cli, _) = Build();
        await runner.RunArgvAsync("walkthrough", new[] { "draft", "--", "f" });
        Assert.Equal("walkthrough", cli.Calls[0].Verb);
        Assert.Equal(new[] { "draft", "--", "f" }, cli.Calls[0].Args);
        Assert.Contains("status", cli.Verbs);
    }

    /// <summary>
    /// Without a single root there is nothing to run in, and the runner says so
    /// instead of spawning in whatever the process happens to be sitting in.
    /// </summary>
    [Fact]
    public async Task Without_a_sole_root_nothing_is_spawned()
    {
        var (runner, cli, _) = Build(cwd: null);
        var result = await runner.RunActionAsync("next");
        Assert.Equal(UserCopy.NoSoleRoot, result?.Stderr);
        Assert.Equal(1, result?.ExitCode);
        Assert.Empty(cli.Calls);

        var raw = await runner.RunArgvAsync("next", Array.Empty<string>());
        Assert.Equal(UserCopy.NoSoleRoot, raw?.Stderr);
        Assert.Empty(cli.Calls);
    }

    /// <summary>
    /// Depth one: a second mutation while one is in flight is discarded, not queued.
    /// Queuing would run it against state the first has already changed.
    /// </summary>
    [Fact]
    public async Task A_second_mutation_while_one_is_running_is_discarded()
    {
        var gate = new TaskCompletionSource();
        var cli = new GatedInvoker(gate.Task);
        var state = new ReviewStateManager(cli, () => new[] { "/repo" });
        var runner = new MutationRunner(cli, state, () => "/repo");

        var discarded = new List<string>();
        runner.Lock.OnDidDiscard(discarded.Add);

        var first = runner.RunActionAsync("next");
        Assert.True(runner.IsBusy);

        var second = await runner.RunActionAsync("prev");
        Assert.Null(second);
        Assert.Equal(new[] { MutationLock.DiscardReason }, discarded);

        gate.SetResult();
        Assert.NotNull(await first);
        Assert.False(runner.IsBusy);
        Assert.DoesNotContain("prev", cli.Verbs);
    }

    [Fact]
    public async Task The_lock_is_released_even_when_the_action_is_unknown()
    {
        var (runner, _, _) = Build();
        await Assert.ThrowsAsync<ArgumentException>(() => runner.RunActionAsync("notAnAction"));
        Assert.False(runner.IsBusy);
        Assert.NotNull(await runner.RunActionAsync("next"));
    }

    private sealed class GatedInvoker : CliInvoker
    {
        private readonly Task _gate;
        public List<string> Verbs { get; } = new();

        public GatedInvoker(Task gate) => _gate = gate;

        public override async Task<InvokeResult> InvokeAsync(
            string verb,
            IReadOnlyList<string> args,
            string cwd,
            bool network = false,
            long? timeoutMs = null,
            CancellationToken cancellationToken = default)
        {
            Verbs.Add(verb);
            if (verb is "next") await _gate.ConfigureAwait(false);
            return verb switch
            {
                "--version" => new InvokeResult(CliVersion.MinCliVersion + "\n", "", 0),
                "status" => new InvokeResult(WalkStatus, "", 0),
                _ => new InvokeResult("", "", 0),
            };
        }
    }
}
