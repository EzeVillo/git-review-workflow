using Xunit;

namespace GitReview.Domain.Tests;

public class UnquoteTests
{
    [Fact]
    public void Plain_path_unchanged()
    {
        Assert.Equal("src/main.kt", Unquote.UnquotePath("src/main.kt"));
        // Not quoted on both ends: left alone rather than half-stripped.
        Assert.Equal("\"half", Unquote.UnquotePath("\"half"));
        Assert.Equal("\"", Unquote.UnquotePath("\""));
        Assert.Equal("", Unquote.UnquotePath(""));
    }

    [Fact]
    public void Unquote_escaped_quote_and_backslash()
    {
        Assert.Equal("a\"b\\c", Unquote.UnquotePath("\"a\\\"b\\\\c\""));
    }

    [Fact]
    public void Unquote_octal_utf8()
    {
        // "caf\303\251" -> café: two octal bytes that only decode as one character
        // when they are collected as bytes first.
        Assert.Equal("café", Unquote.UnquotePath("\"caf\\303\\251\""));
        Assert.Equal("aéb", Unquote.UnquotePath("\"a\\303\\251b\""));
    }

    /// <summary>
    /// A four-byte codepoint arrives as four octal escapes; decoding them one at a
    /// time would yield four replacement characters instead of the emoji.
    /// </summary>
    [Fact]
    public void Unquote_octal_outside_the_basic_plane()
    {
        Assert.Equal("a\U0001F389b", Unquote.UnquotePath("\"a\\360\\237\\216\\211b\""));
    }

    [Fact]
    public void Unquote_c_escapes()
    {
        Assert.Equal("a\tb", Unquote.UnquotePath("\"a\\tb\""));
        Assert.Equal("a\nb", Unquote.UnquotePath("\"a\\nb\""));
        Assert.Equal("a\rb", Unquote.UnquotePath("\"a\\rb\""));
        // An escape git does not define keeps the character, not the backslash.
        Assert.Equal("aqb", Unquote.UnquotePath("\"a\\qb\""));
    }

    /// <summary>Octal runs stop at three digits, so a literal digit after them survives.</summary>
    [Fact]
    public void Octal_runs_stop_after_three_digits()
    {
        Assert.Equal("é7", Unquote.UnquotePath("\"\\303\\2517\""));
    }

    [Fact]
    public void Non_ascii_that_git_did_not_quote_passes_through()
    {
        Assert.Equal("src/café.kt", Unquote.UnquotePath("src/café.kt"));
        Assert.Equal("src/\U0001F389.kt", Unquote.UnquotePath("src/\U0001F389.kt"));
    }

    [Fact]
    public void To_path_ref_keeps_raw_for_the_cli_and_display_for_the_user()
    {
        var quoted = Unquote.ToPathRef("\"foo bar\"");
        Assert.Equal("\"foo bar\"", quoted.Raw);
        Assert.Equal("foo bar", quoted.Display);

        var plain = Unquote.ToPathRef("src/a.kt");
        Assert.Equal("src/a.kt", plain.Raw);
        Assert.Equal("src/a.kt", plain.Display);
    }
}
