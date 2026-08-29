using Xunit;

namespace GitReview.Domain.Tests;

public class ReviewIntentTests
{
    [Fact]
    public void Intent_to_args_order()
    {
        var intent = new ReviewIntent("feature/x", ReviewLayout.Step, ReviewRange.Delta, ReviewSource.Local);
        Assert.Equal(
            new[] { "--step", "--delta", "--local", "--", "feature/x" },
            ReviewIntentLogic.IntentToArgs(intent, "main"));
    }

    /// <summary>Walk is the default layout and remote the default source: neither has a flag.</summary>
    [Fact]
    public void Walk_remote_full_uses_the_current_branch_and_no_flags()
    {
        var intent = new ReviewIntent(null, ReviewLayout.Walk, ReviewRange.Full, ReviewSource.Remote);
        Assert.Equal(new[] { "--", "main" }, ReviewIntentLogic.IntentToArgs(intent, "main"));
    }

    [Fact]
    public void Whole_offline()
    {
        var intent = new ReviewIntent("f", ReviewLayout.Whole, ReviewRange.Full, ReviewSource.Offline);
        Assert.Equal(new[] { "--no-walk", "--offline", "--", "f" }, ReviewIntentLogic.IntentToArgs(intent, "main"));
    }

    [Fact]
    public void Keys_flag()
    {
        var intent = new ReviewIntent("f", ReviewLayout.Keys, ReviewRange.Full, ReviewSource.Remote);
        Assert.Equal(new[] { "--keys", "--", "f" }, ReviewIntentLogic.IntentToArgs(intent, "main"));
    }

    /// <summary>
    /// Every combination ends with the separator immediately before the branch. A
    /// branch is the one argument that can look like a flag, and this is what keeps
    /// the CLI from reading it as one.
    /// </summary>
    [Fact]
    public void The_branch_is_always_the_last_argument_behind_a_separator()
    {
        foreach (var layout in Enum.GetValues<ReviewLayout>())
        foreach (var range in Enum.GetValues<ReviewRange>())
        foreach (var source in Enum.GetValues<ReviewSource>())
        {
            var args = ReviewIntentLogic.IntentToArgs(
                new ReviewIntent("--not-a-flag", layout, range, source), "main");
            Assert.Equal("--not-a-flag", args[^1]);
            Assert.Equal("--", args[^2]);
            Assert.Single(args, a => a == "--");
        }
    }

    [Fact]
    public void Validate_delta_requires_a_prior_tip()
    {
        var intent = new ReviewIntent(null, ReviewLayout.Whole, ReviewRange.Delta, ReviewSource.Remote);
        var fail = Assert.IsType<IntentValidationResult.Fail>(
            ReviewIntentLogic.ValidateIntent(intent, new IntentValidationContext()));
        Assert.Contains("delta", fail.Reason);
        Assert.IsType<IntentValidationResult.Ok>(
            ReviewIntentLogic.ValidateIntent(
                intent,
                new IntentValidationContext(new DeltaRecord("f", "abc", DeltaOrigin.Remote))));
    }

    /// <summary>A full range never needs a marker, with or without one on file.</summary>
    [Fact]
    public void Validate_full_range_always_passes()
    {
        var intent = new ReviewIntent("f", ReviewLayout.Walk, ReviewRange.Full, ReviewSource.Remote);
        Assert.IsType<IntentValidationResult.Ok>(
            ReviewIntentLogic.ValidateIntent(intent, new IntentValidationContext()));
        Assert.IsType<IntentValidationResult.Ok>(
            ReviewIntentLogic.ValidateIntent(
                intent, new IntentValidationContext(new DeltaRecord("f", "abc", DeltaOrigin.Local))));
    }

    /// <summary>
    /// The draft is of the review that is about to start, so it takes the same origin
    /// and range the wizard resolved — a draft of a different range lists the wrong
    /// files. --force only when the reviewer chose Start over in the picker for a
    /// draft whose review is over: it is the only thing that makes prose disappear,
    /// and this file is not in git.
    /// </summary>
    [Fact]
    public void Draft_argv_matches_the_contract()
    {
        Assert.Equal(
            new[] { "draft", "--porcelain", "--", "feature/x" },
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Remote, ReviewRange.Full, false));
        Assert.Equal(
            new[] { "draft", "--build", "--local", "--delta", "--", "feature/x" },
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Local, ReviewRange.Delta, true));
        Assert.Equal(
            new[] { "draft", "--porcelain", "--offline", "--", "feature/x" },
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Offline, ReviewRange.Full, false));
    }

    /// <summary>
    /// The step that writes the skeleton asks for the `merged` record; the one
    /// that validates and installs does not, because it emits none -- its result
    /// is the row's badge.
    /// </summary>
    [Fact]
    public void Draft_argv_asks_for_the_record_only_where_it_exists()
    {
        Assert.Contains(
            "--porcelain",
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Remote, ReviewRange.Full, false));
        Assert.DoesNotContain(
            "--porcelain",
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Remote, ReviewRange.Full, true));
    }

    [Fact]
    public void Draft_argv_does_not_force_unless_asked()
    {
        foreach (var source in Enum.GetValues<ReviewSource>())
        foreach (var range in Enum.GetValues<ReviewRange>())
        foreach (var build in new[] { true, false })
        {
            var args = ReviewIntentLogic.DraftArgs("feature/x", source, range, build);
            Assert.DoesNotContain("--force", args);
            Assert.Equal("draft", args[0]);
            Assert.Equal("feature/x", args[^1]);
            Assert.Equal("--", args[^2]);
        }
    }

    /// <summary>
    /// Update carries no flag: the verb reconciles by default since it stopped
    /// refusing over an existing file. Start over is the one that carries --force.
    /// </summary>
    [Fact]
    public void Draft_argv_forces_only_when_starting_over()
    {
        Assert.Equal(
            new[] { "draft", "--porcelain", "--", "feature/x" },
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Remote, ReviewRange.Full, false, false));
        Assert.Equal(
            new[] { "draft", "--porcelain", "--force", "--local", "--delta", "--", "feature/x" },
            ReviewIntentLogic.DraftArgs("feature/x", ReviewSource.Local, ReviewRange.Delta, false, true));
    }

    [Fact]
    public void Enum_ids_are_the_wire_names()
    {
        Assert.Equal(new[] { "walk", "keys", "step", "whole" },
            Enum.GetValues<ReviewLayout>().Select(l => l.Id()));
        Assert.Equal(new[] { "full", "delta" },
            Enum.GetValues<ReviewRange>().Select(r => r.Id()));
        Assert.Equal(new[] { "remote", "local", "offline" },
            Enum.GetValues<ReviewSource>().Select(s => s.Id()));
        foreach (var s in Enum.GetValues<ReviewSource>())
            Assert.Equal(s, ReviewSourceExt.Parse(s.Id()));
        Assert.Null(ReviewSourceExt.Parse("nope"));
    }
}
