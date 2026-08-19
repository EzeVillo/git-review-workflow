using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutSkeletonTests
{
    [Fact]
    public void The_skeleton_keeps_the_silhouette_with_every_control_disabled()
    {
        var layout = PanelLayoutBuilder.PanelLayout(
            PanelFixtures.ReviewWalk(why: new PanelWhy(WhyState.Loading)), loading: true);

        Assert.Contains(layout.Blocks, b => b is Block.IdentityBar { IsSkeleton: true });
        Assert.Contains(layout.Blocks, b => b is Block.Why { State: WhyState.Loading });
        Assert.Contains(layout.Blocks, b => b is Block.EntryHead { IsSkeleton: true });
        Assert.Contains(layout.Blocks, b => b is Block.EntryTitle { IsSkeleton: true });

        var body = layout.CollectControls()
            .Where(c => c.Id is ControlId.OpenEntry or ControlId.OpenChange or ControlId.Prev or ControlId.Next)
            .ToList();
        Assert.NotEmpty(body);
        Assert.All(body, c => Assert.False(c.Enabled));
    }

    /// <summary>
    /// A skeleton is a placeholder, so its title actions are placeholders too — a
    /// live Finish over a state still being read is a click on stale information.
    /// </summary>
    [Fact]
    public void The_skeleton_disables_the_title_bar_without_emptying_it()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk(), loading: true);
        Assert.NotEmpty(layout.TitleActions);
        Assert.All(layout.TitleActions, t => Assert.False(t.Enabled));
        // The same situation, resolved, has them live.
        var resolved = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk());
        Assert.All(resolved.TitleActions, t => Assert.True(t.Enabled));
    }

    /// <summary>The identity bar keeps the name but drops the cursor it cannot know yet.</summary>
    [Fact]
    public void The_skeleton_identity_bar_holds_no_position()
    {
        var bar = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk(), loading: true)
            .Blocks.OfType<Block.IdentityBar>().First();
        Assert.True(bar.IsSkeleton);
        Assert.Null(bar.Position);
        Assert.Null(bar.Total);
        Assert.Equal("feature", bar.Name);
    }

    [Fact]
    public void A_step_skeleton_has_no_why_block()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewStep(), loading: true);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.Why);
        Assert.Contains(layout.Blocks, b => b is Block.IdentityBar { IsSkeleton: true });
    }

    /// <summary>
    /// Only a review can be drawn as a silhouette of itself. The other situations
    /// have no shape to hold, so loading renders them as they are.
    /// </summary>
    [Fact]
    public void Only_readable_situations_get_a_skeleton()
    {
        foreach (var model in new[] { PanelFixtures.NoReviewReady(), PanelFixtures.CliMissing(), PanelFixtures.FinishPending() })
        {
            var loading = PanelLayoutBuilder.PanelLayout(model, loading: true);
            var resolved = PanelLayoutBuilder.PanelLayout(model);
            Assert.Equal(resolved.Blocks.Count, loading.Blocks.Count);
            Assert.DoesNotContain(loading.Blocks, b => b is Block.IdentityBar { IsSkeleton: true });
        }
    }

    /// <summary>
    /// Whole is a file list, not a cursor: there is no silhouette to draw, so it
    /// renders its inventory rather than a fake entry.
    /// </summary>
    [Fact]
    public void Whole_is_never_drawn_as_a_skeleton()
    {
        var loading = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole(), loading: true);
        Assert.Contains(loading.Blocks, b => b is Block.FileRows);
        Assert.DoesNotContain(loading.Blocks, b => b is Block.EntryHead);
    }

    /// <summary>A conflict has no nav row, and the skeleton must not invent one.</summary>
    [Fact]
    public void A_locked_skeleton_still_has_no_navigation()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishConflict(), loading: true);
        Assert.DoesNotContain(layout.CollectControls(), c => c.Id is ControlId.Next or ControlId.Prev);
    }
}
