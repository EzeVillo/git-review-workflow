using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// Which of the two recoveries the panel offers after a failed start: a network
/// failure gets the "run it in a terminal so git can prompt you" path, everything
/// else gets the repository one. Guessing wrong sends the reviewer to the wrong fix.
/// </summary>
public class StartFailureTests
{
    [Theory]
    [InlineData("fatal: Could not resolve host github.com")]
    [InlineData("fatal: could not read from remote repository")]
    [InlineData("ssh: connect to host github.com port 22: Connection timed out")]
    [InlineData("ssh: connect to host github.com port 22: Connection refused")]
    [InlineData("fatal: unable to access 'https://github.com/x.git/'")]
    [InlineData("fatal: could not read Username for 'https://github.com'")]
    [InlineData("fatal: could not read Password for 'https://github.com'")]
    [InlineData("remote: Authentication failed for 'https://github.com/x.git/'")]
    [InlineData("git@github.com: Permission denied (publickey).")]
    [InlineData("fatal: could not read Username: terminal prompts disabled")]
    public void Network_markers_classify_as_network(string stderr)
    {
        Assert.Equal(StartFailureCategory.Network, StartFailure.ClassifyStartFailure(stderr));
    }

    [Theory]
    [InlineData("error: working tree is dirty")]
    [InlineData("error: reviewworkflow.base is not set")]
    [InlineData("fatal: not a git repository")]
    [InlineData("")]
    public void Everything_else_classifies_as_repository(string stderr)
    {
        Assert.Equal(StartFailureCategory.Repository, StartFailure.ClassifyStartFailure(stderr));
    }

    /// <summary>git varies the case of these across versions and platforms.</summary>
    [Fact]
    public void Classification_is_case_insensitive()
    {
        Assert.Equal(StartFailureCategory.Network, StartFailure.ClassifyStartFailure("COULD NOT RESOLVE HOST"));
        Assert.Equal(StartFailureCategory.Network, StartFailure.ClassifyStartFailure("Authentication Failed"));
    }

    /// <summary>
    /// The offered command line is meant to be pasted into a terminal and run, so a
    /// value with a space in it has to survive the paste as one argument.
    /// </summary>
    [Fact]
    public void Posix_quoting_leaves_plain_values_alone_and_quotes_the_rest()
    {
        Assert.Equal("feature/x", StartFailure.QuoteForTerminal("feature/x"));
        Assert.Equal("/opt/bin/git-review", StartFailure.QuoteForTerminal("/opt/bin/git-review"));
        Assert.Equal("\"con espacio\"", StartFailure.QuoteForTerminal("con espacio"));
        Assert.Equal("\"say \\\"hi\\\"\"", StartFailure.QuoteForTerminal("say \"hi\""));
        // A leading dash would read as a flag, so it gets quoted.
        Assert.Equal("\"--force\"", StartFailure.QuoteForTerminal("--force"));
    }

    [Fact]
    public void Windows_quoting_uses_powershell_doubling()
    {
        Assert.Equal("feature/x", StartFailure.QuoteForTerminal("feature/x", "win32"));
        // The drive letter's colon is not in the bare-token set, so a Windows path
        // is quoted — harmless, and PowerShell reads it back as the same path.
        Assert.Equal("'C:\\repo\\bin\\git-review'", StartFailure.QuoteForTerminal("C:\\repo\\bin\\git-review", "win32"));
        Assert.Equal("'con espacio'", StartFailure.QuoteForTerminal("con espacio", "win32"));
        Assert.Equal("'it''s'", StartFailure.QuoteForTerminal("it's", "win32"));
        Assert.Equal("'--force'", StartFailure.QuoteForTerminal("--force", "win32"));
    }

    /// <summary>
    /// An empty value has to stay an argument rather than vanishing from the line.
    /// </summary>
    [Fact]
    public void An_empty_value_is_still_quoted_into_an_argument()
    {
        Assert.Equal("\"\"", StartFailure.QuoteForTerminal(""));
        Assert.Equal("''", StartFailure.QuoteForTerminal("", "win32"));
    }

    /// <summary>
    /// A branch with an accent in it is a branch like any other, and whichever way
    /// it is quoted it has to come back out as itself. .NET's <c>\w</c> is
    /// Unicode-aware while Java's is not, so this is exactly the spot where a
    /// mechanical port drifts from the client it was ported from.
    /// </summary>
    [Fact]
    public void Non_ascii_values_round_trip_through_both_shells()
    {
        foreach (var platform in new[] { "linux", "win32" })
        {
            var quoted = StartFailure.QuoteForTerminal("feature/ación", platform);
            Assert.Contains("feature/ación", quoted);
            Assert.DoesNotContain(" ", quoted);
        }
        // With a space in it there is no ambiguity left: both shells quote.
        Assert.StartsWith("\"", StartFailure.QuoteForTerminal("feature/con acción", "linux"));
        Assert.StartsWith("'", StartFailure.QuoteForTerminal("feature/con acción", "win32"));
    }
}

public class CliLogTests
{
    [Fact]
    public void The_command_line_is_the_one_that_ran()
    {
        Assert.Equal("git review status", CliLog.FormatCommandLine("git", new[] { "review", "status" }));
        Assert.Equal("sh /bin/git-review next", CliLog.FormatCommandLine("sh", new[] { "/bin/git-review", "next" }));
    }

    [Fact]
    public void Arguments_that_need_quoting_get_it()
    {
        Assert.Equal("plain", CliLog.ShellQuoteArg("plain"));
        Assert.Equal("\"a b\"", CliLog.ShellQuoteArg("a b"));
        Assert.Equal("\"\"", CliLog.ShellQuoteArg(""));
        Assert.Equal("\"say \\\"hi\\\"\"", CliLog.ShellQuoteArg("say \"hi\""));
        Assert.Equal("\"C:\\\\repo\"", CliLog.ShellQuoteArg("C:\\repo"));
    }

    [Fact]
    public void A_clean_exit_is_one_line()
    {
        Assert.Equal(
            new[] { "← exit 0  12ms" },
            CliLog.FormatCliEnd(new CliLog.CliLogEnd(0, null, 12, "")));
    }

    /// <summary>
    /// A non-zero exit brings its stderr with it, indented — that text is the whole
    /// reason anyone opens the log.
    /// </summary>
    [Fact]
    public void A_failed_exit_carries_its_stderr()
    {
        var lines = CliLog.FormatCliEnd(new CliLog.CliLogEnd(1, null, 30, "fatal: boom\nsecond line\n"));
        Assert.Equal(new[] { "← exit 1  30ms", "  fatal: boom", "  second line" }, lines);
        // Non-zero with nothing to say stays a single line rather than a blank one.
        Assert.Single(CliLog.FormatCliEnd(new CliLog.CliLogEnd(1, null, 30, "   \n")));
    }

    [Fact]
    public void A_timeout_and_a_spawn_failure_each_say_which_they_were()
    {
        Assert.Equal(
            new[] { "← timed out after 300000ms (killed)" },
            CliLog.FormatCliEnd(new CliLog.CliLogEnd(null, null, 300000, "", TimedOut: true)));
        Assert.Equal(
            new[] { "← spawn failed Win32Exception  5ms" },
            CliLog.FormatCliEnd(new CliLog.CliLogEnd(null, "Win32Exception", 5, "")));
        Assert.Equal(
            new[] { "← exit null  5ms" },
            CliLog.FormatCliEnd(new CliLog.CliLogEnd(null, null, 5, "")));
    }

    /// <summary>A runaway stderr is truncated so the ring buffer stays readable.</summary>
    [Fact]
    public void Long_stderr_is_truncated_and_says_so()
    {
        var huge = new string('x', CliLog.StderrMax + 500);
        var lines = CliLog.FormatCliEnd(new CliLog.CliLogEnd(1, null, 10, huge));
        Assert.Equal(3, lines.Count);
        Assert.Equal("  " + new string('x', CliLog.StderrMax), lines[1]);
        Assert.Equal("  … (truncated)", lines[2]);
    }
}
