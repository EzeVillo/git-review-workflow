using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The projection from porcelain records to what the panel draws. Everything the
/// layout later asserts on is decided here.
/// </summary>
public class PanelModelTests
{
    [Fact]
    public void No_review_builds_the_inventory_and_the_setup_flag()
    {
        var state = new ReviewState(
            Situation.NoReview,
            Branches: new[] { new BranchRecord("review-saved/f", true, false, false, ReviewMode.Walk) },
            Config: new EffectiveConfig(null, "origin"));
        var m = PanelModelBuilder.BuildPanelModel(state, new PanelInputs(false));
        Assert.True(m.NoBaseConfigured);
        Assert.Single(m.ReviewsList);
        Assert.True(m.ReviewsList[0].Resumable);
        Assert.Equal("origin", m.ConfiguredRemote);
        Assert.Null(m.ConfiguredBase);
    }

    /// <summary>
    /// The setup screen is for a repository with no base, not for one whose config
    /// could not be read at all — those are different failures.
    /// </summary>
    [Fact]
    public void No_base_configured_needs_a_config_that_was_actually_read()
    {
        var unread = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.NoReview), new PanelInputs(false));
        Assert.False(unread.NoBaseConfigured);

        var configured = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.NoReview, Config: new EffectiveConfig("main", "origin")),
            new PanelInputs(false));
        Assert.False(configured.NoBaseConfigured);
        Assert.Equal("main", configured.ConfiguredBase);
    }

    /// <summary>
    /// A saved review is resumable unless something is holding its branch: an active
    /// review of the same source, or no metadata to resume from.
    /// </summary>
    [Fact]
    public void Resumable_is_false_when_the_source_is_taken_or_the_branch_is_an_orphan()
    {
        var branches = Porcelain.ParseListPorcelain(
            "branch\treview-saved/taken\t1\t0\t0\twalk\n" +
            "branch\treview/taken\t0\t1\t0\twalk\n" +
            "branch\treview-saved/free\t1\t0\t0\twalk\n" +
            "branch\treview-saved/orphan\t1\t0\t1");
        var m = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.NoReview, Branches: branches), new PanelInputs(false));
        var byName = m.ReviewsList.ToDictionary(r => r.Name);
        Assert.False(byName["review-saved/taken"].Resumable);
        Assert.True(byName["review-saved/free"].Resumable);
        Assert.False(byName["review-saved/orphan"].Resumable);
        // An active review is never "resumable": it is already open.
        Assert.False(byName["review/taken"].Resumable);
    }

    [Fact]
    public void Resumable_source_at_resolves_an_index_to_a_branch_name()
    {
        var branches = Porcelain.ParseListPorcelain(
            "branch\treview-saved/free\t1\t0\t0\twalk\n" +
            "branch\treview-saved/taken\t1\t0\t0\twalk\n" +
            "branch\treview/taken\t0\t1\t0\twalk");
        Assert.Equal("free", PanelModelBuilder.ResumableSourceAt(branches, 0));
        Assert.Null(PanelModelBuilder.ResumableSourceAt(branches, 1));
        // Anything that is not an in-range index resolves to nothing rather than
        // to whichever review happens to sit at position zero.
        Assert.Null(PanelModelBuilder.ResumableSourceAt(branches, null));
        Assert.Null(PanelModelBuilder.ResumableSourceAt(branches, "0"));
        Assert.Null(PanelModelBuilder.ResumableSourceAt(branches, -1));
        Assert.Null(PanelModelBuilder.ResumableSourceAt(branches, 99));
    }

    [Fact]
    public void Walk_carries_the_cursor_and_asks_for_a_why()
    {
        var state = new ReviewState(
            Situation.Review,
            State: new StateRecord(
                "review/f", "f", "abc", ReviewMode.Walk, WalkthroughStatus.Applied,
                Position: 1, Total: 2, Recorded: 2, Current: Unquote.ToPathRef("a.kt")),
            Entries: new[]
            {
                new EntryRecord(1, Unquote.ToPathRef("a.kt"), Essential: true, Annotated: true),
                new EntryRecord(2, Unquote.ToPathRef("b.kt"), Essential: false, Annotated: true),
            });
        var m = PanelModelBuilder.BuildPanelModel(state, new PanelInputs(false));
        Assert.Equal(1, m.Position);
        Assert.True(m.AtFirst);
        Assert.False(m.AtLast);
        Assert.Equal("a.kt", m.Current?.Display);
        Assert.True(m.Current?.Essential);
        Assert.Equal(2, m.EntryCount);
        // No why supplied yet: the panel asks for one rather than showing none.
        Assert.Equal(WhyState.Loading, m.Why?.State);
    }

    /// <summary>Only walk has a why; asking for one in step would be a request nobody answers.</summary>
    [Fact]
    public void Step_and_whole_carry_no_why()
    {
        var step = PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord("review/f", "f", "abc", ReviewMode.Step, WalkthroughStatus.None,
                    Position: 1, Total: 1, Recorded: 1, Current: "aaa"),
                Entries: new[] { new EntryRecord(1, "aaa") }),
            new PanelInputs(false, Why: new PanelWhy(WhyState.Present, "text")));
        Assert.Null(step.Why);

        var whole = PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord("review/f", "f", "abc", ReviewMode.Whole, WalkthroughStatus.None),
                Entries: new[] { new EntryRecord(1, Unquote.ToPathRef("a.kt")) }),
            new PanelInputs(false, Why: new PanelWhy(WhyState.Present, "text")));
        Assert.Null(whole.Why);
    }

    /// <summary>
    /// Fewer entries in range than were recorded at start means the base moved under
    /// the review, which the panel says out loud.
    /// </summary>
    [Fact]
    public void Base_moved_comes_from_total_against_recorded()
    {
        static bool Moved(int total, int recorded) => PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord("review/f", "f", "abc", ReviewMode.Walk, WalkthroughStatus.Applied,
                    Position: 1, Total: total, Recorded: recorded, Current: Unquote.ToPathRef("a.kt")),
                Entries: new[] { new EntryRecord(1, Unquote.ToPathRef("a.kt")) }),
            new PanelInputs(false)).BaseMoved;

        Assert.True(Moved(2, 3));
        Assert.False(Moved(3, 3));
        Assert.False(Moved(4, 3));
    }

    [Fact]
    public void Finish_conflict_locks_navigation()
    {
        var state = new ReviewState(
            Situation.FinishConflict,
            State: new StateRecord(
                "review/f", "f", "abc", ReviewMode.Step, WalkthroughStatus.None,
                Position: 2, Total: 3, Recorded: 3, Current: "bbb"),
            Entries: new[]
            {
                new EntryRecord(1, "aaa", Banked: false),
                new EntryRecord(2, "bbb", Banked: true),
                new EntryRecord(3, "ccc", Banked: false),
            });
        var m = PanelModelBuilder.BuildPanelModel(state, new PanelInputs(true));
        Assert.True(m.NavigationLocked);
        Assert.False(m.AtFirst);
        Assert.False(m.AtLast);
        Assert.True(m.Busy);
    }

    /// <summary>
    /// Situations with no review carry no review fields at all: a leftover branch
    /// name from a previous refresh is what makes a panel act on the wrong review.
    /// </summary>
    [Fact]
    public void Non_review_situations_carry_no_review_fields()
    {
        var state = new ReviewState(
            Situation.NoReview,
            State: new StateRecord("review/stale", "stale", "abc", ReviewMode.Walk, WalkthroughStatus.Applied,
                Position: 1, Total: 2, Recorded: 2),
            Entries: new[] { new EntryRecord(1, Unquote.ToPathRef("a.kt")) });
        var m = PanelModelBuilder.BuildPanelModel(state, new PanelInputs(false));
        Assert.Null(m.Branch);
        Assert.Null(m.Mode);
        Assert.Null(m.Position);
        Assert.Equal(0, m.EntryCount);
    }

    [Fact]
    public void Pending_finish_is_taken_from_the_branch_that_has_one()
    {
        var state = new ReviewState(
            Situation.FinishPending,
            Branches: new[]
            {
                new BranchRecord("review/other", false, false, false),
                new BranchRecord("review/f", false, true, false, Finish: new BranchFinish("pending", true)),
            });
        var m = PanelModelBuilder.BuildPanelModel(state, new PanelInputs(false));
        Assert.Equal("review/f", m.PendingFinish?.Branch);
        Assert.True(m.PendingFinish?.Onto);
    }

    /// <summary>
    /// Blank stderr is nothing to show; the model normalises it away so no screen has
    /// to test for whitespace.
    /// </summary>
    [Fact]
    public void Blank_stderr_is_dropped()
    {
        foreach (var blank in new[] { null, "", "  \n\t" })
            Assert.Null(PanelModelBuilder.BuildPanelModel(
                new ReviewState(Situation.Error, Stderr: blank), new PanelInputs(false)).Stderr);
        Assert.Equal("boom", PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.Error, Stderr: "boom"), new PanelInputs(false)).Stderr);
    }

    [Fact]
    public void Current_entry_is_looked_up_by_position_not_by_order()
    {
        var entries = new[] { new EntryRecord(3, "c"), new EntryRecord(1, "a") };
        Assert.Equal("a", PanelModelBuilder.CurrentEntry(entries, 1)?.Id);
        Assert.Equal("c", PanelModelBuilder.CurrentEntry(entries, 3)?.Id);
        Assert.Null(PanelModelBuilder.CurrentEntry(entries, 2));
        Assert.Null(PanelModelBuilder.CurrentEntry(entries, null));
    }

    /// <summary>
    /// The picker line is what the reviewer reads when jumping around, so it pads to
    /// keep the numbers aligned and names every mark the entry carries.
    /// </summary>
    [Fact]
    public void Entry_pick_labels_pad_and_list_their_marks()
    {
        var entry = new EntryRecord(2, Unquote.ToPathRef("src/a.kt"), Essential: true, Annotated: false, Banked: true);
        var label = PanelModelBuilder.EntryPickLabel(entry, 2, "Fix the thing");
        Assert.Equal("02  src/a.kt  Fix the thing", label.Label);
        Assert.Equal("current · key · not covered · saved edits", label.Description);

        var plain = PanelModelBuilder.EntryPickLabel(new EntryRecord(10, "abc1234"), 1, null);
        Assert.Equal("10  abc1234", plain.Label);
        Assert.Equal("", plain.Description);
    }

    [Fact]
    public void Step_files_and_last_opened_only_survive_when_the_file_is_listed()
    {
        var state = new ReviewState(
            Situation.Review,
            State: new StateRecord("review/f", "f", "abc", ReviewMode.Step, WalkthroughStatus.None,
                Position: 1, Total: 1, Recorded: 1, Current: "aaa"),
            Entries: new[] { new EntryRecord(1, "aaa") },
            Files: new[] { new EntryRecord(1, Unquote.ToPathRef("src/a.kt")) });

        var listed = PanelModelBuilder.BuildPanelModel(state, new PanelInputs(false, LastOpened: "src/a.kt"));
        Assert.Equal("src/a.kt", listed.LastOpened);
        Assert.Single(listed.FilesList);

        var gone = PanelModelBuilder.BuildPanelModel(state, new PanelInputs(false, LastOpened: "src/gone.kt"));
        Assert.Null(gone.LastOpened);
    }

    [Fact]
    public void Why_state_ids_are_the_wire_names()
    {
        Assert.Equal(new[] { "loading", "present", "absent", "failed" },
            Enum.GetValues<WhyState>().Select(s => s.Id()));
    }
}
