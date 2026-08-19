using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The five title-bar actions. In this host they are a .vsct ToolWindowToolbar whose
/// visibility is answered from <see cref="PanelLayout.TitleActions"/>, so what this
/// projection says is literally which buttons the shell draws.
/// </summary>
public class TitleBarActionsTests
{
    [Fact]
    public void A_review_has_the_full_title_bar_in_order()
    {
        var actions = PanelLayoutBuilder.TitleBarActions(PanelFixtures.ReviewWalk());
        Assert.Equal(
            new[]
            {
                ControlId.Refresh, ControlId.FinishReview, ControlId.SaveReview,
                ControlId.AbortReview, ControlId.PreviewEdits,
            },
            actions.Select(a => a.Id));
        Assert.Equal(
            new[] { "Refresh", "Finish", "Save", "Cancel", "Preview edits" },
            actions.Select(a => a.Label));
        Assert.All(actions, a => Assert.True(a.Enabled));
    }

    /// <summary>
    /// A compare review is read-only: there is nothing to finish, so the button is
    /// gone rather than present and failing.
    /// </summary>
    [Fact]
    public void Readonly_omits_finish_but_keeps_save_and_cancel()
    {
        var ids = PanelLayoutBuilder.TitleBarActions(PanelFixtures.ReviewWalk() with { Readonly = true })
            .Select(a => a.Id).ToList();
        Assert.DoesNotContain(ControlId.FinishReview, ids);
        Assert.Contains(ControlId.SaveReview, ids);
        Assert.Contains(ControlId.AbortReview, ids);
        Assert.Contains(ControlId.PreviewEdits, ids);
    }

    /// <summary>
    /// While the CLI runs, Refresh is the only thing left: every other title action
    /// mutates, and a second mutation is discarded by the lock anyway.
    /// </summary>
    [Fact]
    public void Busy_keeps_only_refresh()
    {
        Assert.Equal(
            new[] { ControlId.Refresh },
            PanelLayoutBuilder.TitleBarActions(PanelFixtures.ReviewWalk(busy: true)).Select(a => a.Id));
    }

    [Fact]
    public void Finish_conflict_has_refresh_cancel_and_preview_but_not_finish_or_save()
    {
        Assert.Equal(
            new[] { ControlId.Refresh, ControlId.AbortReview, ControlId.PreviewEdits },
            PanelLayoutBuilder.TitleBarActions(PanelFixtures.FinishConflict()).Select(a => a.Id));
    }

    [Fact]
    public void Situations_with_no_review_keep_only_refresh()
    {
        foreach (var model in new[]
                 {
                     PanelFixtures.NoReviewReady(), PanelFixtures.NoReviewSetup(),
                     PanelFixtures.FinishPending(), PanelFixtures.OutOfRange(),
                     PanelFixtures.Error(), PanelFixtures.CliMissing(), PanelFixtures.CliOutdated(),
                 })
        {
            Assert.Equal(
                new[] { ControlId.Refresh },
                PanelLayoutBuilder.TitleBarActions(model).Select(a => a.Id));
        }
    }

    /// <summary>
    /// The title actions reach CollectControls, which is what makes the invariants
    /// (and the contract's title-only filter) see them at all.
    /// </summary>
    [Fact]
    public void Title_actions_are_part_of_the_layout()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk());
        Assert.Equal(PanelLayoutBuilder.TitleBarActions(PanelFixtures.ReviewWalk()).Count, layout.TitleActions.Count);
        foreach (var t in layout.TitleActions)
            Assert.Contains(layout.CollectControls(), c => c.Id == t.Id && c.Label == t.Label);
    }

    /// <summary>Cancel and Save confirm; Refresh and Preview do not.</summary>
    [Fact]
    public void The_destructive_title_actions_confirm()
    {
        Assert.True(PanelLayoutBuilder.RequiresConfirmation(ControlId.AbortReview));
        Assert.True(PanelLayoutBuilder.RequiresConfirmation(ControlId.SaveReview));
        Assert.False(PanelLayoutBuilder.RequiresConfirmation(ControlId.Refresh));
        Assert.False(PanelLayoutBuilder.RequiresConfirmation(ControlId.PreviewEdits));
    }
}
