using System.Collections.Generic;
using System.Linq;
using GitReview.Domain;
using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The authoring-guide rows of the empty state.
///
/// What these pin down is the rule the block is built on: both rows are always drawn
/// and the state changes the enabled, never the presence — except Discard, which the
/// shared row does not have at all, because removing a tracked file is `git rm` plus a
/// commit and not this button's decision.
/// </summary>
public class PanelLayoutGuidesTests
{
    private static IReadOnlyList<GuideRow> Rows(PanelModel model) =>
        PanelLayoutBuilder.PanelLayout(model)
            .Blocks
            .OfType<Block.ToolsSection>()
            .SelectMany(s => s.NestedBlocks)
            .OfType<Block.GuideRows>()
            .SelectMany(b => b.Rows)
            .ToList();

    private static Control Control(GuideRow row, ControlId id) =>
        row.Controls.First(c => c.Id == id);

    [Fact]
    public void The_guide_rows_live_in_the_walkthrough_section_in_the_clis_order()
    {
        var walkthrough = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewGuides())
            .Blocks
            .OfType<Block.ToolsSection>()
            .First(s => s.Title == "Walkthrough");
        var rows = walkthrough.NestedBlocks.OfType<Block.GuideRows>().SelectMany(b => b.Rows).ToList();
        Assert.Equal(new[] { "Repository guide", "Your guide" }, rows.Select(r => r.Name));
    }

    [Fact]
    public void A_guide_in_force_can_be_opened_but_not_created()
    {
        var team = Rows(PanelFixtures.NoReviewGuides())[0];
        Assert.Equal("in force", team.Badge);
        Assert.True(Control(team, ControlId.OpenGuide).Enabled);
        Assert.False(Control(team, ControlId.CreateGuide).Enabled);
    }

    [Fact]
    public void An_absent_guide_can_be_created_but_not_opened()
    {
        var own = Rows(PanelFixtures.NoReviewGuides())[1];
        Assert.Equal("absent", own.Badge);
        Assert.False(Control(own, ControlId.OpenGuide).Enabled);
        Assert.True(Control(own, ControlId.CreateGuide).Enabled);
        // Nothing to discard, but the control is still drawn: off says why in its
        // tooltip, and a row that changes shape with its state stops lining up.
        Assert.False(Control(own, ControlId.DiscardGuide).Enabled);
    }

    [Fact]
    public void An_empty_guide_is_opened_and_discarded_not_created()
    {
        // Empty is not absent: the file is there, so the offer is to fill it.
        var own = Rows(PanelFixtures.NoReviewGuideEmpty())[1];
        Assert.Equal("empty", own.Badge);
        Assert.True(Control(own, ControlId.OpenGuide).Enabled);
        Assert.False(Control(own, ControlId.CreateGuide).Enabled);
        Assert.True(Control(own, ControlId.DiscardGuide).Enabled);
    }

    [Fact]
    public void Only_the_reviewers_row_offers_discard()
    {
        // The shared guide is tracked: removing it is git rm plus a commit, a decision
        // about what goes into the PR. The CLI refuses --delete --team from its side.
        var rows = Rows(PanelFixtures.NoReviewGuides());
        Assert.DoesNotContain(rows[0].Controls, c => c.Id == ControlId.DiscardGuide);
        Assert.Contains(rows[1].Controls, c => c.Id == ControlId.DiscardGuide);
    }

    [Fact]
    public void Both_rows_carry_the_same_controls_whatever_their_state()
    {
        var a = Rows(PanelFixtures.NoReviewGuides());
        var b = Rows(PanelFixtures.NoReviewGuideEmpty());
        Assert.Equal(a[0].Controls.Select(c => c.Id), b[0].Controls.Select(c => c.Id));
        Assert.Equal(a[1].Controls.Select(c => c.Id), b[1].Controls.Select(c => c.Id));
    }

    [Fact]
    public void Every_guide_control_carries_its_row_index()
    {
        // The index is the only thing the panel sends back; the host re-resolves the
        // row against its own state before invoking anything.
        var rows = Rows(PanelFixtures.NoReviewGuides());
        for (var i = 0; i < rows.Count; i++)
        {
            foreach (var c in rows[i].Controls)
            {
                Assert.Equal(i, c.Index);
            }
        }
    }

    [Fact]
    public void Open_points_at_the_path_the_cli_reported()
    {
        var team = Rows(PanelFixtures.NoReviewGuides())[0];
        Assert.Equal("/repo/.review/walkthrough-guide.md", Control(team, ControlId.OpenGuide).Tooltip);
    }

    [Fact]
    public void A_busy_panel_disables_what_mutates_and_leaves_open_alone()
    {
        // Opening reads; creating and discarding invoke the CLI.
        var own = Rows(PanelFixtures.NoReviewGuideEmpty() with { Busy = true })[1];
        Assert.True(Control(own, ControlId.OpenGuide).Enabled);
        Assert.False(Control(own, ControlId.DiscardGuide).Enabled);
    }

    [Fact]
    public void A_review_has_no_tools_section_at_all()
    {
        // Everything hanging off `walkthrough` — the author's two verbs and the two
        // authoring guides — belongs to whoever is standing on THEIR OWN PR, and in
        // here you are standing on somebody else's.
        foreach (var model in new[] { PanelFixtures.ReviewWalk(), PanelFixtures.ReviewStep(), PanelFixtures.ReviewWhole() })
        {
            Assert.DoesNotContain(
                PanelLayoutBuilder.PanelLayout(model).Blocks,
                b => b is Block.ToolsSection);
        }
    }

    [Fact]
    public void No_guide_records_means_no_block_at_all()
    {
        // The degradation against a CLI that does not know the record: the rows
        // disappear and Init/Build stay where they are.
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady());
        Assert.Contains(layout.Blocks.OfType<Block.ToolsSection>(), s => s.Title == "Walkthrough");
        Assert.Empty(Rows(PanelFixtures.NoReviewReady()));
    }

    [Fact]
    public void The_guide_argv_never_carries_force_and_delete_never_carries_team()
    {
        // Overwriting hand-written prose with an empty file is not something a flag
        // should be able to do, and the shared guide is not removed by this client.
        Assert.Equal(new[] { "guide" }, ReviewIntentLogic.CreateGuideArgs(false));
        Assert.Equal(new[] { "guide", "--team" }, ReviewIntentLogic.CreateGuideArgs(true));
        Assert.Equal(new[] { "guide", "--delete" }, ReviewIntentLogic.DeleteGuideArgs());
        Assert.DoesNotContain("--force", ReviewIntentLogic.CreateGuideArgs(true));
        Assert.DoesNotContain("--team", ReviewIntentLogic.DeleteGuideArgs());
    }

    [Fact]
    public void The_guide_argv_hangs_off_the_walkthrough_verb()
    {
        var create = ActionArgvMap.ActionToArgv("createGuide", new ActionParams.CreateGuide(true));
        Assert.Equal("walkthrough", create.Verb);
        Assert.Equal(new[] { "guide", "--team" }, create.Args);
        var del = ActionArgvMap.ActionToArgv("deleteGuide", new ActionParams.DeleteGuide());
        Assert.Equal("walkthrough", del.Verb);
        Assert.Equal(new[] { "guide", "--delete" }, del.Args);
    }
}
