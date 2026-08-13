using Xunit;

namespace GitReview.Domain.Tests;

public class PorcelainTests
{
    [Fact]
    public void Parse_walk_status()
    {
        var text =
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t2\t2\t\"src/a.kt\"\t1\n" +
            "entry\t1\tsrc/a.kt\t1\t1\n" +
            "entry\t2\tsrc/b.kt\t0\t0\n" +
            "draft";
        var r = Porcelain.ParsePorcelain(text);
        Assert.Equal(ReviewMode.Walk, r.State.Mode);
        Assert.Equal(2, r.Entries.Count);
        Assert.True(r.Draft);
        Assert.IsType<PathRef>(r.Entries[0].Id);
    }

    [Fact]
    public void Situation_for_exit_codes()
    {
        Assert.Equal(Situation.Review, SituationIds.ForExitCode(0));
        Assert.Equal(Situation.NoReview, SituationIds.ForExitCode(2));
        Assert.Equal(Situation.OutOfRange, SituationIds.ForExitCode(3));
        Assert.Equal(Situation.Error, SituationIds.ForExitCode(1));
        Assert.Equal(Situation.FinishConflict, SituationIds.For(0, true, false));
        Assert.Equal(Situation.FinishPending, SituationIds.For(2, false, true));
    }

    [Fact]
    public void Unquote_octal_path()
    {
        // "a\303\251b" style path
        var raw = "\"a\\303\\251b\"";
        var display = Unquote.UnquotePath(raw);
        Assert.Equal("aéb", display);
    }

    [Fact]
    public void Version_compare()
    {
        Assert.True(CliVersion.IsOutdated("0.5.0"));
        Assert.False(CliVersion.IsOutdated("0.6.0"));
        Assert.False(CliVersion.IsOutdated("1.0.0"));
        Assert.True(CliVersion.IsOutdated("not-a-version"));
    }

    [Fact]
    public void Action_argv_start()
    {
        var intent = new ReviewIntent("feat", ReviewLayout.Step, ReviewRange.Full, ReviewSource.Remote);
        var argv = ActionArgvMap.ActionToArgv("startReview", new ActionParams.Start(intent, "main"));
        Assert.Equal("start", argv.Verb);
        Assert.True(argv.Network);
        Assert.Contains("--step", argv.Args);
        Assert.Contains("feat", argv.Args);
    }

    [Fact]
    public void Name_status_rename()
    {
        var output = "R100\0old.kt\0new.kt\0A\0added.kt\0";
        var changes = NameStatus.ParseNameStatus(output);
        Assert.Equal(2, changes.Count);
        Assert.Equal("new.kt", changes[0].Path);
        Assert.Equal("old.kt", changes[0].Before);
        Assert.Null(changes[1].Before);
    }

    [Fact]
    public void Draft_flow_create_path()
    {
        var s = DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Create);
        s = DraftFlow.AdvanceDraftFlow(s, new DraftFlowEvent.Created(true));
        Assert.IsType<DraftFlowState.Open>(s);
        s = DraftFlow.AdvanceDraftFlow(s, DraftFlowEvent.Opened.Instance);
        Assert.IsType<DraftFlowState.Wait>(s);
        s = DraftFlow.AdvanceDraftFlow(s, DraftFlowEvent.Continue.Instance);
        Assert.IsType<DraftFlowState.Build>(s);
        s = DraftFlow.AdvanceDraftFlow(s, new DraftFlowEvent.Built(true));
        Assert.IsType<DraftFlowState.Reload>(s);
        s = DraftFlow.AdvanceDraftFlow(s, new DraftFlowEvent.Offers(new[]
        {
            new ReadingOffer(OfferId.Walk, OfferRank.Recommended),
        }));
        var done = Assert.IsType<DraftFlowState.Done>(s);
        Assert.Equal(ReviewLayout.Walk, done.Layout);
    }

    [Fact]
    public void Resolve_command_windows_dispatcher()
    {
        var r = ResolveCommand.Resolve("status", new[] { "--porcelain" }, "/usr/bin/git-review", "win32");
        Assert.Equal("sh", r.Command);
        Assert.Equal("/usr/bin/git-review", r.Args[0]);
        Assert.Equal("status", r.Args[1]);
    }
}
