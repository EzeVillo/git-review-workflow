using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// Tokenizer for <c>status --porcelain</c> and <c>list --porcelain</c>.
/// Port of the jetbrains PorcelainTest, with the list side the C# port never had.
/// </summary>
public class PorcelainTests
{
    [Fact]
    public void Parse_whole_status()
    {
        var text =
            "state\treview/feature\tfeature\tabc123\twhole\tnone\n" +
            "entry\t1\tsrc/a.kt\n" +
            "entry\t2\tsrc/b.kt\n" +
            "base\tmain";
        var r = Porcelain.ParsePorcelain(text);
        Assert.Equal(ReviewMode.Whole, r.State.Mode);
        Assert.Equal(WalkthroughStatus.None, r.State.Walkthrough);
        Assert.Equal("review/feature", r.State.Branch);
        Assert.Equal("feature", r.State.Source);
        Assert.Equal("abc123", r.State.Tip);
        Assert.Equal(2, r.Entries.Count);
        Assert.Equal("main", r.Base);
        Assert.IsType<PathRef>(r.Entries[0].Id);
        // whole carries no cursor at all
        Assert.Null(r.State.Position);
        Assert.Null(r.State.Total);
        Assert.Null(r.State.Essential);
    }

    [Fact]
    public void Parse_walk_status()
    {
        var text =
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t2\t5\t5\t\"src/foo.kt\"\t1\n" +
            "entry\t1\tsrc/a.kt\t0\t1\n" +
            "entry\t2\t\"src/foo.kt\"\t1\t1\n" +
            "keys";
        var r = Porcelain.ParsePorcelain(text);
        Assert.Equal(ReviewMode.Walk, r.State.Mode);
        Assert.Equal(WalkthroughStatus.Applied, r.State.Walkthrough);
        Assert.Equal(2, r.State.Position);
        Assert.Equal(5, r.State.Total);
        Assert.Equal(5, r.State.Recorded);
        Assert.True(r.State.Essential);
        Assert.True(r.KeysOnly);
        Assert.Null(r.Draft);
        Assert.Equal("src/foo.kt", Assert.IsType<PathRef>(r.State.Current).Display);
        Assert.Equal("src/foo.kt", Assert.IsType<PathRef>(r.Entries[1].Id).Display);
        Assert.True(r.Entries[1].Essential);
        Assert.False(r.Entries[0].Essential);
        Assert.True(r.Entries[0].Annotated);
    }

    /// <summary>011: a presence record with no fields; it shifts nothing else.</summary>
    [Fact]
    public void Parse_walk_status_on_the_reviewers_draft()
    {
        var text =
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t2\t5\t5\t\"src/foo.kt\"\t0\n" +
            "entry\t1\tsrc/a.kt\t0\t1\n" +
            "entry\t2\t\"src/foo.kt\"\t0\t1\n" +
            "draft";
        var r = Porcelain.ParsePorcelain(text);
        Assert.True(r.Draft);
        Assert.Null(r.KeysOnly);
        Assert.Equal(ReviewMode.Walk, r.State.Mode);
        Assert.Equal(2, r.State.Position);
        Assert.Equal(5, r.State.Total);
        Assert.Equal(2, r.Entries.Count);
    }

    [Fact]
    public void Draft_and_keys_coexist()
    {
        var text =
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t1\t1\tsrc/a.kt\t1\n" +
            "entry\t1\tsrc/a.kt\t1\t1\n" +
            "keys\n" +
            "draft";
        var r = Porcelain.ParsePorcelain(text);
        Assert.True(r.Draft);
        Assert.True(r.KeysOnly);
    }

    [Fact]
    public void Parse_step_keeps_a_literal_tab_inside_the_subject()
    {
        var text =
            "state\treview/f\tf\tabc\tstep\tnone\t1\t2\t2\tabc1234\n" +
            "entry\t1\tabc1234\t0\n" +
            "subject\t1\tfix with\ttab\n" +
            "author\t1\tAda\n";
        var r = Porcelain.ParsePorcelain(text);
        Assert.Equal("fix with\ttab", r.Subjects?[1]);
        Assert.Equal("Ada", r.Authors?[1]);
        // step ids stay short SHAs, never PathRefs
        Assert.Equal("abc1234", Assert.IsType<string>(r.Entries[0].Id));
        Assert.False(r.Entries[0].Banked);
        Assert.Equal("abc1234", Assert.IsType<string>(r.State.Current));
    }

    [Fact]
    public void Parse_finish_conflict_and_readonly()
    {
        var text =
            "state\treview/f\tf\tabc\twhole\tnone\n" +
            "finish\tconflict\t1\n" +
            "readonly";
        var r = Porcelain.ParsePorcelain(text);
        Assert.Equal("conflict", r.Finish?.State);
        Assert.True(r.Finish?.Onto);
        Assert.True(r.Readonly);
    }

    [Fact]
    public void File_records_land_in_files_not_entries()
    {
        var text =
            "state\treview/f\tf\tabc\tstep\tnone\t1\t2\t2\tabc1234\n" +
            "entry\t1\tabc1234\t0\n" +
            "file\t1\tsrc/a.kt\n" +
            "file\t2\t\"src/caf\\303\\251.kt\"\n";
        var r = Porcelain.ParsePorcelain(text);
        Assert.Single(r.Entries);
        Assert.Equal(2, r.FilesList.Count);
        Assert.Equal("src/café.kt", Assert.IsType<PathRef>(r.FilesList[1].Id).Display);
    }

    /// <summary>FR-003: a tag this client does not know must not derail the rest.</summary>
    [Fact]
    public void Unknown_tags_are_ignored()
    {
        var text =
            "state\treview/f\tf\tabc\twhole\tnone\n" +
            "something-new\t1\t2\n" +
            "entry\t1\tsrc/a.kt";
        var r = Porcelain.ParsePorcelain(text);
        Assert.Single(r.Entries);
        Assert.Equal(ReviewMode.Whole, r.State.Mode);
    }

    [Fact]
    public void Crlf_output_parses_the_same_as_lf()
    {
        var lf = "state\treview/f\tf\tabc\twhole\tnone\nentry\t1\tsrc/a.kt";
        var crlf = lf.Replace("\n", "\r\n");
        Assert.Equal(
            Porcelain.ParsePorcelain(lf).Entries.Count,
            Porcelain.ParsePorcelain(crlf).Entries.Count);
        Assert.Equal("abc", Porcelain.ParsePorcelain(crlf).State.Tip);
    }

    [Fact]
    public void No_state_record_is_an_error_not_an_empty_review()
    {
        Assert.Throws<ArgumentException>(() => Porcelain.ParsePorcelain(""));
        Assert.Throws<ArgumentException>(() => Porcelain.ParsePorcelain("entry\t1\tsrc/a.kt"));
    }

    [Fact]
    public void Invalid_mode_is_an_error()
    {
        var ex = Assert.Throws<ArgumentException>(
            () => Porcelain.ParsePorcelain("state\treview/f\tf\tabc\tsideways\tnone"));
        Assert.Contains("sideways", ex.Message);
    }

    // --- list --porcelain -----------------------------------------------------

    [Fact]
    public void Parse_list_and_source_of()
    {
        var text =
            "branch\treview-saved/feature\t1\t0\t0\twalk\t3\t5\n" +
            "finish\treview-saved/feature\tpending\t0\n" +
            "branch\treview/other\t0\t1\t0\tstep\t1\t2";
        var branches = Porcelain.ParseListPorcelain(text);
        Assert.Equal(2, branches.Count);
        Assert.Equal("feature", Porcelain.SourceOf(branches[0]));
        Assert.True(branches[0].Saved);
        Assert.False(branches[0].Current);
        Assert.Equal(ReviewMode.Walk, branches[0].Mode);
        Assert.Equal(3, branches[0].Position);
        Assert.Equal(5, branches[0].Total);
        Assert.Equal("pending", branches[0].Finish?.State);
        Assert.False(branches[0].Finish?.Onto);

        Assert.False(branches[1].Saved);
        Assert.True(branches[1].Current);
        Assert.Null(branches[1].Finish);
        Assert.Equal("other", Porcelain.SourceOf(branches[1]));
    }

    /// <summary>
    /// A finish record can precede or follow its branch; it is joined by name either
    /// way, and one that names no listed branch is dropped rather than inventing a row.
    /// </summary>
    [Fact]
    public void Finish_records_join_by_name_in_either_order()
    {
        var after =
            "branch\treview/f\t0\t1\t0\twhole\n" +
            "finish\treview/f\tconflict\t1";
        Assert.Equal("conflict", Porcelain.ParseListPorcelain(after)[0].Finish?.State);
        Assert.True(Porcelain.ParseListPorcelain(after)[0].Finish?.Onto);

        var orphanFinish =
            "finish\treview/nobody\tpending\t0\n" +
            "branch\treview/f\t0\t1\t0\twhole";
        var branches = Porcelain.ParseListPorcelain(orphanFinish);
        Assert.Single(branches);
        Assert.Null(branches[0].Finish);
    }

    [Fact]
    public void Unknown_finish_states_are_dropped()
    {
        var text =
            "branch\treview/f\t0\t1\t0\twhole\n" +
            "finish\treview/f\tsomething-else\t0";
        Assert.Null(Porcelain.ParseListPorcelain(text)[0].Finish);
    }

    /// <summary>An orphan has no metadata to read, so no mode and no cursor.</summary>
    [Fact]
    public void Orphan_branches_carry_no_mode_or_cursor()
    {
        var text = "branch\treview/f\t0\t0\t1\twalk\t1\t2";
        var b = Porcelain.ParseListPorcelain(text)[0];
        Assert.True(b.Orphan);
        Assert.Null(b.Mode);
        Assert.Null(b.Position);
        Assert.Null(b.Total);
    }

    /// <summary>A cursor is a pair: half of it is no cursor.</summary>
    [Fact]
    public void A_half_cursor_is_dropped()
    {
        var b = Porcelain.ParseListPorcelain("branch\treview/f\t0\t0\t0\twalk\t3")[0];
        Assert.Equal(ReviewMode.Walk, b.Mode);
        Assert.Null(b.Position);
        Assert.Null(b.Total);
    }

    [Fact]
    public void Missing_mode_field_defaults_to_whole()
    {
        Assert.Equal(ReviewMode.Whole, Porcelain.ParseListPorcelain("branch\treview/f\t0\t0\t0")[0].Mode);
    }

    [Fact]
    public void Empty_list_is_valid()
    {
        Assert.Empty(Porcelain.ParseListPorcelain(""));
        Assert.Empty(Porcelain.ParseListPorcelain("\n\n"));
    }

    [Fact]
    public void Source_of_strips_the_longest_prefix_first()
    {
        static BranchRecord B(string n) => new(n, false, false, false);
        Assert.Equal("feature/x", Porcelain.SourceOf(B("review-saved/feature/x")));
        Assert.Equal("feature/x", Porcelain.SourceOf(B("review/feature/x")));
        // Not a review branch: left alone rather than half-stripped.
        Assert.Equal("feature/x", Porcelain.SourceOf(B("feature/x")));
        Assert.Equal("reviewer/x", Porcelain.SourceOf(B("reviewer/x")));
    }

    [Fact]
    public void Mode_and_walkthrough_ids_round_trip()
    {
        foreach (var m in Enum.GetValues<ReviewMode>())
            Assert.Equal(m, ReviewModeExt.Parse(m.Id()));
        foreach (var w in Enum.GetValues<WalkthroughStatus>())
            Assert.Equal(w, WalkthroughStatusExt.Parse(w.Id()));
        Assert.Null(ReviewModeExt.Parse("nope"));
        Assert.Null(WalkthroughStatusExt.Parse(null));
    }

    [Fact]
    public void The_draft_record_of_status_carries_the_path_without_touching_the_flag()
    {
        var stdout =
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t1\t1\tsrc/a.cs\t0\n" +
            "entry\t1\tsrc/a.cs\t0\t1\n" +
            "draft\t/repo/.git/review-walkthrough/feature.md\n";
        var parsed = Porcelain.ParsePorcelain(stdout);
        Assert.True(parsed.Draft);
        Assert.Equal("/repo/.git/review-walkthrough/feature.md", parsed.DraftPath);

        // An older CLI emits the bare record, and that cannot turn the mark off.
        var bare = Porcelain.ParsePorcelain(
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t1\t1\tsrc/a.cs\t0\n" +
            "entry\t1\tsrc/a.cs\t0\t1\n" +
            "draft\n");
        Assert.True(bare.Draft);
        Assert.Null(bare.DraftPath);
    }
}
