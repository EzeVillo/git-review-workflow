using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// Table-driven argv parity for every action (SC-003 / FR-008), port of the jetbrains
/// ActionArgvParityTest. Full-sequence equality, never containment: containment is
/// what let a start argv drop its <c>--</c> separator and still pass, and that
/// separator is the only thing standing between a branch named like a flag and the
/// CLI reading it as one.
/// </summary>
public class ActionArgvParityTests
{
    private static void AssertArgv(string verb, string[] args, ActionArgv actual, bool network = false)
    {
        Assert.Equal(verb, actual.Verb);
        Assert.Equal(args, actual.Args);
        Assert.Equal(network, actual.Network);
    }

    [Fact]
    public void Start_argv_keeps_flag_order_and_the_separator()
    {
        var intent = new ReviewIntent(
            "feature/checkout", ReviewLayout.Step, ReviewRange.Delta, ReviewSource.Local);
        var a = ActionArgvMap.ActionToArgv("startReview", new ActionParams.Start(intent, "main"));
        AssertArgv("start", new[] { "--step", "--delta", "--local", "--", "feature/checkout" }, a, network: true);
    }

    /// <summary>A start always fetches, whatever the layout, so it always takes the network budget.</summary>
    [Fact]
    public void Start_is_always_a_network_action()
    {
        foreach (var source in Enum.GetValues<ReviewSource>())
        {
            var intent = new ReviewIntent("f", ReviewLayout.Walk, ReviewRange.Full, source);
            Assert.True(ActionArgvMap.ActionToArgv("startReview", new ActionParams.Start(intent, "main")).Network);
        }
    }

    [Fact]
    public void Continue_save_abort_and_navigation()
    {
        AssertArgv("continue", new[] { "feature/x" },
            ActionArgvMap.ActionToArgv("continueReview", new ActionParams.Continue("feature/x")));
        AssertArgv("save", Array.Empty<string>(), ActionArgvMap.ActionToArgv("saveReview"));
        AssertArgv("abort", Array.Empty<string>(), ActionArgvMap.ActionToArgv("abortReview"));
        AssertArgv("next", Array.Empty<string>(), ActionArgvMap.ActionToArgv("next"));
        AssertArgv("prev", Array.Empty<string>(), ActionArgvMap.ActionToArgv("prev"));
    }

    [Fact]
    public void Finish_family()
    {
        AssertArgv("finish", Array.Empty<string>(),
            ActionArgvMap.ActionToArgv("finishReview", new ActionParams.FinishOnto(false)));
        AssertArgv("finish", new[] { "--onto-source" },
            ActionArgvMap.ActionToArgv("finishReview", new ActionParams.FinishOnto(true)));
        AssertArgv("finish", new[] { "--abort" },
            ActionArgvMap.ActionToArgv("undoFinish", new ActionParams.UndoFinish(false)));
        AssertArgv("finish", new[] { "--abort", "--force" },
            ActionArgvMap.ActionToArgv("undoFinish", new ActionParams.UndoFinish(true)));
        AssertArgv("finish", new[] { "--resume" },
            ActionArgvMap.ActionToArgv("resumeFinish", new ActionParams.ResumeFinish(false)));
        AssertArgv("finish", new[] { "--resume", "--onto-source" },
            ActionArgvMap.ActionToArgv("resumeFinish", new ActionParams.ResumeFinish(true)));
    }

    /// <summary>
    /// A finish with no params is the plain one: --onto-source is opt-in, and getting
    /// that default backwards stages the edits on the PR branch itself.
    /// </summary>
    [Fact]
    public void Finish_without_params_does_not_go_onto_the_source()
    {
        AssertArgv("finish", Array.Empty<string>(), ActionArgvMap.ActionToArgv("finishReview"));
        AssertArgv("finish", new[] { "--abort" }, ActionArgvMap.ActionToArgv("undoFinish"));
        AssertArgv("finish", new[] { "--resume" }, ActionArgvMap.ActionToArgv("resumeFinish"));
    }

    [Fact]
    public void Housekeeping_argv()
    {
        static ActionArgv Clean(HousekeepingKind kind, string? src = null) =>
            ActionArgvMap.ActionToArgv("cleanReview",
                new ActionParams.Housekeeping(new HousekeepingAction(kind, src)));
        static ActionArgv Forget(HousekeepingKind kind, string? src = null) =>
            ActionArgvMap.ActionToArgv("forgetReview",
                new ActionParams.Housekeeping(new HousekeepingAction(kind, src)));

        AssertArgv("clean", new[] { "f" }, Clean(HousekeepingKind.CleanOne, "f"));
        AssertArgv("clean", new[] { "--keep-fixes", "f" }, Clean(HousekeepingKind.CleanKeepFixes, "f"));
        AssertArgv("clean", Array.Empty<string>(), Clean(HousekeepingKind.CleanAll));
        AssertArgv("forget", new[] { "--saved", "f" }, Forget(HousekeepingKind.ForgetSavedOne, "f"));
        AssertArgv("forget", new[] { "--saved", "--all" }, Forget(HousekeepingKind.ForgetSavedAll));
        AssertArgv("forget", new[] { "--delta", "f" }, Forget(HousekeepingKind.ForgetDeltaOne, "f"));
        AssertArgv("forget", new[] { "--delta", "--all" }, Forget(HousekeepingKind.ForgetDeltaAll));
        AssertArgv("forget", new[] { "--delta", "--stale" },
            Forget(HousekeepingKind.ForgetDeltaStale), network: true);
    }

    /// <summary>discardInventory routes through the same table as clean/forget.</summary>
    [Fact]
    public void Discard_inventory_shares_the_housekeeping_table()
    {
        AssertArgv("forget", new[] { "--saved", "f" },
            ActionArgvMap.ActionToArgv("discardInventory",
                new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.ForgetSavedOne, "f"))));
        AssertArgv("clean", new[] { "f" },
            ActionArgvMap.ActionToArgv("discardInventory",
                new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.CleanOne, "f"))));
    }

    [Fact]
    public void Config_walkthrough_preview_and_compare()
    {
        AssertArgv("config", new[] { "base", "--", "main" },
            ActionArgvMap.ActionToArgv("setBase", new ActionParams.SetConfig("base", "main")));
        AssertArgv("config", new[] { "remote", "--", "upstream" },
            ActionArgvMap.ActionToArgv("setRemote", new ActionParams.SetConfig("remote", "upstream")));
        AssertArgv("walkthrough", new[] { "init" },
            ActionArgvMap.ActionToArgv("walkthroughInit", new ActionParams.WalkthroughInit(false)));
        AssertArgv("walkthrough", new[] { "init", "--force" },
            ActionArgvMap.ActionToArgv("walkthroughInit", new ActionParams.WalkthroughInit(true)));
        AssertArgv("walkthrough", new[] { "build" }, ActionArgvMap.ActionToArgv("walkthroughBuild"));
        AssertArgv("preview", Array.Empty<string>(), ActionArgvMap.ActionToArgv("previewEdits"));
        AssertArgv("preview", new[] { "--stat" }, ActionArgvMap.ActionToArgv("previewEditsStat"));
        AssertArgv("compare", new[] { "--step", "--", "a", "b" },
            ActionArgvMap.ActionToArgv("compareReview",
                new ActionParams.Compare(new[] { "--step" }, "a", "b")));
        AssertArgv("compare", new[] { "--", "a", "b" },
            ActionArgvMap.ActionToArgv("compareReview",
                new ActionParams.Compare(Array.Empty<string>(), "a", "b")));
    }

    /// <summary>
    /// The key/remote/config values are always behind <c>--</c>: a branch called
    /// <c>--force</c> is a legal git ref, and the whole point of the separator is
    /// that it stops being a flag.
    /// </summary>
    [Fact]
    public void Values_that_could_read_as_flags_stay_behind_the_separator()
    {
        var setBase = ActionArgvMap.ActionToArgv("setBase", new ActionParams.SetConfig("base", "--force"));
        Assert.Equal(new[] { "base", "--", "--force" }, setBase.Args);

        var intent = new ReviewIntent("--force", ReviewLayout.Walk, ReviewRange.Full, ReviewSource.Remote);
        var start = ActionArgvMap.ActionToArgv("startReview", new ActionParams.Start(intent, "main"));
        Assert.Equal(new[] { "--", "--force" }, start.Args);

        var compare = ActionArgvMap.ActionToArgv("compareReview",
            new ActionParams.Compare(Array.Empty<string>(), "--force", "b"));
        Assert.Equal(new[] { "--", "--force", "b" }, compare.Args);
    }

    /// <summary>The panel-only actions run no CLI, and an empty verb is how the runner knows.</summary>
    [Fact]
    public void Client_side_actions_carry_no_verb()
    {
        foreach (var action in new[] { "openEntry", "openChange", "showWhy", "goToEntry", "refresh", "installCli", "showCliLog" })
        {
            var argv = ActionArgvMap.ActionToArgv(action);
            Assert.Equal("", argv.Verb);
            Assert.Empty(argv.Args);
            Assert.False(argv.Network);
        }
    }

    /// <summary>
    /// An action that needs params and gets none is a bug in the caller, not a
    /// command to run with defaults: <c>continue</c> with no source would resume
    /// whichever review the CLI picks.
    /// </summary>
    [Fact]
    public void Actions_that_need_params_refuse_without_them()
    {
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("startReview"));
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("continueReview"));
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("compareReview"));
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("setBase"));
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("setRemote"));
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("cleanReview"));
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("forgetReview"));
        // And so does one nobody defined.
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("startReviewNow"));
    }

    /// <summary>
    /// Only the one action that reaches the remote is marked as network; anything
    /// else marked so would take the five-minute budget for a local operation.
    /// </summary>
    [Fact]
    public void Only_start_and_forget_stale_are_network()
    {
        var network = new List<string>();
        foreach (var action in ActionArgvMap.ProductActions)
        {
            var argv = ActionArgvMap.ActionToArgv(action, ParamsFor(action));
            if (argv.Network) network.Add(action);
        }
        Assert.Equal(new[] { "startReview" }, network);
        Assert.True(ActionArgvMap.ActionToArgv("forgetReview",
            new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.ForgetDeltaStale))).Network);
    }

    private static ActionParams? ParamsFor(string action) => action switch
    {
        "startReview" => new ActionParams.Start(
            new ReviewIntent("f", ReviewLayout.Walk, ReviewRange.Full, ReviewSource.Remote), "main"),
        "continueReview" => new ActionParams.Continue("f"),
        "compareReview" => new ActionParams.Compare(Array.Empty<string>(), "a", "b"),
        "cleanReview" or "discardInventory" or "forgetReview" =>
            new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.CleanAll)),
        "setBase" or "setRemote" => new ActionParams.SetConfig("base", "main"),
        _ => null,
    };

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
}
