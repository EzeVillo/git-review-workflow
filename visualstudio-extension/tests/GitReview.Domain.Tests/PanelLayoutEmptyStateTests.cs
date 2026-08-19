using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutEmptyStateTests
{
    private static IEnumerable<Control> ControlsOf(Block b) =>
        b is Block.Row r ? r.Controls : Array.Empty<Control>();

    [Fact]
    public void Setup_without_a_base_is_five_blocks_with_set_base_primary_and_no_inventory()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewSetup());
        Assert.False(layout.FillsHeight);
        Assert.Equal(5, layout.Blocks.Count);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.InventoryRows);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.ToolsSection);
        // Nothing to start until there is a base to compare against.
        Assert.DoesNotContain(layout.CollectControls(), c => c.Id == ControlId.StartReview);

        var primary = layout.CollectControls().Where(c => c.Emphasis == Emphasis.Primary).ToList();
        Assert.Single(primary);
        Assert.Equal(ControlId.SetBase, primary[0].Id);
        Assert.Equal("Set the base branch", primary[0].Label);
    }

    [Fact]
    public void Ready_no_review_puts_the_inventory_before_start_and_fills_height()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady());
        Assert.True(layout.FillsHeight);

        var inventory = layout.Blocks.ToList().FindIndex(b => b is Block.InventoryRows);
        var startRow = layout.Blocks.ToList().FindIndex(
            b => b is Block.Row r && r.Controls.Any(c => c.Id == ControlId.StartReview));
        Assert.True(inventory >= 0, "the fixture has reviews, so it has an inventory");
        Assert.True(inventory < startRow, "the leftovers are read before the offer to start another");

        Assert.Contains(layout.CollectControls(),
            c => c.Id == ControlId.StartReview && c.Emphasis == Emphasis.Primary);
        Assert.Equal(3, layout.Blocks.Count(b => b is Block.ToolsSection));
    }

    [Fact]
    public void The_start_paragraph_is_ruled_off_from_the_inventory_only_when_there_is_one()
    {
        var withReviews = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady())
            .Blocks.OfType<Block.Paragraph>()
            .First(p => p.Text == "No active review on this branch.");
        Assert.True(withReviews.Separated, "a listed inventory needs the rule under it");

        var withoutReviews = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewEmpty())
            .Blocks.OfType<Block.Paragraph>()
            .First(p => p.Text == "No active review on this branch.");
        Assert.False(withoutReviews.Separated, "with no inventory there is nothing to separate");
    }

    [Fact]
    public void An_empty_repository_shows_no_inventory_heading_at_all()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewEmpty());
        Assert.DoesNotContain(layout.Blocks, b => b is Block.InventoryRows);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.Heading h && h.Text == "Reviews in this repository");
        Assert.Contains(layout.CollectControls(), c => c.Id == ControlId.StartReview);
    }

    /// <summary>
    /// Continue is offered on a saved review that nothing else is holding; the active
    /// one gets Discard only, and the row says why Continue is not there.
    /// </summary>
    [Fact]
    public void Inventory_rows_carry_an_index_and_offer_continue_only_where_it_would_work()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady());
        var rows = layout.Blocks.OfType<Block.InventoryRows>().First().Rows;
        Assert.Equal(2, rows.Count);

        foreach (var row in rows)
        {
            foreach (var c in row.Controls)
                Assert.NotNull(c.Index);
            if (row.Controls.Count == 0)
                Assert.False(string.IsNullOrWhiteSpace(row.HelpTooltip));
        }

        var saved = rows.First(r => r.Name == "review-saved/feature");
        Assert.Equal(new[] { ControlId.ContinueReview, ControlId.DiscardInventory },
            saved.Controls.Select(c => c.Id));
        Assert.True(saved.Controls[0].Enabled);
        Assert.Equal(0, saved.Controls[0].Index);
        Assert.Equal("walk · 2/5", saved.Meta);

        // Each row's controls carry that row's index, not the first one's: this is
        // the whole mechanism by which a click reaches the review it was next to.
        var orphan = rows.First(r => r.Name == "review/other");
        Assert.All(orphan.Controls, c => Assert.Equal(1, c.Index));
    }

    /// <summary>
    /// An active review of another branch is neither resumable nor discardable: it
    /// is a row you read, with a tooltip saying what to do instead of a button that
    /// would refuse.
    /// </summary>
    [Fact]
    public void An_active_review_of_another_branch_is_a_row_with_no_buttons()
    {
        var branches = Porcelain.ParseListPorcelain("branch\treview/other\t0\t0\t0\tstep\t1\t2");
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.NoReview, Config: new EffectiveConfig("main", "origin"), Branches: branches),
            new PanelInputs(false));
        var row = PanelLayoutBuilder.PanelLayout(model)
            .Blocks.OfType<Block.InventoryRows>().First().Rows.Single();

        Assert.Empty(row.Controls);
        Assert.Equal("Still active — switch to this branch to work on it.", row.HelpTooltip);
        Assert.Equal("step · 1/2", row.Meta);
    }

    /// <summary>
    /// A row whose finish is waiting says where the edits are and which button
    /// undoes it, rather than looking like an ordinary leftover branch.
    /// </summary>
    [Fact]
    public void A_row_with_a_pending_finish_explains_itself()
    {
        var branches = Porcelain.ParseListPorcelain(
            "branch\treview/feature/x\t0\t0\t0\twalk\n" +
            "finish\treview/feature/x\tpending\t0");
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.NoReview, Config: new EffectiveConfig("main", "origin"), Branches: branches),
            new PanelInputs(false));
        var row = PanelLayoutBuilder.PanelLayout(model)
            .Blocks.OfType<Block.InventoryRows>().First().Rows.Single();
        Assert.Equal(
            "Finish waiting on review-fixes/feature/x — use Undo above.",
            row.HelpTooltip);
    }

    [Fact]
    public void An_orphan_row_offers_discard_orphan_and_no_continue()
    {
        var branches = Porcelain.ParseListPorcelain("branch\treview-saved/gone\t1\t0\t1");
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.NoReview, Config: new EffectiveConfig("main", "origin"), Branches: branches),
            new PanelInputs(false));
        var row = PanelLayoutBuilder.PanelLayout(model)
            .Blocks.OfType<Block.InventoryRows>().First().Rows.Single();

        Assert.Contains("orphan", row.Badges);
        Assert.Equal("no metadata", row.Meta);
        var continueControl = row.Controls.First(c => c.Id == ControlId.ContinueReview);
        Assert.False(continueControl.Enabled);
        Assert.Equal("This branch has no review metadata — use Discard", continueControl.Tooltip);
        Assert.Equal("Discard orphan", row.Controls.First(c => c.Id == ControlId.DiscardInventory).Label);
    }

    /// <summary>
    /// A saved review of a branch that already has an active one cannot be resumed,
    /// and the row says so rather than offering a button that would fail.
    /// </summary>
    [Fact]
    public void A_saved_review_shadowed_by_an_active_one_cannot_be_continued()
    {
        var branches = Porcelain.ParseListPorcelain(
            "branch\treview/feature\t0\t0\t0\twalk\n" +
            "branch\treview-saved/feature\t1\t0\t0\twalk\t1\t2");
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.NoReview, Config: new EffectiveConfig("main", "origin"), Branches: branches),
            new PanelInputs(false));
        var saved = PanelLayoutBuilder.PanelLayout(model)
            .Blocks.OfType<Block.InventoryRows>().First()
            .Rows.First(r => r.Name == "review-saved/feature");

        var continueControl = saved.Controls.First(c => c.Id == ControlId.ContinueReview);
        Assert.False(continueControl.Enabled);
        Assert.Equal("A review of this branch is already active", continueControl.Tooltip);
    }

    [Fact]
    public void Busy_disables_every_inventory_control_without_removing_it()
    {
        var model = PanelFixtures.NoReviewReady() with { Busy = true };
        var rows = PanelLayoutBuilder.PanelLayout(model)
            .Blocks.OfType<Block.InventoryRows>().First().Rows;
        var controls = rows.SelectMany(r => r.Controls).ToList();
        Assert.NotEmpty(controls);
        Assert.All(controls, c => Assert.False(c.Enabled));
    }

    [Fact]
    public void The_settings_section_names_the_configured_base_and_remote()
    {
        var settings = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady())
            .Blocks.OfType<Block.ToolsSection>().First(s => s.Title == "Settings");
        var paragraphs = settings.NestedBlocks.OfType<Block.Paragraph>().Select(p => p.Text).ToList();
        Assert.Equal(new[] { "Base: main.", "Remote: origin." }, paragraphs);
        var controls = settings.NestedBlocks.SelectMany(ControlsOf).ToList();
        Assert.Equal(new[] { ControlId.SetBase, ControlId.SetRemote }, controls.Select(c => c.Id));
    }
}
