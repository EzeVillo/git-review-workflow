using System.Linq;
using GitReview.Domain;
using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The author's own walkthrough row in the empty state.
///
/// What these pin down is the reason the row exists: a walkthrough is written once,
/// when the PR is finished, and then the PR keeps moving. The row says so without
/// anybody remembering to ask — and says it cautiously, because what the CLI compares
/// on every refresh is cheap and approximate.
/// </summary>
public class PanelLayoutWalkthroughTests
{
    private static GuideRow? Row(PanelModel model) =>
        PanelLayoutBuilder.PanelLayout(model)
            .Blocks
            .OfType<Block.ToolsSection>()
            .SelectMany(s => s.NestedBlocks)
            .OfType<Block.WalkthroughRow>()
            .Select(b => b.Entry)
            .FirstOrDefault();

    private static Control Control(GuideRow row, ControlId id) =>
        row.Controls.First(c => c.Id == id);

    // Init and build are the ROW's buttons: their subject is the file the row
    // names, exactly as Create is each guide's.
    private static string? InitLabel(PanelModel model) =>
        Row(model)?.Controls.FirstOrDefault(c => c.Id == ControlId.WalkthroughInit)?.Label;

    [Fact]
    public void The_row_lives_in_the_walkthrough_section_above_the_guides()
    {
        var section = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewWalkthroughStale())
            .Blocks
            .OfType<Block.ToolsSection>()
            .First(s => s.Title == "Walkthrough");
        // Nothing loose above the row: the section is three rows and no more.
        Assert.Equal(
            new[] { "WalkthroughRow", "GuideRows" },
            section.NestedBlocks.Select(b => b.GetType().Name));
    }

    [Fact]
    public void The_row_is_named_after_the_branch_it_annotates()
    {
        // The section is already called Walkthrough; saying it again in the row
        // added no fact, and the two prefixed buttons said it a third time.
        Assert.StartsWith("feature/checkout", Row(PanelFixtures.NoReviewWalkthroughStale())!.Name);
    }

    [Fact]
    public void The_two_verbs_are_buttons_of_the_row()
    {
        var row = Row(PanelFixtures.NoReviewWalkthroughStale())!;
        Assert.Equal(
            new[] { "Update", "Build", "Copy for agent" },
            row.Controls.Where(c => c.Emphasis != Emphasis.Icon).Select(c => c.Label));
        // And nowhere else in the section: a loose row above would say the word a
        // third time in four centimetres.
        var loose = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewWalkthroughStale())
            .Blocks
            .OfType<Block.ToolsSection>()
            .SelectMany(s => s.NestedBlocks)
            .OfType<Block.Row>()
            .SelectMany(r => r.Controls)
            .Select(c => c.Id)
            .ToList();
        Assert.DoesNotContain(ControlId.WalkthroughInit, loose);
        Assert.DoesNotContain(ControlId.WalkthroughBuild, loose);
    }

    [Fact]
    public void A_stale_walkthrough_suggests_looking_it_does_not_pass_a_verdict()
    {
        // The exact answer is build's; this badge is the cheap half.
        Assert.Equal("may be out of date", Row(PanelFixtures.NoReviewWalkthroughStale())!.Badge);
    }

    [Fact]
    public void The_row_carries_how_much_of_the_reading_order_is_written()
    {
        Assert.Contains("4/6", Row(PanelFixtures.NoReviewWalkthroughStale())!.Name);
    }

    [Fact]
    public void An_absent_walkthrough_leaves_both_row_controls_off()
    {
        var row = Row(PanelFixtures.NoReviewWalkthroughAbsent())!;
        Assert.Equal("none", row.Badge);
        Assert.False(Control(row, ControlId.OpenWalkthrough).Enabled);
        Assert.False(Control(row, ControlId.CopyWalkthroughPrompt).Enabled);
        // And no progress pair: 0/0 is "nothing here", not "finished". Asked of
        // the digits, not of the slash — the row is named after a branch now, and
        // feature/checkout has one of those.
        Assert.DoesNotMatch(@"\d+/\d+", row.Name);
    }

    [Fact]
    public void An_existing_walkthrough_can_be_opened_and_handed_to_an_agent()
    {
        var row = Row(PanelFixtures.NoReviewWalkthroughStale())!;
        var open = Control(row, ControlId.OpenWalkthrough);
        Assert.True(open.Enabled);
        // Open points at the path the CLI reported, never one rebuilt here.
        Assert.Equal("/repo/.review/walkthrough.md", open.Tooltip);
        Assert.True(Control(row, ControlId.CopyWalkthroughPrompt).Enabled);
    }

    [Fact]
    public void The_init_button_says_update_over_a_walkthrough_that_exists()
    {
        // The same verb creates and updates; "Init" over a file full of prose
        // promised what that verb precisely no longer does.
        Assert.Equal("Update", InitLabel(PanelFixtures.NoReviewWalkthroughStale()));
        Assert.Equal("Init", InitLabel(PanelFixtures.NoReviewWalkthroughAbsent()));
    }

    [Fact]
    public void With_no_record_from_the_cli_the_row_is_still_drawn_in_unknown()
    {
        // Init and build hang off this row, so a row that disappears takes the two
        // verbs with it. Unknown is what the CLI itself calls "cannot be told", so
        // nothing is invented: no badge, no path, both file controls off, and the
        // two verbs still there.
        var row = Row(PanelFixtures.NoReviewNoWalkthroughRecord())!;
        Assert.Equal("Walkthrough", row.Name);
        Assert.Equal("state unknown", row.Badge);
        Assert.False(Control(row, ControlId.OpenWalkthrough).Enabled);
        Assert.False(Control(row, ControlId.CopyWalkthroughPrompt).Enabled);
        Assert.True(Control(row, ControlId.WalkthroughInit).Enabled);
        Assert.True(Control(row, ControlId.WalkthroughBuild).Enabled);
        Assert.Equal("Init", InitLabel(PanelFixtures.NoReviewNoWalkthroughRecord()));
    }

    [Fact]
    public void The_row_controls_are_not_product_actions()
    {
        // Their subject is the row: without it they have no subject at all, so they
        // stay out of the action matrix and out of the .vsct.
        var row = Row(PanelFixtures.NoReviewWalkthroughStale())!;
        Assert.NotNull(Control(row, ControlId.OpenWalkthrough).Index);
        Assert.NotNull(Control(row, ControlId.CopyWalkthroughPrompt).Index);
    }

    [Fact]
    public void A_walkthrough_that_came_in_with_a_merge_is_not_stale()
    {
        // Nothing about it fell behind: it belongs to a range that closed. The two
        // have to stay apart or the panel offers reconciling another PR's prose.
        var row = Row(PanelFixtures.NoReviewWalkthroughSuperseded())!;
        Assert.Equal("from a merged PR", row.Badge);
        Assert.NotEqual("may be out of date", row.Badge);
    }

    [Fact]
    public void The_button_says_start_over_on_a_superseded_walkthrough()
    {
        // The CLI starts over on its own there, so the button says what will
        // happen instead of promising a reconciliation that does not occur.
        Assert.Equal("Start over", InitLabel(PanelFixtures.NoReviewWalkthroughSuperseded()));
    }

    [Fact]
    public void A_superseded_walkthrough_can_still_be_opened_and_copied()
    {
        // The file is right there; what changed is whose it is.
        var row = Row(PanelFixtures.NoReviewWalkthroughSuperseded())!;
        Assert.True(Control(row, ControlId.OpenWalkthrough).Enabled);
        Assert.True(Control(row, ControlId.CopyWalkthroughPrompt).Enabled);
    }

    [Fact]
    public void The_row_carries_the_branch_it_annotates()
    {
        // It is WHAT THE ROW IS CALLED in the panel, so losing it here means a row
        // that says "Walkthrough" under a section already called that.
        var r = ConfigPorcelain.ParseConfigPorcelain("walkthrough\tstale\t/repo/.review/walkthrough.md\t1\t2\tfeature/x").Walkthrough;
        Assert.Equal("feature/x", r!.Branch);
    }

    [Fact]
    public void A_detached_head_omits_the_branch_and_the_row_stays()
    {
        // The CLI OMITS the field, never blanks it: the file and both verbs work
        // there and the only thing without an answer is the name.
        var r = ConfigPorcelain.ParseConfigPorcelain("walkthrough\tstale\t/repo/.review/walkthrough.md\t1\t2").Walkthrough;
        Assert.Equal(WalkthroughState.Stale, r!.State);
        Assert.Null(r.Branch);
    }
}
