using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The small pieces the panel and the host lean on. Port of the jetbrains
/// MiscDomainTest; none of them had a test in this client.
/// </summary>
public class MiscDomainTests
{
    /// <summary>
    /// Depth one, discarded rather than queued: a second mutation while one is in
    /// flight would run against state the first has already changed.
    /// </summary>
    [Fact]
    public void Mutation_lock_discards_the_second_call()
    {
        var mutationLock = new MutationLock();
        var discarded = new List<string>();
        var busyEvents = new List<bool>();
        mutationLock.OnDidDiscard(discarded.Add);
        mutationLock.OnDidChangeBusy(busyEvents.Add);

        var innerRan = false;
        var first = mutationLock.Run(() =>
        {
            Assert.True(mutationLock.IsBusy);
            var second = mutationLock.Run<object?>(() =>
            {
                innerRan = true;
                return "nope";
            });
            Assert.Null(second);
            return "done";
        });

        Assert.Equal("done", first);
        Assert.False(innerRan, "the discarded call must not run its body");
        Assert.Equal(new[] { MutationLock.DiscardReason }, discarded);
        Assert.Equal(new[] { true, false }, busyEvents);
        Assert.False(mutationLock.IsBusy);
    }

    /// <summary>The lock releases even when the body throws, or the panel stays busy forever.</summary>
    [Fact]
    public void Mutation_lock_releases_after_a_throw()
    {
        var mutationLock = new MutationLock();
        Assert.Throws<InvalidOperationException>(
            () => mutationLock.Run<object?>(() => throw new InvalidOperationException("boom")));
        Assert.False(mutationLock.IsBusy);
        Assert.Equal("after", mutationLock.Run(() => "after"));
    }

    [Fact]
    public async Task Mutation_lock_serialises_the_async_path_too()
    {
        var mutationLock = new MutationLock();
        var discarded = new List<string>();
        mutationLock.OnDidDiscard(discarded.Add);

        var gate = new TaskCompletionSource();
        var first = mutationLock.RunAsync(async () =>
        {
            await gate.Task;
            return "first";
        });

        var second = await mutationLock.RunAsync(() => Task.FromResult("second"));
        Assert.Null(second);
        Assert.Single(discarded);

        gate.SetResult();
        Assert.Equal("first", await first);
        Assert.False(mutationLock.IsBusy);
    }

    [Fact]
    public void Mutation_lock_listeners_can_be_removed()
    {
        var mutationLock = new MutationLock();
        var seen = 0;
        var subscription = mutationLock.OnDidChangeBusy(_ => seen++);
        mutationLock.Run(() => 1);
        Assert.Equal(2, seen);
        subscription.Dispose();
        mutationLock.Run(() => 1);
        Assert.Equal(2, seen);
    }

    /// <summary>
    /// The token is what a long action carries so it can tell, when it comes back,
    /// whether it is still acting on the review it was started from.
    /// </summary>
    [Fact]
    public void Stale_guard_notices_a_moved_tip_a_renamed_branch_or_a_new_situation()
    {
        var state = new ReviewState(
            Situation.Review,
            State: new StateRecord("review/f", "f", "tip1", ReviewMode.Whole, WalkthroughStatus.None));
        var token = StaleGuard.CaptureToken(state);
        Assert.True(StaleGuard.TokenStillValid(token, state));

        Assert.False(StaleGuard.TokenStillValid(
            token, state with { State = state.State! with { Tip = "tip2" } }));
        Assert.False(StaleGuard.TokenStillValid(
            token, state with { State = state.State! with { Branch = "review/other" } }));
        Assert.False(StaleGuard.TokenStillValid(token, state with { Situation = Situation.NoReview }));
        // The review disappearing entirely is the most important case of all.
        Assert.False(StaleGuard.TokenStillValid(token, new ReviewState(Situation.NoReview)));
    }

    /// <summary>A situation with no review still has a token, and it still compares.</summary>
    [Fact]
    public void Stale_guard_works_on_situations_with_no_state_record()
    {
        var empty = new ReviewState(Situation.NoReview);
        var token = StaleGuard.CaptureToken(empty);
        Assert.Null(token.Branch);
        Assert.True(StaleGuard.TokenStillValid(token, empty));
        Assert.False(StaleGuard.TokenStillValid(token, new ReviewState(Situation.Error)));
    }

    /// <summary>One usable root, like the CLI's cwd: two is not a hint, it is a refusal.</summary>
    [Fact]
    public void Sole_target_never_guesses()
    {
        Assert.Null(SoleTarget.PickSoleTarget(Array.Empty<string>()));
        Assert.Equal("a", SoleTarget.PickSoleTarget(new[] { "a" }));
        Assert.Null(SoleTarget.PickSoleTarget(new[] { "a", "b" }));
        Assert.Null(SoleTarget.PickSoleTarget(new[] { "a", "b", "c" }));
    }

    /// <summary>
    /// The panel re-probes only while it is on screen and only while the answer
    /// could change — polling behind a closed tool window is a process every ten
    /// seconds for nothing.
    /// </summary>
    [Fact]
    public void Cli_probe_runs_only_when_visible_and_only_when_the_cli_is_the_problem()
    {
        Assert.True(CliProbe.ShouldProbeCli(Situation.CliMissing, true));
        Assert.True(CliProbe.ShouldProbeCli(Situation.CliOutdated, true));
        Assert.False(CliProbe.ShouldProbeCli(Situation.CliMissing, false));
        Assert.False(CliProbe.ShouldProbeCli(Situation.CliOutdated, false));
        foreach (var s in Enum.GetValues<Situation>())
        {
            if (s is Situation.CliMissing or Situation.CliOutdated) continue;
            Assert.False(CliProbe.ShouldProbeCli(s, true), $"{s.Id()} does not need a probe");
        }
        Assert.Equal(10_000, CliProbe.CliProbeIntervalMs);
    }

    [Fact]
    public void Source_preference_prefers_the_workspace_then_the_user_then_remote()
    {
        Assert.Equal(ReviewSource.Remote, SourcePreference.ResolveDefaultSource(new SourcePreferenceLevels()));
        Assert.Equal(
            ReviewSource.Local,
            SourcePreference.ResolveDefaultSource(new SourcePreferenceLevels("local", "offline")));
        Assert.Equal(
            ReviewSource.Offline,
            SourcePreference.ResolveDefaultSource(new SourcePreferenceLevels(GlobalValue: "offline")));
        // A value nobody defined falls through to the next level, not to a crash.
        Assert.Equal(
            ReviewSource.Offline,
            SourcePreference.ResolveDefaultSource(new SourcePreferenceLevels("nonsense", "offline")));
        Assert.Equal(
            ReviewSource.Remote,
            SourcePreference.ResolveDefaultSource(new SourcePreferenceLevels("nonsense", "")));
    }

    [Fact]
    public void Finish_outcome_reads_the_refreshed_state_not_the_finish_output()
    {
        var pending = new ReviewState(
            Situation.FinishPending,
            Branches: new[]
            {
                new BranchRecord("review-fixes/f", false, true, false, Finish: new BranchFinish("pending", false)),
            });
        Assert.Equal(FinishOutcome.Pending, FinishOutcomeLogic.FinishOutcome(pending, "review-fixes/f"));
        // A different branch, or none at all: nothing to undo, so nothing is promised.
        Assert.Equal(FinishOutcome.NoEdits, FinishOutcomeLogic.FinishOutcome(pending, "other"));
        Assert.Equal(FinishOutcome.NoEdits,
            FinishOutcomeLogic.FinishOutcome(new ReviewState(Situation.NoReview), "review-fixes/f"));
    }

    /// <summary>
    /// A conflict is not a pending finish: offering "undo is available" over a
    /// half-applied finish would be the wrong promise.
    /// </summary>
    [Fact]
    public void Finish_outcome_only_counts_a_pending_record()
    {
        var conflict = new ReviewState(
            Situation.FinishConflict,
            Branches: new[]
            {
                new BranchRecord("review-fixes/f", false, true, false, Finish: new BranchFinish("conflict", false)),
            });
        Assert.Equal(FinishOutcome.NoEdits, FinishOutcomeLogic.FinishOutcome(conflict, "review-fixes/f"));
    }

    [Fact]
    public void Entry_arg_falls_back_to_the_cursor_and_rejects_anything_else()
    {
        var entries = new List<EntryRecord> { new(1, "a"), new(2, "b") };
        Assert.Equal(entries[1], EntryArg.ResolveEntryArg(null, entries, 2));
        Assert.Equal(entries[0], EntryArg.ResolveEntryArg(entries[0], entries, 2));
        // A stray argument resolves to nothing rather than to the first entry.
        Assert.Null(EntryArg.ResolveEntryArg("nope", entries, 1));
        Assert.Null(EntryArg.ResolveEntryArg(7, entries, 1));
        Assert.Null(EntryArg.ResolveEntryArg(null, entries, 9));
        Assert.Null(EntryArg.ResolveEntryArg(null, entries, null));
    }

    [Fact]
    public void Flatten_cli_message_joins_the_non_empty_lines()
    {
        Assert.Equal("a b", CliMessage.FlattenCliMessage("  a \n\n b  \n"));
        Assert.Equal("", CliMessage.FlattenCliMessage("\n  \n"));
        Assert.Equal("a b", CliMessage.FlattenCliMessage("a\r\nb"));
        Assert.Equal("only", CliMessage.FirstCliLine("\n only \n two"));
        Assert.Equal("", CliMessage.FirstCliLine("\n \n"));
    }

    /// <summary>
    /// stderr first, then stdout, then a fallback: the CLI usually already said
    /// something more useful than anything the client could invent.
    /// </summary>
    [Fact]
    public void Cli_error_text_prefers_what_the_cli_said()
    {
        Assert.Equal("err", CliMessage.CliErrorText("err\n", "out", "fallback"));
        Assert.Equal("out", CliMessage.CliErrorText("  \n", "out", "fallback"));
        Assert.Equal("fallback", CliMessage.CliErrorText("", "", "fallback"));
    }

    [Fact]
    public void Install_hints_are_the_npm_commands()
    {
        Assert.Equal("npm install -g git-review-workflow", InstallHint.NpmInstallCmd);
        Assert.Equal("npm install -g git-review-workflow@latest", InstallHint.NpmUpdateCmd);
        Assert.StartsWith("https://github.com/EzeVillo/git-review-workflow", UserCopy.InstallDocsUrl);
    }
}
