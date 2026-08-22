using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutFooterTests
{
    private static IEnumerable<Control> ControlsOf(Block b) =>
        b is Block.Row r ? r.Controls : Array.Empty<Control>();

    [Fact]
    public void No_review_ready_ends_with_four_tools_sections()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady());
        var sections = layout.Blocks.OfType<Block.ToolsSection>().ToList();
        Assert.Equal(
            new[] { "Other actions", "Walkthrough", "Settings", "Support" },
            sections.Select(s => s.Title));

        // Compare stayed where it was; init and build moved to the section named
        // after the noun they share with the two authoring guides.
        var other = sections[0].NestedBlocks.SelectMany(ControlsOf).ToList();
        Assert.Equal(new[] { ControlId.CompareReview }, other.Select(c => c.Id));
        Assert.Equal("Compare revisions", other[0].Label);

        var walkthrough = sections[1].NestedBlocks.SelectMany(ControlsOf).ToList();
        Assert.Equal(
            new[] { ControlId.WalkthroughInit, ControlId.WalkthroughBuild },
            walkthrough.Select(c => c.Id));
        Assert.Equal("Walkthrough: Init", walkthrough[0].Label);
        Assert.Equal("Walkthrough: Build", walkthrough[1].Label);
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
