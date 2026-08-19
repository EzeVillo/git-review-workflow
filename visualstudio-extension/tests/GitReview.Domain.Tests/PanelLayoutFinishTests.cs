using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutFinishTests
{
    [Fact]
    public void Finish_pending_banner_has_clean_primary_and_undo_finish()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishPending());
        var banner = layout.Blocks.OfType<Block.Banner>().First();
        Assert.StartsWith("Finished. Your edits are staged on", banner.Paragraphs[0]);

        var controls = banner.ControlsRow.Controls;
        Assert.Equal(ControlId.CleanReview, controls[0].Id);
        Assert.Equal(Emphasis.Primary, controls[0].Emphasis);
        Assert.Equal("Clean", controls[0].Label);
        Assert.Equal(ControlId.UndoFinish, controls[1].Id);
        Assert.Equal("Undo finish", controls[1].Label);
    }

    /// <summary>
    /// The banner names the branch the edits actually landed on, which is the branch
    /// itself for a finish with --onto-source and review-fixes/ otherwise. Sending
    /// someone to the wrong branch to commit is how work gets lost.
    /// </summary>
    [Fact]
    public void The_banner_names_where_the_edits_went()
    {
        static string FirstParagraph(bool onto)
        {
            var branches = new[]
            {
                new BranchRecord("review/feature/x", false, true, false, Finish: new BranchFinish("pending", onto)),
            };
            var model = PanelModelBuilder.BuildPanelModel(
                new ReviewState(Situation.FinishPending, Branches: branches), new PanelInputs(false));
            return PanelLayoutBuilder.PanelLayout(model).Blocks.OfType<Block.Banner>().First().Paragraphs[0];
        }

        Assert.Equal("Finished. Your edits are staged on review-fixes/feature/x.", FirstParagraph(false));
        Assert.Equal("Finished. Your edits are staged on feature/x.", FirstParagraph(true));
    }

    [Fact]
    public void The_banner_says_how_to_undo_and_how_to_stop_being_able_to()
    {
        var banner = PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishPending())
            .Blocks.OfType<Block.Banner>().First();
        Assert.Contains("git review finish --abort", banner.Paragraphs[1]);
        Assert.Contains("clean --keep-fixes", banner.Paragraphs[1]);
    }

    [Fact]
    public void Busy_disables_the_pending_banner_controls()
    {
        var model = PanelFixtures.FinishPending() with { Busy = true };
        var controls = PanelLayoutBuilder.PanelLayout(model)
            .Blocks.OfType<Block.Banner>().First().ControlsRow.Controls;
        Assert.All(controls, c => Assert.False(c.Enabled));
    }

    [Fact]
    public void Finish_conflict_banner_comes_before_the_notes_and_there_is_no_nav()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishConflict());
        var types = layout.Blocks.Select(b => b.GetType().Name).ToList();
        var bar = types.IndexOf(nameof(Block.IdentityBar));
        var banner = types.IndexOf(nameof(Block.Banner));
        var note = types.IndexOf(nameof(Block.Note));
        Assert.True(banner > bar);
        Assert.True(note < 0 || banner < note);

        // Navigation is locked: resolving a conflict is not a place to walk away from.
        Assert.DoesNotContain(layout.CollectControls(),
            c => c.Id == ControlId.Next || c.Id == ControlId.Prev);

        var row = layout.Blocks.OfType<Block.Banner>().First().ControlsRow;
        Assert.Equal(new[] { ControlId.UndoFinish, ControlId.ResumeFinish }, row.Controls.Select(c => c.Id));
        Assert.Equal("Undo", row.Controls[0].Label);
        Assert.Equal("Continue", row.Controls[1].Label);
    }

    /// <summary>
    /// A conflict is still a readable review, so the entry and its why stay on
    /// screen — the point of the situation is to read what you were editing.
    /// </summary>
    [Fact]
    public void Finish_conflict_keeps_the_entry_readable()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishConflict());
        Assert.Contains(layout.Blocks, b => b is Block.EntryHead);
        Assert.Contains(layout.Blocks, b => b is Block.Why);
        Assert.Contains(layout.CollectControls(), c => c.Id == ControlId.OpenEntry);
        Assert.Contains(layout.CollectControls(), c => c.Id == ControlId.OpenChange);
    }

    [Fact]
    public void Finish_conflict_title_bar_drops_finish_and_save()
    {
        var ids = PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishConflict())
            .TitleActions.Select(t => t.Id).ToList();
        Assert.Equal(
            new[] { ControlId.Refresh, ControlId.AbortReview, ControlId.PreviewEdits },
            ids);
    }
}
