using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutFooterTests
{
    // The walkthrough row counts: the two verbs are ITS buttons, not a loose row
    // above it — see the section's note in the canonical.
    private static IEnumerable<Control> ControlsOf(Block b) => b switch
    {
        Block.Row r => r.Controls,
        Block.WalkthroughRow w => w.Entry.Controls,
        Block.GuideRows g => g.Rows.SelectMany(row => row.Controls),
        _ => Array.Empty<Control>(),
    };

    [Fact]
    public void No_review_ready_ends_with_four_tools_sections()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady());
        var sections = layout.Blocks.OfType<Block.ToolsSection>().ToList();
        Assert.Equal(
            new[] { "Walkthrough", "Compare", "Settings", "Support" },
            sections.Select(s => s.Title));

        // Compare names what it does and goes below the sections that are about
        // the review you are about to do; init and build live in the section named
        // after the noun they share with the two authoring guides — and inside it,
        // in the row whose file they act on.
        var walkthrough = sections[0].NestedBlocks.SelectMany(ControlsOf).ToList();
        Assert.Equal(
            new[]
            {
                ControlId.WalkthroughInit,
                ControlId.WalkthroughBuild,
                ControlId.CopyWalkthroughPrompt,
                ControlId.OpenWalkthrough,
            },
            walkthrough.Select(c => c.Id));
        Assert.Equal("Init", walkthrough[0].Label);
        Assert.Equal("Build", walkthrough[1].Label);

        var compare = sections[1].NestedBlocks.SelectMany(ControlsOf).ToList();
        Assert.Equal(new[] { ControlId.CompareReview }, compare.Select(c => c.Id));
        Assert.Equal("Compare revisions", compare[0].Label);
    }

    /// <summary>
    /// The reading orders you finished with are still about the review you are about
    /// to do; Compare mounts two revisions that have nothing to do with it, so it
    /// sits below them.
    /// </summary>
    [Fact]
    public void Compare_sits_below_the_reading_orders_you_finished_with()
    {
        var sections = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewSpentDraft())
            .Blocks.OfType<Block.ToolsSection>().ToList();
        Assert.Equal(
            new[] { "Walkthrough", "Reading orders you finished with", "Compare", "Settings", "Support" },
            sections.Select(s => s.Title));
    }

    /// <summary>
    /// The two support links are the same control id, told apart only by the link id
    /// the host resolves to a URL — mixing them up sends "Report a bug" to the repo
    /// front page.
    /// </summary>
    [Fact]
    public void The_support_section_carries_both_links_with_their_own_ids()
    {
        var support = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady())
            .Blocks.OfType<Block.ToolsSection>().First(s => s.Title == "Support");
        var controls = support.NestedBlocks.SelectMany(ControlsOf).ToList();

        Assert.Equal(2, controls.Count(c => c.Id == ControlId.OpenSupport));
        Assert.Contains(controls, c =>
            c.Id == ControlId.OpenSupport && c.Label == "Star on GitHub" && c.SupportLinkId == SupportLinks.Star);
        Assert.Contains(controls, c =>
            c.Id == ControlId.OpenSupport && c.Label == "Report a bug" && c.SupportLinkId == SupportLinks.Bug);
        Assert.NotEqual(SupportLinks.Star, SupportLinks.Bug);
    }

    [Fact]
    public void A_review_has_no_tools_sections()
    {
        foreach (var model in new[] { PanelFixtures.ReviewWalk(), PanelFixtures.ReviewStep(), PanelFixtures.ReviewWhole() })
            Assert.DoesNotContain(PanelLayoutBuilder.PanelLayout(model).Blocks, b => b is Block.ToolsSection);
    }

    /// <summary>
    /// A repository with no base configured has nothing to put in Settings, so the
    /// setup screen carries no sections at all rather than an empty one.
    /// </summary>
    [Fact]
    public void The_setup_screen_has_no_sections()
    {
        Assert.DoesNotContain(
            PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewSetup()).Blocks,
            b => b is Block.ToolsSection);
    }

    [Fact]
    public void Busy_disables_the_footer_actions()
    {
        var model = PanelFixtures.NoReviewReady() with { Busy = true };
        var sections = PanelLayoutBuilder.PanelLayout(model).Blocks.OfType<Block.ToolsSection>().ToList();
        var actionable = sections
            .Where(s => s.Title != "Support")
            .SelectMany(s => s.NestedBlocks.SelectMany(ControlsOf))
            .ToList();
        Assert.NotEmpty(actionable);
        Assert.All(actionable, c => Assert.False(c.Enabled));
        // Support links are not mutations: they stay clickable while the CLI runs.
        var support = sections.First(s => s.Title == "Support").NestedBlocks.SelectMany(ControlsOf);
        Assert.All(support, c => Assert.True(c.Enabled));
    }
}
