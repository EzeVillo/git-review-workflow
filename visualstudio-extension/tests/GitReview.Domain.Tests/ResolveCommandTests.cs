using Xunit;

namespace GitReview.Domain.Tests;

public class ResolveCommandTests
{
    [Fact]
    public void Empty_path_goes_through_git_review()
    {
        foreach (var path in new string?[] { null, "", "   " })
        {
            var r = ResolveCommand.Resolve("status", new[] { "--porcelain" }, path, "linux");
            Assert.Equal("git", r.Command);
            Assert.Equal(new[] { "review", "status", "--porcelain" }, r.Args);
        }
    }

    [Fact]
    public void Posix_path_runs_directly()
    {
        var r = ResolveCommand.Resolve("start", new[] { "--", "f" }, "/opt/bin/git-review", "linux");
        Assert.Equal("/opt/bin/git-review", r.Command);
        Assert.Equal(new[] { "start", "--", "f" }, r.Args);
    }

    /// <summary>
    /// The dispatcher is a POSIX script with no extension, and Windows cannot exec
    /// one: it goes through sh, with the script as the first argument.
    /// </summary>
    [Fact]
    public void Windows_runs_an_extensionless_dispatcher_through_sh()
    {
        var r = ResolveCommand.Resolve("next", Array.Empty<string>(), "C:\\repo\\bin\\git-review", "win32");
        Assert.Equal("sh", r.Command);
        Assert.Equal(new[] { "C:\\repo\\bin\\git-review", "next" }, r.Args);
    }

    [Fact]
    public void Windows_runs_a_native_executable_directly()
    {
        foreach (var exe in new[] { "C:\\git-review.exe", "C:\\git-review.CMD", "C:\\git-review.bat" })
        {
            var r = ResolveCommand.Resolve("next", Array.Empty<string>(), exe, "win32");
            Assert.Equal(exe, r.Command);
            Assert.Equal(new[] { "next" }, r.Args);
        }
    }

    [Fact]
    public void Posix_never_inserts_sh_even_without_an_extension()
    {
        var r = ResolveCommand.Resolve("next", Array.Empty<string>(), "/usr/local/bin/git-review", "posix");
        Assert.Equal("/usr/local/bin/git-review", r.Command);
        Assert.Equal(new[] { "next" }, r.Args);
    }
}

public class TimeoutClassTests
{
    [Fact]
    public void Reads_get_the_short_timeout()
    {
        Assert.Equal(TimeoutClass.ReadTimeoutMs, TimeoutClass.TimeoutForClass("status", Array.Empty<string>()));
        Assert.Equal(TimeoutClass.ReadTimeoutMs, TimeoutClass.TimeoutForClass("list", new[] { "--porcelain" }));
        Assert.Equal(TimeoutClass.ReadTimeoutMs, TimeoutClass.TimeoutForClass("config", new[] { "--porcelain" }));
        Assert.Equal(TimeoutClass.ReadTimeoutMs, TimeoutClass.TimeoutForClass("--version", Array.Empty<string>()));
    }

    [Fact]
    public void Local_mutations_get_the_long_one()
    {
        var verbs = new[]
        {
            "finish", "save", "abort", "continue", "next", "prev",
            "clean", "compare", "walkthrough", "preview",
        };
        foreach (var verb in verbs)
            Assert.Equal(TimeoutClass.LocalMutationTimeoutMs, TimeoutClass.TimeoutForClass(verb, Array.Empty<string>()));
    }

    /// <summary>
    /// start always fetches, and so does <c>forget --delta --stale</c> — the one
    /// housekeeping action that has to reach the remote to know what is stale.
    /// </summary>
    [Fact]
    public void Network_verbs_get_the_network_timeout()
    {
        Assert.Equal(TimeoutClass.NetworkMutationTimeoutMs, TimeoutClass.TimeoutForClass("start", Array.Empty<string>()));
        Assert.Equal(
            TimeoutClass.NetworkMutationTimeoutMs,
            TimeoutClass.TimeoutForClass("forget", new[] { "--delta", "--stale" }));
        Assert.Equal(
            TimeoutClass.LocalMutationTimeoutMs,
            TimeoutClass.TimeoutForClass("forget", new[] { "--saved", "--all" }));
    }

    [Fact]
    public void Class_timeouts_are_ordered_and_named()
    {
        Assert.Equal(TimeoutClass.ReadTimeoutMs, TimeoutClass.TimeoutMs(InvocationClass.Read));
        Assert.Equal(TimeoutClass.LocalMutationTimeoutMs, TimeoutClass.TimeoutMs(InvocationClass.LocalMutation));
        Assert.Equal(TimeoutClass.NetworkMutationTimeoutMs, TimeoutClass.TimeoutMs(InvocationClass.Network));
        Assert.Equal(TimeoutClass.SupportGitTimeoutMs, TimeoutClass.TimeoutMs(InvocationClass.SupportGit));
        Assert.True(TimeoutClass.ReadTimeoutMs < TimeoutClass.SupportGitTimeoutMs);
        Assert.True(TimeoutClass.SupportGitTimeoutMs < TimeoutClass.LocalMutationTimeoutMs);
        Assert.True(TimeoutClass.LocalMutationTimeoutMs < TimeoutClass.NetworkMutationTimeoutMs);
    }
}
