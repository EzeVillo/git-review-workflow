using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The rules the layout cannot break. They are checked on the way in, which means a
/// violation is an exception on the render path rather than a red test — which is
/// exactly why they need one here. Two of them (an inventory control without an
/// index, a nested tools section) were missing from this port entirely and nothing
/// noticed, because nothing asked.
/// </summary>
public class PanelLayoutInvariantsTests
{
    private static Control Ctrl(
        ControlId id, string? label, Emphasis emphasis, int? index = null) =>
        new(id, label, label ?? id.Wire(), emphasis, index: index);

    [Fact]
    public void Icon_control_requires_an_accessible_name()
    {
        var ex = Assert.Throws<ArgumentException>(
            () => new Control(ControlId.Prev, null, "", Emphasis.Icon));
        Assert.Contains("accessibleName", ex.Message);
    }

    [Fact]
    public void Null_label_requires_icon_emphasis()
    {
        Assert.Throws<ArgumentException>(
            () => new Control(ControlId.Next, null, "Next entry", Emphasis.Secondary));
        Assert.Throws<ArgumentException>(
            () => new Control(ControlId.Next, null, "Next entry", Emphasis.Primary));
        // The legal shape: no label, icon emphasis, and a name to read out.
        var ok = new Control(ControlId.Next, null, "Next entry", Emphasis.Icon);
        Assert.Equal("Next entry", ok.AccessibleName);
    }

    [Fact]
    public void Row_rejects_zero_or_three_controls()
    {
        Assert.Throws<ArgumentException>(() => new Block.Row(Array.Empty<Control>()));
        var c = Ctrl(ControlId.SetBase, "A", Emphasis.Secondary);
        Assert.Throws<ArgumentException>(() => new Block.Row(new[] { c, c, c }));
        // One or two is the whole range the panel lays out.
        Assert.Single(new Block.Row(new[] { c }).Controls);
        Assert.Equal(2, new Block.Row(new[] { c, c }).Controls.Count);
    }

    [Fact]
    public void At_most_one_primary_per_situation()
    {
        var primary = Ctrl(ControlId.StartReview, "A", Emphasis.Primary);
        var otherPrimary = Ctrl(ControlId.SetBase, "B", Emphasis.Primary);
        var ex = Assert.Throws<ArgumentException>(() => new PanelLayout(
            Situation.NoReview,
            new Block[] { new Block.Row(new[] { primary }), new Block.Row(new[] { otherPrimary }) },
            Array.Empty<Control>()));
        Assert.Contains("PRIMARY", ex.Message);
    }

    /// <summary>The count is over the whole layout, nested sections included.</summary>
    [Fact]
    public void The_primary_count_sees_through_tools_sections()
    {
        var primary = Ctrl(ControlId.StartReview, "A", Emphasis.Primary);
        var otherPrimary = Ctrl(ControlId.SetBase, "B", Emphasis.Primary);
        Assert.Throws<ArgumentException>(() => new PanelLayout(
            Situation.NoReview,
            new Block[]
            {
                new Block.Row(new[] { primary }),
                new Block.ToolsSection("Settings", new Block[] { new Block.Row(new[] { otherPrimary }) }),
            },
            Array.Empty<Control>()));
    }

    /// <summary>
    /// The rule the panel relies on to route a click back to the row it came from: an
    /// index identifies a row of the inventory, and nothing else.
    /// </summary>
    [Fact]
    public void Index_is_allowed_only_on_inventory_row_controls()
    {
        var indexed = Ctrl(ControlId.ContinueReview, "Resume", Emphasis.Secondary, index: 0);
        var row = new InventoryRow("review-saved/feature", new[] { "saved" }, "walk [1/3]", new[] { indexed });

        // Hosted by an InventoryRows block: legal, and it survives being nested in a
        // ToolsSection, which is where the inventory actually lives.
        new PanelLayout(
            Situation.NoReview,
            new Block[] { new Block.ToolsSection("Reviews", new Block[] { new Block.InventoryRows(new[] { row }) }) },
            Array.Empty<Control>());

        // The same control anywhere else is not: a plain row, or a title action.
        Assert.Throws<ArgumentException>(() => new PanelLayout(
            Situation.NoReview, new Block[] { new Block.Row(new[] { indexed }) }, Array.Empty<Control>()));
        Assert.Throws<ArgumentException>(() => new PanelLayout(
            Situation.NoReview, Array.Empty<Block>(), new[] { indexed }));

        // FileRows carries its position on the row (FileRow.Index), never on a
        // control, so having one in the layout does not license an indexed control.
        Assert.Throws<ArgumentException>(() => new PanelLayout(
            Situation.Review,
            new Block[]
            {
                new Block.FileRows(new[] { new FileRow("src/a.kt", 0, false) }),
                new Block.Row(new[] { indexed }),
            },
            Array.Empty<Control>()));
    }

    /// <summary>
    /// The forward half of the same rule, and the one this port was missing: a
    /// control on an inventory row with no index reaches the dispatcher with none,
    /// which drops it into the "which review?" picker instead of acting on the row
    /// the reviewer clicked.
    /// </summary>
    [Fact]
    public void Inventory_controls_must_carry_an_index()
    {
        var ex = Assert.Throws<ArgumentException>(() => new InventoryRow(
            "review/feature",
            Array.Empty<string>(),
            "walk [1/3]",
            new[] { Ctrl(ControlId.ContinueReview, "Resume", Emphasis.Secondary) }));
        Assert.Contains("must carry an index", ex.Message);

        // A row with no controls at all is the read-only kind, and legal.
        var help = new InventoryRow("review/other", Array.Empty<string>(), "step", Array.Empty<Control>(), "Still active");
        Assert.Empty(help.Controls);
    }

    /// <summary>
    /// A section is a flat group of rows under a title; nesting one would render a
    /// heading no client draws and give the same control two homes in CollectControls.
    /// </summary>
    [Fact]
    public void Tools_sections_do_not_nest()
    {
        var inner = new Block.ToolsSection("Inner", Array.Empty<Block>());
        Assert.Throws<ArgumentException>(() => new Block.ToolsSection("Outer", new Block[] { inner }));

        var banner = new Block.Banner(
            new[] { "text" },
            new Block.Row(new[] { Ctrl(ControlId.UndoFinish, "Undo", Emphasis.Secondary) }));
        Assert.Throws<ArgumentException>(() => new Block.ToolsSection("Outer", new Block[] { banner }));

        // Rows and paragraphs are what it is for.
        var ok = new Block.ToolsSection("Settings", new Block[]
        {
            new Block.Paragraph("Base: main."),
            new Block.Row(new[] { Ctrl(ControlId.SetBase, "Change the base branch", Emphasis.Secondary) }),
        });
        Assert.Equal(2, ok.NestedBlocks.Count);
    }

    /// <summary>
    /// Every control the layout holds has to be reachable, wherever it sits: a
    /// control CollectControls does not see is one the invariants above never check
    /// and the host never wires up.
    /// </summary>
    [Fact]
    public void Collect_controls_reaches_every_nesting_the_panel_uses()
    {
        var row = Ctrl(ControlId.SetBase, "row", Emphasis.Secondary);
        var banner = Ctrl(ControlId.UndoFinish, "banner", Emphasis.Secondary);
        var code = Ctrl(ControlId.CopyCliInstall, "code", Emphasis.Secondary);
        var empty = Ctrl(ControlId.OutOfRangeHelp, "empty", Emphasis.Secondary);
        var nested = Ctrl(ControlId.CompareReview, "nested", Emphasis.Secondary);
        var inventory = Ctrl(ControlId.DiscardInventory, "inventory", Emphasis.Secondary, index: 0);
        var title = Ctrl(ControlId.Refresh, "title", Emphasis.Secondary);

        var layout = new PanelLayout(
            Situation.NoReview,
            new Block[]
            {
                new Block.Row(new[] { row }),
                new Block.Banner(new[] { "p" }, new Block.Row(new[] { banner })),
                new Block.CodeCommand("npm i", code),
                new Block.EmptyMessage("nothing here", empty),
                new Block.ToolsSection("Other", new Block[]
                {
                    new Block.Row(new[] { nested }),
                    new Block.InventoryRows(new[]
                    {
                        new InventoryRow("review-saved/f", Array.Empty<string>(), "walk", new[] { inventory }),
                    }),
                }),
            },
            new[] { title });

        Assert.Equal(
            new[] { "row", "banner", "code", "empty", "nested", "inventory", "title" },
            layout.CollectControls().Select(c => c.Label));
    }

    [Fact]
    public void Emphasis_and_control_ids_are_the_wire_names()
    {
        Assert.Equal(new[] { "primary", "secondary", "link", "icon" },
            Enum.GetValues<Emphasis>().Select(e => e.Id()));
        // 32 ids: 27 body plus the 5 title-bar ones. The body count grew by the
        // draft block's four and the guide block's three — controls of a ROW, not
        // product actions: the canonical's actions: matrix is still 26 for this
        // client.
        Assert.Equal(32, Enum.GetValues<ControlId>().Length);
        Assert.Equal(32, Enum.GetValues<ControlId>().Select(id => id.Wire()).Distinct().Count());
    }

    /// <summary>
    /// A confirmation is what stands between a click and a branch being deleted, so
    /// which ids need one is fixed here as well as in the canonical contract.
    /// </summary>
    [Fact]
    public void The_destructive_controls_all_require_confirmation()
    {
        var confirming = new[]
        {
            ControlId.StartReview, ControlId.ContinueReview, ControlId.DiscardInventory,
            ControlId.CleanReview, ControlId.UndoFinish, ControlId.CompareReview,
            ControlId.WalkthroughInit, ControlId.WalkthroughBuild, ControlId.SaveReview,
            ControlId.AbortReview,
        };
        foreach (var id in confirming)
            Assert.True(PanelLayoutBuilder.RequiresConfirmation(id), $"{id.Wire()} must confirm");
        foreach (var id in new[] { ControlId.Refresh, ControlId.Next, ControlId.Prev, ControlId.OpenEntry })
            Assert.False(PanelLayoutBuilder.RequiresConfirmation(id), $"{id.Wire()} must not confirm");
    }

    [Fact]
    public void Skeleton_timings_stay_under_the_perceptible_threshold()
    {
        Assert.True(PanelLayoutTiming.SkeletonDelayMs <= 200);
        Assert.Equal(120, PanelLayoutTiming.SkeletonDelayMs);
        Assert.Equal(800, PanelLayoutTiming.WhyCeilingMs);
    }
}
