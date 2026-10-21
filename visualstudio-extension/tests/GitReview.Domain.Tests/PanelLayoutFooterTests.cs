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
    /// The support links are the same control id, told apart only by the link id
    /// the host resolves to a URL — mixing them up sends "Report a bug" to the repo
    /// front page.
    /// </summary>
    [Fact]
    public void The_support_section_stacks_four_links_with_their_own_ids()
    {
        var support = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady())
            .Blocks.OfType<Block.ToolsSection>().First(s => s.Title == "Support");
        var controls = support.NestedBlocks.SelectMany(ControlsOf).ToList();

        Assert.Equal(new[] { 1, 1, 1, 1 }, support.NestedBlocks.Select(b => ControlsOf(b).Count()));
        Assert.Equal(new[] { "Star on GitHub", "Report a bug", "Sponsor", "Contact" }, controls.Select(c => c.Label));
        Assert.Equal(new[] { SupportLinks.Star, SupportLinks.Bug, SupportLinks.Sponsor, SupportLinks.Contact },
            controls.Select(c => c.SupportLinkId));
        Assert.All(controls, c => Assert.Equal(ControlId.OpenSupport, c.Id));
        Assert.Equal("https://github.com/sponsors/EzeVillo", SupportLinks.UrlFor(SupportLinks.Sponsor));
        Assert.Equal("mailto:ezevillodev@gmail.com", SupportLinks.UrlFor(SupportLinks.Contact));
        Assert.Null(SupportLinks.UrlFor("unknown"));
    }

    [Fact]
    public void A_review_has_no_tools_sections()
    {
        foreach (var model in new[] { PanelFixtures.ReviewWalk(), PanelFixtures.ReviewStep(), PanelFixtures.ReviewWhole() })
            Assert.DoesNotContain(PanelLayoutBuilder.PanelLayout(model).Blocks, b => b is Block.ToolsSection);
    }

    /// <summary>
    /// Compare is independent of the PR base; it is the only setup section.
    /// </summary>
    [Fact]
    public void The_setup_screen_offers_only_the_independent_compare_section()
    {
        var section = Assert.Single(PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewSetup()).Blocks.OfType<Block.ToolsSection>());
        Assert.Equal("Compare", section.Title);
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
