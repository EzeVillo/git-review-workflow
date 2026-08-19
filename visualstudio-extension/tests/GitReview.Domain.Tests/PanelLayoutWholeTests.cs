using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutWholeTests
{
    /// <summary>
    /// No truncation and no "show more": a review's range is what it is, and a file
    /// the panel silently drops is a file nobody reviews.
    /// </summary>
    [Fact]
    public void Three_hundred_files_produce_three_hundred_rows()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole(300));
        var files = layout.Blocks.OfType<Block.FileRows>().First();
        Assert.Equal(300, files.Rows.Count);
        Assert.Equal("300 files in this review", layout.Blocks.OfType<Block.Heading>().First().Text);
        Assert.True(files.Rows[0].LastOpened);
        Assert.All(files.Rows.Skip(1), r => Assert.False(r.LastOpened));
        // Each row carries its own position, which is how a click finds its file.
        Assert.Equal(Enumerable.Range(1, 300), files.Rows.Select(r => r.Index));
    }

    [Fact]
    public void Singular_file_heading()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole(1));
        Assert.Equal("1 file in this review", layout.Blocks.OfType<Block.Heading>().First().Text);
    }

    [Fact]
    public void An_empty_range_says_so_instead_of_an_empty_list()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWholeEmpty());
        var empty = layout.Blocks.OfType<Block.EmptyMessage>().First();
        Assert.Equal("This review's range does not touch any files.", empty.Text);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.FileRows);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.Heading);
    }

    /// <summary>The same block builder in step, with the unit it is counting swapped.</summary>
    [Fact]
    public void A_step_commit_counts_files_in_this_commit()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewStep());
        Assert.Equal("2 files in this commit", layout.Blocks.OfType<Block.Heading>().First().Text);

        var noFiles = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewStep(withFiles: false));
        Assert.Equal(
            "This commit changes no files.",
            noFiles.Blocks.OfType<Block.EmptyMessage>().First().Text);
    }

    /// <summary>
    /// Whole is the file inventory and nothing else: no entry head, no why, no
    /// navigation — there is no cursor to move.
    /// </summary>
    [Fact]
    public void Whole_has_no_cursor_furniture()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole());
        Assert.DoesNotContain(layout.Blocks, b => b is Block.EntryHead);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.EntryTitle);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.Why);
        Assert.DoesNotContain(layout.CollectControls(), c => c.Id is ControlId.Next or ControlId.Prev);
        Assert.DoesNotContain(layout.CollectControls(), c => c.Id == ControlId.ShowWhy);
    }

    /// <summary>
    /// The row the reviewer opened last is marked, and only while it is still in the
    /// range — a stale mark points at a file that is no longer there.
    /// </summary>
    [Fact]
    public void The_last_opened_mark_is_dropped_when_the_file_leaves_the_range()
    {
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord("review/f", "f", "tip", ReviewMode.Whole, WalkthroughStatus.None),
                Entries: new[] { new EntryRecord(1, Unquote.ToPathRef("file1.kt")) },
                Base: "main"),
            new PanelInputs(false, LastOpened: "gone.kt"));
        var rows = PanelLayoutBuilder.PanelLayout(model).Blocks.OfType<Block.FileRows>().First().Rows;
        Assert.All(rows, r => Assert.False(r.LastOpened));
    }

    /// <summary>Rows show the display path, which is what the file system and the user use.</summary>
    [Fact]
    public void Rows_show_the_unquoted_path()
    {
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord("review/f", "f", "tip", ReviewMode.Whole, WalkthroughStatus.None),
                Entries: new[] { new EntryRecord(1, Unquote.ToPathRef("\"src/caf\\303\\251 y espacio.kt\"")) },
                Base: "main"),
            new PanelInputs(false));
        var row = PanelLayoutBuilder.PanelLayout(model).Blocks.OfType<Block.FileRows>().First().Rows.Single();
        Assert.Equal("src/café y espacio.kt", row.Display);
    }
}
