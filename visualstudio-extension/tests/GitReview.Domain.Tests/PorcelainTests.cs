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
        Assert.True(CliVersion.IsOutdated("0.6.0"));
        Assert.False(CliVersion.IsOutdated("0.7.0"));
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
        // 012: creating green ends the wizard. No open, no wait, no build here —
        // all of that moved to the panel, over a state that outlives the IDE.
        var s = DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Create);
        Assert.IsType<DraftFlowState.Create>(s);
        s = DraftFlow.AdvanceDraftFlow(s, new DraftFlowEvent.Created(true));
        Assert.IsType<DraftFlowState.Done>(s);
        // Terminal.
        Assert.IsType<DraftFlowState.Done>(
            DraftFlow.AdvanceDraftFlow(s, new DraftFlowEvent.Created(false)));
    }

    [Fact]
    public void Draft_flow_resume_creates_nothing()
    {
        // The file exists; recreating it would overwrite what the reviewer wrote,
        // which is what --force is there to ask for by hand.
        Assert.IsType<DraftFlowState.Done>(
            DraftFlow.InitialDraftFlowState(LayoutOffers.DraftStep.Resume));
    }

    [Fact]
    public void Draft_flow_failure_goes_back_with_the_reason()
    {
        var s = DraftFlow.AdvanceDraftFlow(
            DraftFlowState.Create.Instance,
            new DraftFlowEvent.Created(false, "a draft already exists; use --force"));
        var back = Assert.IsType<DraftFlowState.Back>(s);
        Assert.Equal("a draft already exists; use --force", back.Error);

        var bare = Assert.IsType<DraftFlowState.Back>(
            DraftFlow.AdvanceDraftFlow(DraftFlowState.Create.Instance, new DraftFlowEvent.Created(false)));
        Assert.Null(bare.Error);
    }

    [Fact]
    public void Draft_records_parse_their_seven_fields()
    {
        var stdout =
            "config\tremote\torigin\n" +
            "draft\tfeature/checkout\t/repo/.git/review-walkthrough/feature/checkout.md\t3\t9\tlocal\tdelta\n";
        var draft = Assert.Single(ConfigPorcelain.ParseConfigPorcelain(stdout).Drafts!);
        Assert.Equal("feature/checkout", draft.Src);
        Assert.Equal("/repo/.git/review-walkthrough/feature/checkout.md", draft.Path);
        Assert.Equal(3, draft.Annotated);
        Assert.Equal(9, draft.Total);
        Assert.Equal(DraftSource.Local, draft.Source);
        Assert.Equal(DraftRange.Delta, draft.Range);
    }

    [Fact]
    public void An_unknown_source_or_range_reads_as_unknown()
    {
        // What the CLI emits when the instruction block was deleted by hand, and
        // the only honest reading of a value a newer CLI might add: in both cases
        // this client cannot replicate the flags.
        var stdout = "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t2\tunknown\tunknown\n";
        var draft = Assert.Single(ConfigPorcelain.ParseConfigPorcelain(stdout).Drafts!);
        Assert.Equal(DraftSource.Unknown, draft.Source);
        Assert.Equal(DraftRange.Unknown, draft.Range);
    }

    [Fact]
    public void A_malformed_draft_record_is_ignored_whole()
    {
        // Half a progress pair would be worse than none: a total that is not an
        // integer cannot be drawn as "3/N" without inventing the N.
        var stdout =
            "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\tmany\t2\tremote\tfull\n" +
            "draft\t\t/repo/.git/review-walkthrough/feature/y.md\t0\t2\tremote\tfull\n" +
            "draft\tfeature/z\n" +
            "draft\tfeature/ok\t/repo/.git/review-walkthrough/feature/ok.md\t1\t2\tremote\tfull\n";
        var draft = Assert.Single(ConfigPorcelain.ParseConfigPorcelain(stdout).Drafts!);
        Assert.Equal("feature/ok", draft.Src);
    }

    [Fact]
    public void The_draft_record_of_status_carries_the_path_without_touching_the_flag()
    {
        var stdout =
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t1\t1\tsrc/a.cs\t0\n" +
            "entry\t1\tsrc/a.cs\t0\t1\n" +
            "draft\t/repo/.git/review-walkthrough/feature.md\n";
        var parsed = Porcelain.ParsePorcelain(stdout);
        Assert.True(parsed.Draft);
        Assert.Equal("/repo/.git/review-walkthrough/feature.md", parsed.DraftPath);

        // An older CLI emits the bare record, and that cannot turn the mark off.
        var bare = Porcelain.ParsePorcelain(
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t1\t1\tsrc/a.cs\t0\n" +
            "entry\t1\tsrc/a.cs\t0\t1\n" +
            "draft\n");
        Assert.True(bare.Draft);
        Assert.Null(bare.DraftPath);
    }

    [Fact]
    public void The_three_steps_of_validate_and_start_carry_the_same_flags()
    {
        // They come from the source/range fields of the `draft` record, not from
        // the defaults: with the defaults a draft made with --delta or --local
        // covers a different set of paths and --build dies on drift, every time.
        Assert.Equal(
            new[] { "draft", "--build", "--local", "--delta", "--", "feature/x" },
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Local, ReviewRange.Delta, build: true));
        Assert.Equal(
            new[] { "--porcelain", "--local", "--delta", "--", "feature/x" },
            ReviewIntentLogic.DraftConfigArgs("feature/x", ReviewSource.Local, ReviewRange.Delta));
        Assert.Equal(
            new[] { "--delta", "--local", "--", "feature/x" },
            ReviewIntentLogic.IntentToArgs(
                new ReviewIntent("feature/x", ReviewLayout.Walk, ReviewRange.Delta, ReviewSource.Local),
                "feature/x"));
    }

    [Fact]
    public void Discard_names_one_branch_and_never_all_or_saved()
    {
        Assert.Equal(new[] { "--draft", "--", "feature/x" }, ReviewIntentLogic.ForgetDraftArgs("feature/x"));
        var argv = ActionArgvMap.ActionToArgv("forgetDraft", new ActionParams.ForgetDraft("feature/x"));
        Assert.Equal("forget", argv.Verb);
        Assert.Equal(new[] { "--draft", "--", "feature/x" }, argv.Args);
        Assert.DoesNotContain("--all", argv.Args);
        Assert.DoesNotContain("--saved", argv.Args);
    }

    [Fact]
    public void The_agent_prompt_is_the_canonical_text_with_this_rows_path()
    {
        Assert.Equal(
            "Fill in the reading order at /repo/.git/review-walkthrough/feature/x.md. " +
            "The instructions are inside the file, in the comment at the top. " +
            "Do not change the file list or the numbering rules.",
            UserCopy.DraftAgentPrompt("/repo/.git/review-walkthrough/feature/x.md"));
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
