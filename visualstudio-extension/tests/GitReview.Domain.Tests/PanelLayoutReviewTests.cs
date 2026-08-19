using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutReviewTests
{
    private static readonly HashSet<ControlId> TitleIds = new()
    {
        ControlId.Refresh, ControlId.FinishReview, ControlId.SaveReview,
        ControlId.AbortReview, ControlId.PreviewEdits,
    };

    private static List<Control> Body(PanelLayout layout) =>
        layout.CollectControls().Where(c => !TitleIds.Contains(c.Id)).ToList();

    [Fact]
    public void Walk_layout_has_file_diff_nav_and_why()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk());
        var controls = Body(layout);
        Assert.Equal(
            new[] { "showWhy", "openEntry", "openChange", "prev", "next" },
            controls.Select(c => c.Id.Wire()));

        var showWhy = controls.First(c => c.Id == ControlId.ShowWhy);
        Assert.Equal("open in editor", showWhy.Label);
        Assert.Equal(Emphasis.Link, showWhy.Emphasis);

        var prev = controls.First(c => c.Id == ControlId.Prev);
        Assert.Equal("Previous entry", prev.AccessibleName);
        Assert.Equal(Emphasis.Icon, prev.Emphasis);
        Assert.Null(prev.Label);
        Assert.Equal("Next entry", controls.First(c => c.Id == ControlId.Next).AccessibleName);

        Assert.Contains(layout.Blocks, b => b is Block.IdentityBar);
        Assert.Contains(layout.Blocks, b => b is Block.Why);
    }

    /// <summary>
    /// 011: whose reading order this is. Two days into a review it is easy to read
    /// your own why as the author's, which is why the CLI writes "walk (draft)" and
    /// the panel says it too — in the same place, from the same porcelain record.
    /// </summary>
    [Fact]
    public void Walk_on_the_reviewers_own_draft_is_marked_in_the_identity_bar()
    {
        var bar = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalkDraft())
            .Blocks.OfType<Block.IdentityBar>().First();
        Assert.Equal("walk", bar.Mode);
        Assert.True(bar.Draft);

        // And it is the record that decides, not the mode: the same walk without it
        // is unmarked.
        var plain = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk())
            .Blocks.OfType<Block.IdentityBar>().First();
        Assert.False(plain.Draft);
    }

    [Fact]
    public void The_identity_bar_shortens_the_tip_and_carries_the_cursor()
    {
        var bar = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk())
            .Blocks.OfType<Block.IdentityBar>().First();
        Assert.Equal("feature", bar.Name);
        Assert.Equal("deadbee", bar.Tip);
        Assert.Equal(1, bar.Position);
        Assert.Equal(3, bar.Total);
        Assert.False(bar.IsSkeleton);
    }

    [Fact]
    public void Step_layout_has_diff_only_and_no_why()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewStep());
        var body = Body(layout);
        Assert.DoesNotContain(body, c => c.Id == ControlId.ShowWhy);
        Assert.DoesNotContain(body, c => c.Id == ControlId.OpenEntry);
        Assert.Contains(body, c => c.Id == ControlId.OpenChange && c.Label == "Diff");
        Assert.DoesNotContain(layout.Blocks, b => b is Block.Why);

        var title = layout.Blocks.OfType<Block.EntryTitle>().First();
        Assert.Equal("Fix the thing", title.Text);

        // The current commit's file inventory, like whole.
        var files = layout.Blocks.OfType<Block.FileRows>().First();
        Assert.Equal(2, files.Rows.Count);
        Assert.Equal("src/a.kt", files.Rows[0].Display);
        Assert.True(files.Rows[0].LastOpened);
        Assert.Equal("2 files in this commit", layout.Blocks.OfType<Block.Heading>().First().Text);
    }

    [Fact]
    public void A_step_entry_head_names_the_commit_and_its_author()
    {
        var head = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewStep())
            .Blocks.OfType<Block.EntryHead>().First();
        Assert.Equal(2, head.Position);
        Assert.Equal("abc1234", head.Identifier);
        Assert.Equal("Ada", head.Author);
        Assert.Equal("edits", head.Badge);
    }

    [Fact]
    public void First_entry_disables_prev_and_last_disables_next()
    {
        var first = PanelLayoutBuilder.PanelLayout(
            PanelFixtures.ReviewWalk(atFirst: true, atLast: false, position: 1));
        Assert.False(first.CollectControls().First(c => c.Id == ControlId.Prev).Enabled);
        Assert.True(first.CollectControls().First(c => c.Id == ControlId.Next).Enabled);

        var last = PanelLayoutBuilder.PanelLayout(
            PanelFixtures.ReviewWalk(atFirst: false, atLast: true, position: 3));
        Assert.True(last.CollectControls().First(c => c.Id == ControlId.Prev).Enabled);
        Assert.False(last.CollectControls().First(c => c.Id == ControlId.Next).Enabled);
    }

    [Fact]
    public void Busy_disables_the_mutators_and_strips_the_title_bar()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk(busy: true));
        Assert.False(layout.CollectControls().First(c => c.Id == ControlId.Prev).Enabled);
        Assert.False(layout.CollectControls().First(c => c.Id == ControlId.Next).Enabled);
        Assert.Equal(new[] { ControlId.Refresh }, layout.TitleActions.Select(t => t.Id));
    }

    [Fact]
    public void Badge_precedence_is_key_then_uncovered_then_edits()
    {
        var head = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk())
            .Blocks.OfType<Block.EntryHead>().First();
        Assert.Equal("key", head.Badge);
    }

    [Fact]
    public void Without_a_why_present_there_is_no_open_in_editor()
    {
        foreach (var state in new[] { WhyState.Absent, WhyState.Failed, WhyState.Loading })
        {
            var layout = PanelLayoutBuilder.PanelLayout(
                PanelFixtures.ReviewWalk(why: new PanelWhy(state)));
            Assert.DoesNotContain(layout.CollectControls(), c => c.Id == ControlId.ShowWhy);
            Assert.Contains(layout.Blocks, b => b is Block.Why w && w.State == state);
        }
    }

    /// <summary>
    /// An absent why on a file the walkthrough never annotates reads differently
    /// from one the author simply left blank, and the panel says which.
    /// </summary>
    [Fact]
    public void An_uncovered_entry_says_so_instead_of_looking_unexplained()
    {
        var uncovered = PanelLayoutBuilder.PanelLayout(
                PanelFixtures.ReviewWalk(why: new PanelWhy(WhyState.Absent), atFirst: false, position: 3))
            .Blocks.OfType<Block.Why>().First();
        Assert.True(uncovered.Uncovered);
        Assert.Equal(
            "This file changes in the review and the walkthrough does not annotate it.",
            uncovered.Text);

        var annotated = PanelLayoutBuilder.PanelLayout(
                PanelFixtures.ReviewWalk(why: new PanelWhy(WhyState.Absent)))
            .Blocks.OfType<Block.Why>().First();
        Assert.False(annotated.Uncovered);
        Assert.Equal("This entry has no explanation.", annotated.Text);
    }

    [Fact]
    public void An_empty_cursor_says_so_instead_of_drawing_a_blank_entry()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalkEmptyCursor());
        var empty = layout.Blocks.OfType<Block.EmptyMessage>().First();
        Assert.Equal("The cursor does not point at any entry in the sequence.", empty.Text);
        Assert.DoesNotContain(layout.Blocks, b => b is Block.EntryHead);
    }

    /// <summary>
    /// The notes are the standing warnings about the range; each one comes from its
    /// own flag and they stack.
    /// </summary>
    [Fact]
    public void Notes_come_from_the_flags_that_earn_them()
    {
        var plain = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk());
        Assert.DoesNotContain(plain.Blocks, b => b is Block.Note);

        var flagged = PanelFixtures.ReviewWalk() with
        {
            Readonly = true,
            KeysOnly = true,
            BaseMoved = true,
            Degraded = true,
        };
        var notes = PanelLayoutBuilder.PanelLayout(flagged).Blocks.OfType<Block.Note>().ToList();
        Assert.Equal(4, notes.Count);
        Assert.StartsWith("Read-only compare", notes[0].Text);
        Assert.StartsWith("Keys-only", notes[1].Text);
        Assert.StartsWith("The base moved", notes[2].Text);
        Assert.StartsWith("The walkthrough does not cover", notes[3].Text);
    }

    [Fact]
    public void Whole_notes_name_the_base_the_range_was_built_against()
    {
        var note = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole())
            .Blocks.OfType<Block.Note>().First();
        Assert.Equal("Range built against main.", note.Text);
    }
}
