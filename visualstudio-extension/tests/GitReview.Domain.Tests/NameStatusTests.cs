using Xunit;

namespace GitReview.Domain.Tests;

public class NameStatusTests
{
    [Fact]
    public void Add_modify_delete()
    {
        var output = "A\0new.kt\0M\0edit.kt\0D\0gone.kt\0";
        var c = NameStatus.ParseNameStatus(output);
        Assert.Equal(3, c.Count);
        Assert.Null(c[0].Before);
        Assert.Equal("new.kt", c[0].After);
        Assert.Equal("edit.kt", c[1].Before);
        Assert.Equal("edit.kt", c[1].After);
        Assert.Equal("gone.kt", c[2].Before);
        Assert.Null(c[2].After);
    }

    [Fact]
    public void Rename_and_copy_carry_both_sides()
    {
        var renamed = NameStatus.ParseNameStatus("R100\0old.kt\0new.kt\0");
        Assert.Single(renamed);
        Assert.Equal("new.kt", renamed[0].Path);
        Assert.Equal("old.kt", renamed[0].Before);
        Assert.Equal("new.kt", renamed[0].After);

        var copied = NameStatus.ParseNameStatus("C75\0src.kt\0copy.kt\0");
        Assert.Equal("copy.kt", copied[0].Path);
        Assert.Equal("src.kt", copied[0].Before);
    }

    [Fact]
    public void Rename_next_to_an_add()
    {
        var c = NameStatus.ParseNameStatus("R100\0old.kt\0new.kt\0A\0added.kt\0");
        Assert.Equal(2, c.Count);
        Assert.Equal("new.kt", c[0].Path);
        Assert.Equal("old.kt", c[0].Before);
        Assert.Null(c[1].Before);
        Assert.Equal("added.kt", c[1].After);
    }

    /// <summary>
    /// Documents the contract for callers: output must use <c>--no-commit-id</c>.
    /// Without it the first field is the full SHA and the first path becomes the
    /// status letter "M" — the empty-pane "file M" bug in step Diff.
    /// </summary>
    [Fact]
    public void Leading_commit_id_corrupts_paths()
    {
        var sha = "87aaafe84f16d9376bc57f08ab2e5ff1dbc0b588";
        var c = NameStatus.ParseNameStatus($"{sha}\0M\0src/edit.kt\0");
        Assert.Single(c);
        Assert.Equal("M", c[0].Path);
    }

    [Fact]
    public void Without_leading_commit_id_modify_is_a_path()
    {
        var c = NameStatus.ParseNameStatus("M\0src/edit.kt\0");
        Assert.Single(c);
        Assert.Equal("src/edit.kt", c[0].Path);
        Assert.Equal("src/edit.kt", c[0].Before);
        Assert.Equal("src/edit.kt", c[0].After);
    }

    /// <summary>-z means git never quotes, so a path with a space or an accent is literal.</summary>
    [Fact]
    public void Paths_are_never_quoted_under_z()
    {
        var c = NameStatus.ParseNameStatus("M\0src/con espacio y acento é.kt\0");
        Assert.Equal("src/con espacio y acento é.kt", c[0].Path);
    }

    [Fact]
    public void Empty_and_truncated_output()
    {
        Assert.Empty(NameStatus.ParseNameStatus(""));
        Assert.Empty(NameStatus.ParseNameStatus("\0\0"));
        // A record cut in half is dropped, not half-read.
        Assert.Empty(NameStatus.ParseNameStatus("M\0"));
        Assert.Single(NameStatus.ParseNameStatus("M\0a.kt\0R100\0only-one-side\0"));
    }
}
