using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;

/// <summary>
/// The refresh pipeline: version probe → status --porcelain → list/config when
/// needed. It is the sole source of ReviewState for the panel, and it had no test.
/// </summary>
public class ReviewStateManagerTests
{
    private static ReviewStateManager Manager(FakeCliInvoker cli, params string[] roots) =>
        new(cli, () => roots);

    private const string WalkStatus =
        "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t3\t3\t\"src/a.kt\"\t1\n" +
        "entry\t1\tsrc/a.kt\t1\t1\nentry\t2\tsrc/b.kt\t0\t1\nentry\t3\tsrc/c.kt\t0\t0";

    [Fact]
    public async Task An_active_review_is_parsed_into_the_state()
    {
        var cli = new FakeCliInvoker().Answer("status", WalkStatus);
        var state = await Manager(cli, "/repo").RefreshAsync();

        Assert.Equal(Situation.Review, state.Situation);
        Assert.Equal(ReviewMode.Walk, state.State?.Mode);
        Assert.Equal(3, state.EntriesList.Count);
        Assert.Equal(new[] { "--version", "status" }, cli.Verbs);
        Assert.All(cli.Calls, c => Assert.Equal("/repo", c.Cwd));
    }

    /// <summary>
    /// A finish record in the porcelain turns a review into a conflict without a
    /// second invocation — the situation is derived, not asked for.
    /// </summary>
    [Fact]
    public async Task A_finish_record_makes_it_a_conflict()
    {
        var cli = new FakeCliInvoker().Answer("status", WalkStatus + "\nfinish\tconflict\t0");
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.FinishConflict, state.Situation);
        Assert.Equal("conflict", state.Finish?.State);
    }

    /// <summary>
    /// Exit 2 means no review, and only then does the pipeline pay for the inventory
    /// and the config — asking for them on every refresh is two processes per keystroke.
    /// </summary>
    [Fact]
    public async Task No_review_also_reads_the_inventory_and_the_config()
    {
        var cli = new FakeCliInvoker()
            .Fails("status", "no review", exitCode: 2)
            .Answer("list", "branch\treview-saved/feature\t1\t0\t0\twalk\t2\t5")
            .Answer("config", "config\tbase\tmain\nconfig\tremote\torigin\ncandidate\tf\tremote\t1");
        var state = await Manager(cli, "/repo").RefreshAsync();

        Assert.Equal(Situation.NoReview, state.Situation);
        Assert.Single(state.BranchesList);
        Assert.Equal("main", state.Config?.Base);
        Assert.Equal("origin", state.Config?.Remote);
        Assert.Single(state.Candidates!);
        Assert.Equal(new[] { "--version", "status", "list", "config" }, cli.Verbs.OrderByVerb());
    }

    [Fact]
    public async Task A_pending_finish_in_the_inventory_becomes_finish_pending()
    {
        var cli = new FakeCliInvoker()
            .Fails("status", "no review", exitCode: 2)
            .Answer("list", "branch\treview/f\t0\t0\t0\twhole\nfinish\treview/f\tpending\t0")
            .Answer("config", "config\tremote\torigin");
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.FinishPending, state.Situation);
    }

    /// <summary>
    /// A review with no review is still a review to nobody: an unreadable inventory
    /// leaves the situation intact rather than turning into an error screen.
    /// </summary>
    [Fact]
    public async Task An_unreadable_inventory_or_config_still_yields_no_review()
    {
        var cli = new FakeCliInvoker()
            .Fails("status", "no review", exitCode: 2)
            .Fails("list", "boom")
            .Fails("config", "boom");
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.NoReview, state.Situation);
        Assert.Empty(state.BranchesList);
        Assert.Null(state.Config);
    }

    /// <summary>
    /// Exit 3 prints no porcelain at all — parsing it anyway is how the actionable
    /// stderr ("undo the commits with git reset --soft, or abort") used to come out
    /// as "porcelain output has no state record" under a generic error.
    /// </summary>
    [Fact]
    public async Task Out_of_range_keeps_the_clis_own_diagnosis()
    {
        var cli = new FakeCliInvoker()
            .Fails("status", "HEAD moved: undo the commits with git reset --soft, or abort", exitCode: 3);
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.OutOfRange, state.Situation);
        Assert.Contains("git reset --soft", state.Stderr);
        Assert.Null(state.State);
    }

    /// <summary>
    /// Porcelain the parser cannot read is more often a CLI that already explained
    /// itself than a bug in the tokenizer, and the reviewer can act on the former.
    /// </summary>
    [Fact]
    public async Task Unparseable_porcelain_shows_what_the_cli_said_first()
    {
        var withStderr = new FakeCliInvoker()
            .Answer("status", new InvokeResult("garbage", "fatal: the repository is in a bad state", 0));
        var state = await Manager(withStderr, "/repo").RefreshAsync();
        Assert.Equal(Situation.Error, state.Situation);
        Assert.Contains("bad state", state.Stderr);

        // With nothing on stderr, the parser's own message is better than nothing.
        var silent = new FakeCliInvoker().Answer("status", "garbage");
        var fallback = await Manager(silent, "/repo").RefreshAsync();
        Assert.Equal(Situation.Error, fallback.Situation);
        Assert.False(string.IsNullOrWhiteSpace(fallback.Stderr));
    }

    [Fact]
    public async Task A_timeout_is_its_own_error_not_an_empty_review()
    {
        var cli = new FakeCliInvoker()
            .Answer("status", new InvokeResult("", "", null, TimedOut: true));
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.Error, state.Situation);
        Assert.Contains("timed out", state.Stderr);
    }

    [Theory]
    [InlineData("git: 'review' is not a git command.")]
    [InlineData("sh: git-review: not found")]
    [InlineData("spawn git-review ENOENT")]
    public async Task A_missing_cli_is_reported_as_missing_not_as_an_error(string stderr)
    {
        var cli = new FakeCliInvoker().Fails("--version", stderr, exitCode: 127);
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.CliMissing, state.Situation);
        Assert.Equal(stderr, state.Stderr);
        // It never got as far as asking for the status.
        Assert.Equal(new[] { "--version" }, cli.Verbs);
    }

    /// <summary>
    /// A version probe that times out describes a CLI that is there and slow, which is
    /// the opposite of one that is not there: the install screen would send the
    /// reviewer to install what is already installed.
    /// </summary>
    [Fact]
    public async Task A_version_probe_that_times_out_is_not_a_missing_cli()
    {
        var cli = new FakeCliInvoker()
            .Answer("--version", new InvokeResult("", "", null, TimedOut: true));
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.Error, state.Situation);
        Assert.Contains("did not finish in time", state.Stderr);
    }

    /// <summary>
    /// A failure that names nothing is not evidence of anything, and the first
    /// invocation of a startup is the one most likely to produce one. It is retried
    /// before the panel is told anything at all.
    /// </summary>
    [Fact]
    public async Task A_failure_without_evidence_is_retried_before_it_is_believed()
    {
        var cli = new FakeCliInvoker().Fails("--version", "", exitCode: 127);
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.CliMissing, state.Situation);
        Assert.Equal(1 + CliProbe.CliProbeRetries, cli.Verbs.Count(v => v == "--version"));
        // And it never got as far as asking for the status.
        Assert.DoesNotContain("status", cli.Verbs);
    }

    /// <summary>
    /// The other half: with evidence there is nothing to wait for, so the reviewer is
    /// told at once instead of sitting through the retries.
    /// </summary>
    [Fact]
    public async Task Evidence_of_absence_is_answered_on_the_first_probe()
    {
        var cli = new FakeCliInvoker().Fails("--version", "sh: git-review: not found", exitCode: 127);
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.CliMissing, state.Situation);
        Assert.Equal(new[] { "--version" }, cli.Verbs);
    }

    [Fact]
    public async Task A_spawn_failure_is_a_missing_cli_too()
    {
        var cli = new FakeCliInvoker()
            .Answer("--version", new InvokeResult("", "", null, ErrorCode: "Win32Exception"));
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.CliMissing, state.Situation);
    }

    [Fact]
    public async Task A_cli_older_than_the_minimum_stops_before_the_status()
    {
        var cli = new FakeCliInvoker().Answer("--version", "0.5.9\n");
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.CliOutdated, state.Situation);
        Assert.Equal("0.5.9", state.Stderr);
        Assert.Equal(new[] { "--version" }, cli.Verbs);
    }

    /// <summary>
    /// A build that prints its version somewhere else is not an outdated one: the
    /// probe carries on and lets the status decide.
    /// </summary>
    [Fact]
    public async Task A_silent_version_probe_does_not_block_the_refresh()
    {
        var cli = new FakeCliInvoker()
            .Answer("--version", "")
            .Answer("status", WalkStatus);
        var state = await Manager(cli, "/repo").RefreshAsync();
        Assert.Equal(Situation.Review, state.Situation);
    }

    /// <summary>
    /// git review takes one root, like the CLI's cwd. Two is refused with the message
    /// the contract fixes, rather than guessing which one the reviewer meant.
    /// </summary>
    [Fact]
    public async Task More_than_one_root_is_refused_by_name()
    {
        var cli = new FakeCliInvoker();
        var state = await Manager(cli, "/one", "/two").RefreshAsync();
        Assert.Equal(Situation.Error, state.Situation);
        Assert.Contains("multi-root is not supported", state.Stderr);
        Assert.Empty(cli.Calls);
    }

    [Fact]
    public async Task No_root_at_all_asks_for_one()
    {
        var cli = new FakeCliInvoker();
        var state = await Manager(cli).RefreshAsync();
        Assert.Equal(Situation.Error, state.Situation);
        Assert.Equal(UserCopy.NoSoleRoot, state.Stderr);
        Assert.Empty(cli.Calls);
    }

    /// <summary>
    /// Until a refresh has answered, the seed state is a placeholder and not an
    /// answer — drawing it would tell the reviewer the CLI is missing before anyone
    /// has looked.
    /// </summary>
    [Fact]
    public async Task Has_resolved_is_false_until_the_first_refresh_lands()
    {
        var manager = Manager(new FakeCliInvoker().Answer("status", WalkStatus), "/repo");
        Assert.False(manager.HasResolved);
        Assert.Equal(Situation.CliMissing, manager.Current.Situation);
        await manager.RefreshAsync();
        Assert.True(manager.HasResolved);
        Assert.Equal(Situation.Review, manager.Current.Situation);
    }

    [Fact]
    public async Task Subscribers_are_told_about_each_resolved_state()
    {
        var manager = Manager(new FakeCliInvoker().Answer("status", WalkStatus), "/repo");
        var seen = new List<Situation>();
        manager.StateChanged += s => seen.Add(s.Situation);
        await manager.RefreshAsync();
        await manager.RefreshAsync();
        Assert.Equal(new[] { Situation.Review, Situation.Review }, seen);
    }

    /// <summary>
    /// Two refreshes can be in flight (a mutation finishes while a probe is running);
    /// the older one must not publish over the newer, or the panel snaps back to a
    /// state that is already gone.
    /// </summary>
    [Fact]
    public async Task A_slower_earlier_refresh_does_not_overwrite_a_newer_one()
    {
        var gate = new TaskCompletionSource();
        var slow = new GatedCliInvoker(gate.Task, WalkStatus);
        var manager = new ReviewStateManager(slow, () => new[] { "/repo" });

        var first = manager.RefreshAsync();          // blocks inside the version probe
        slow.Release();                               // later refreshes answer immediately
        var second = await manager.RefreshAsync();
        Assert.Equal(Situation.Review, second.Situation);

        gate.SetResult();
        await first;
        Assert.Equal(Situation.Review, manager.Current.Situation);
        Assert.True(manager.HasResolved);
    }

    private sealed class GatedCliInvoker : CliInvoker
    {
        private readonly Task _gate;
        private readonly string _status;
        private bool _released;

        public GatedCliInvoker(Task gate, string status)
        {
            _gate = gate;
            _status = status;
        }

        public void Release() => _released = true;

        public override async Task<InvokeResult> InvokeAsync(
            string verb,
            IReadOnlyList<string> args,
            string cwd,
            bool network = false,
            long? timeoutMs = null,
            CancellationToken cancellationToken = default)
        {
            if (!_released) await _gate.ConfigureAwait(false);
            return verb switch
            {
                "--version" => new InvokeResult(CliVersion.MinCliVersion + "\n", "", 0),
                "status" => new InvokeResult(_status, "", 0),
                _ => new InvokeResult("", "", 0),
            };
        }
    }
}

internal static class VerbOrdering
{
    /// <summary>
    /// list and config are issued together, so their order between themselves is not
    /// part of the contract — everything before them is.
    /// </summary>
    public static IReadOnlyList<string> OrderByVerb(this IReadOnlyList<string> verbs)
    {
        var head = verbs.TakeWhile(v => v is not ("list" or "config")).ToList();
        var tail = verbs.Skip(head.Count).OrderBy(v => v, StringComparer.Ordinal).Reverse().ToList();
        return head.Concat(tail).ToList();
    }
}
