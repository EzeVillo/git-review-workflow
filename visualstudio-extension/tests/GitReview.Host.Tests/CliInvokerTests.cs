using System.Text;
using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;

/// <summary>
/// The one place that actually spawns something. These run against real git, which
/// every runner of this repo has: what they cover — UTF-8 capture, the cwd, an
/// executable that is not there — cannot be faked without testing the fake.
/// </summary>
[Collection(CliLogCollection.Name)]
public class CliInvokerTests : IDisposable
{
    private readonly string _dir = Path.Combine(
        Path.GetTempPath(), "git-review-host-tests", Guid.NewGuid().ToString("N"));

    public CliInvokerTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        try
        {
            foreach (var f in Directory.EnumerateFiles(_dir, "*", SearchOption.AllDirectories))
                File.SetAttributes(f, FileAttributes.Normal);
            Directory.Delete(_dir, recursive: true);
        }
        catch
        {
            // A leftover temp directory is not worth failing a test over.
        }
    }

    private static Task<InvokeResult> Git(string cwd, params string[] args) =>
        new CliInvoker().InvokeResolvedAsync(
            new ResolvedCommand("git", args), cwd, network: false, timeoutMs: 30_000);

    [Fact]
    public async Task A_real_invocation_captures_stdout_and_the_exit_code()
    {
        var result = await Git(_dir, "--version");
        Assert.Equal(0, result.ExitCode);
        Assert.Null(result.ErrorCode);
        Assert.False(result.TimedOut);
        Assert.StartsWith("git version", result.Stdout);
    }

    /// <summary>
    /// Non-ASCII has to survive the pipe. It is forced to UTF-8 on both streams
    /// because the console code page on Windows is not, and a subject or a path with
    /// an accent in it comes back mangled otherwise.
    /// </summary>
    [Fact]
    public async Task Output_is_captured_as_utf8()
    {
        Assert.Equal(0, (await Git(_dir, "init", "-q")).ExitCode);
        await File.WriteAllTextAsync(Path.Combine(_dir, "café.txt"), "hola\n", new UTF8Encoding(false));
        Assert.Equal(0, (await Git(_dir, "add", "-A")).ExitCode);
        var commit = await Git(
            _dir,
            "-c", "user.email=test@example.com", "-c", "user.name=Test",
            "commit", "-q", "-m", "acción é ñ");
        Assert.Equal(0, commit.ExitCode);

        var subject = await Git(_dir, "log", "-1", "--format=%s");
        Assert.Equal("acción é ñ", subject.Stdout.Trim());

        var files = await Git(_dir, "-c", "core.quotePath=false", "show", "--name-only", "--format=", "HEAD");
        Assert.Contains("café.txt", files.Stdout);
    }

    /// <summary>
    /// The cwd is the repo root, not the process's — running in the wrong directory
    /// is how a review reads another repository's state.
    /// </summary>
    [Fact]
    public async Task The_working_directory_is_the_one_it_was_given()
    {
        var inside = Path.Combine(_dir, "inside");
        Directory.CreateDirectory(inside);
        Assert.Equal(0, (await Git(inside, "init", "-q")).ExitCode);

        var toplevel = await Git(inside, "rev-parse", "--show-toplevel");
        Assert.Equal(0, toplevel.ExitCode);
        Assert.Equal(
            Path.GetFileName(inside),
            Path.GetFileName(toplevel.Stdout.Trim().TrimEnd('/')));
    }

    [Fact]
    public async Task A_failing_command_carries_its_stderr_and_exit_code()
    {
        var result = await Git(_dir, "rev-parse", "--verify", "refs/heads/does-not-exist");
        Assert.NotEqual(0, result.ExitCode);
        Assert.Null(result.ErrorCode);
        Assert.False(string.IsNullOrWhiteSpace(result.Stderr));
    }

    /// <summary>
    /// An executable that is not on PATH is an error code, not an exception and not
    /// a zero exit — the refresh pipeline reads exactly this to decide "CLI missing".
    /// </summary>
    [Fact]
    public async Task A_missing_executable_comes_back_as_an_error_code()
    {
        var result = await new CliInvoker().InvokeResolvedAsync(
            new ResolvedCommand("git-review-does-not-exist", Array.Empty<string>()),
            _dir, network: false, timeoutMs: 10_000);
        Assert.NotNull(result.ErrorCode);
        Assert.Null(result.ExitCode);
        Assert.False(result.TimedOut);
    }

    /// <summary>
    /// With no configured path the invocation goes through <c>git review</c>, which
    /// is how the CLI is reached when it is installed on PATH.
    /// </summary>
    [Fact]
    public async Task Without_a_configured_path_it_invokes_git_review()
    {
        var result = await new CliInvoker().InvokeAsync(
            "--version", Array.Empty<string>(), _dir, timeoutMs: 30_000);
        // Either the CLI is installed here or git says it is not a git command; both
        // are answers from `git review`, which is what this asserts.
        var text = result.Stdout + result.Stderr;
        Assert.False(string.IsNullOrWhiteSpace(text));
    }

    /// <summary>
    /// A network invocation must never let git open a credential prompt: a blocked
    /// prompt is a spawn that hangs until the timeout with no way to answer it.
    /// </summary>
    [Fact]
    public void The_askpass_helper_exists_and_is_a_no_op()
    {
        var askpass = CliInvoker.ResolveAskpassCommand();
        Assert.True(File.Exists(askpass), $"askpass helper missing at {askpass}");
        var body = File.ReadAllText(askpass);
        Assert.Contains("exit", body);
    }

    [Fact]
    public async Task Every_invocation_is_written_to_the_log_sink()
    {
        CliInvoker.CliLogSink.Clear();
        await Git(_dir, "--version");
        var lines = CliInvoker.CliLogSink.Snapshot();
        Assert.Contains(lines, l => l.StartsWith("→ git --version", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.StartsWith("← exit 0", StringComparison.Ordinal));
        Assert.Contains(lines, l => l.Contains($"cwd={_dir}", StringComparison.Ordinal));
    }

    [Fact]
    public async Task The_log_callback_sees_the_same_lines_as_the_sink()
    {
        var logged = new List<string>();
        var invoker = new CliInvoker(log: logged.Add);
        await invoker.InvokeResolvedAsync(
            new ResolvedCommand("git", new[] { "--version" }), _dir, false, 30_000);
        Assert.Contains(logged, l => l.StartsWith("→ git --version", StringComparison.Ordinal));
        Assert.Contains(logged, l => l.StartsWith("← exit 0", StringComparison.Ordinal));
    }
}

/// <summary>
/// The sink is process-global, so these share a collection with the invoker tests:
/// xUnit runs classes in parallel, and two of them clearing the same ring buffer is
/// a flake, not a finding.
/// </summary>
[CollectionDefinition(CliLogCollection.Name, DisableParallelization = true)]
public sealed class CliLogCollection
{
    public const string Name = "cli-log";
}

[Collection(CliLogCollection.Name)]
public class CliLogSinkTests
{
    /// <summary>
    /// A ring buffer, so a long review does not grow it without bound and the last
    /// lines — the ones anyone opening the log wants — are the ones kept.
    /// </summary>
    [Fact]
    public void The_sink_keeps_the_most_recent_lines_and_drops_the_rest()
    {
        CliInvoker.CliLogSink.Clear();
        Assert.Empty(CliInvoker.CliLogSink.Snapshot());

        for (var i = 0; i < 600; i++) CliInvoker.CliLogSink.Append($"line {i}");
        var lines = CliInvoker.CliLogSink.Snapshot();
        Assert.Equal(500, lines.Count);
        Assert.Equal("line 100", lines[0]);
        Assert.Equal("line 599", lines[^1]);

        CliInvoker.CliLogSink.Clear();
        Assert.Empty(CliInvoker.CliLogSink.Snapshot());
    }

    /// <summary>The snapshot is a copy: iterating it while the CLI logs must not throw.</summary>
    [Fact]
    public void A_snapshot_is_not_affected_by_later_writes()
    {
        CliInvoker.CliLogSink.Clear();
        CliInvoker.CliLogSink.Append("first");
        var snapshot = CliInvoker.CliLogSink.Snapshot();
        CliInvoker.CliLogSink.Append("second");
        Assert.Single(snapshot);
        Assert.Equal(2, CliInvoker.CliLogSink.Snapshot().Count);
        CliInvoker.CliLogSink.Clear();
    }
}
