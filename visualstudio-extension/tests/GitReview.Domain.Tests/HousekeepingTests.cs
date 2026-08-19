using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The one place in this client that composes commands which delete branches and
/// refs. It had no test at all: swapping <c>clean</c> for <c>forget</c> across every
/// kind, or dropping the <c>--keep-fixes</c> that is the difference between keeping
/// the reviewer's edits and throwing them away, passed the whole suite.
/// </summary>
public class HousekeepingTests
{
    /// <summary>
    /// Exhaustive on purpose: the verb is derived from the enum member's *name*
    /// (<c>Kind.ToString().StartsWith("Clean")</c>), so a rename that looks like
    /// pure tidying silently reroutes a destructive command.
    /// </summary>
    [Theory]
    [InlineData(HousekeepingKind.CleanOne, "clean")]
    [InlineData(HousekeepingKind.CleanKeepFixes, "clean")]
    [InlineData(HousekeepingKind.CleanAll, "clean")]
    [InlineData(HousekeepingKind.ForgetSavedOne, "forget")]
    [InlineData(HousekeepingKind.ForgetSavedAll, "forget")]
    [InlineData(HousekeepingKind.ForgetDeltaOne, "forget")]
    [InlineData(HousekeepingKind.ForgetDeltaAll, "forget")]
    [InlineData(HousekeepingKind.ForgetDeltaStale, "forget")]
    public void Verb_for_every_kind(HousekeepingKind kind, string verb)
    {
        Assert.Equal(verb, HousekeepingLogic.VerbForHousekeeping(new HousekeepingAction(kind, "f")));
    }

    [Fact]
    public void Args_for_every_kind()
    {
        static IReadOnlyList<string> A(HousekeepingKind kind, string? src = null) =>
            HousekeepingLogic.ArgsForHousekeeping(new HousekeepingAction(kind, src));

        Assert.Equal(new[] { "f" }, A(HousekeepingKind.CleanOne, "f"));
        Assert.Equal(new[] { "--keep-fixes", "f" }, A(HousekeepingKind.CleanKeepFixes, "f"));
        Assert.Empty(A(HousekeepingKind.CleanAll));
        Assert.Equal(new[] { "--saved", "f" }, A(HousekeepingKind.ForgetSavedOne, "f"));
        Assert.Equal(new[] { "--saved", "--all" }, A(HousekeepingKind.ForgetSavedAll));
        Assert.Equal(new[] { "--delta", "f" }, A(HousekeepingKind.ForgetDeltaOne, "f"));
        Assert.Equal(new[] { "--delta", "--all" }, A(HousekeepingKind.ForgetDeltaAll));
        Assert.Equal(new[] { "--delta", "--stale" }, A(HousekeepingKind.ForgetDeltaStale));
    }

    /// <summary>
    /// A per-branch action with no branch would run as the sweeping one
    /// (<c>clean</c> with no source cleans everything), so it refuses instead.
    /// </summary>
    [Theory]
    [InlineData(HousekeepingKind.CleanOne)]
    [InlineData(HousekeepingKind.CleanKeepFixes)]
    [InlineData(HousekeepingKind.ForgetSavedOne)]
    [InlineData(HousekeepingKind.ForgetDeltaOne)]
    public void One_branch_kinds_refuse_without_a_source(HousekeepingKind kind)
    {
        Assert.Throws<ArgumentException>(
            () => HousekeepingLogic.ArgsForHousekeeping(new HousekeepingAction(kind)));
        Assert.Throws<ArgumentException>(
            () => HousekeepingLogic.ArgsForHousekeeping(new HousekeepingAction(kind, "")));
    }

    /// <summary>Only --stale has to reach the remote to know what is stale.</summary>
    [Fact]
    public void Only_forget_delta_stale_needs_the_network()
    {
        foreach (var kind in Enum.GetValues<HousekeepingKind>())
        {
            var needs = HousekeepingLogic.HousekeepingNeedsNetwork(new HousekeepingAction(kind, "f"));
            Assert.Equal(kind == HousekeepingKind.ForgetDeltaStale, needs);
        }
    }

    [Fact]
    public void Source_from_review_name_strips_every_namespace()
    {
        Assert.Equal("feature/x", HousekeepingLogic.SourceFromReviewName("review-saved/feature/x"));
        Assert.Equal("feature/x", HousekeepingLogic.SourceFromReviewName("review/feature/x"));
        Assert.Equal("feature/x", HousekeepingLogic.SourceFromReviewName("review-fixes/feature/x"));
        Assert.Equal("feature/x", HousekeepingLogic.SourceFromReviewName("feature/x"));
    }

    [Fact]
    public void Pending_finish_info_comes_from_the_branch_record()
    {
        var state = new ReviewState(
            Situation.FinishPending,
            Branches: new[]
            {
                new BranchRecord("review/other", false, false, false),
                new BranchRecord("review/feature/x", false, true, false,
                    Finish: new BranchFinish("pending", true)),
            });
        var info = HousekeepingLogic.PendingFinishInfo(state);
        Assert.NotNull(info);
        Assert.Equal("feature/x", info!.Value.Source);
        Assert.True(info.Value.Onto);
        Assert.Equal("feature/x", HousekeepingLogic.PendingFinishSource(state));
    }

    [Fact]
    public void Pending_finish_info_is_null_outside_that_situation()
    {
        var branches = new[]
        {
            new BranchRecord("review/f", false, true, false, Finish: new BranchFinish("pending", false)),
        };
        Assert.Null(HousekeepingLogic.PendingFinishInfo(new ReviewState(Situation.Review, Branches: branches)));
        // Right situation, but a conflict is not a pending finish.
        var conflict = new[]
        {
            new BranchRecord("review/f", false, true, false, Finish: new BranchFinish("conflict", false)),
        };
        Assert.Null(HousekeepingLogic.PendingFinishInfo(new ReviewState(Situation.FinishPending, Branches: conflict)));
        Assert.Null(HousekeepingLogic.PendingFinishInfo(new ReviewState(Situation.FinishPending)));
    }

    /// <summary>
    /// Every confirmation names what it deletes and what it leaves alone; the button
    /// is what the reviewer reads last before it happens.
    /// </summary>
    [Fact]
    public void Confirm_copy_for_every_kind_says_what_goes()
    {
        foreach (var kind in Enum.GetValues<HousekeepingKind>())
        {
            var copy = HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(kind, "feature/x"));
            Assert.False(string.IsNullOrWhiteSpace(copy.Title), $"{kind} has no title");
            Assert.False(string.IsNullOrWhiteSpace(copy.Detail), $"{kind} has no detail");
            Assert.False(string.IsNullOrWhiteSpace(copy.Button), $"{kind} has no button");
            Assert.EndsWith("?", copy.Title);
        }
    }

    [Fact]
    public void Confirm_copy_stays_aligned_with_the_other_clients()
    {
        var clean = HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(HousekeepingKind.CleanOne, "feature/x"));
        Assert.Equal("Clean leftover review branches for feature/x?", clean.Title);
        Assert.Equal("Clean", clean.Button);
        Assert.Contains("Does not touch delta markers.", clean.Detail);

        var discard = HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(HousekeepingKind.ForgetSavedOne, "feature/x"));
        Assert.Equal("Discard the saved review of feature/x?", discard.Title);
        Assert.Equal("Discard", discard.Button);

        Assert.Equal("Clean All",
            HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(HousekeepingKind.CleanAll)).Button);
        Assert.Equal("Discard All Saved",
            HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(HousekeepingKind.ForgetSavedAll)).Button);
        Assert.Equal("Forget Stale",
            HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(HousekeepingKind.ForgetDeltaStale)).Button);
    }

    /// <summary>
    /// The one confirmation whose text depends on where the finish landed: with
    /// --onto-source the edits are on the branch itself, not on review-fixes/.
    /// </summary>
    [Fact]
    public void Keep_fixes_copy_names_where_the_edits_actually_are()
    {
        var separate = HousekeepingLogic.ConfirmCopyFor(
            new HousekeepingAction(HousekeepingKind.CleanKeepFixes, "feature/x", Onto: false));
        Assert.Contains("Your staged edits stay on review-fixes/feature/x", separate.Detail);

        var onto = HousekeepingLogic.ConfirmCopyFor(
            new HousekeepingAction(HousekeepingKind.CleanKeepFixes, "feature/x", Onto: true));
        Assert.Contains("Your staged edits stay on feature/x", onto.Detail);
        Assert.DoesNotContain("review-fixes/feature/x", onto.Detail);
    }
}
