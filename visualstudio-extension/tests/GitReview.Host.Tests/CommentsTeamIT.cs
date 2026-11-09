using System.Diagnostics;
using GitReview.Domain;
using Xunit;

namespace GitReview.Host.Tests;

public class CommentsTeamIT
{
    [Theory]
    [InlineData("ff")]
    [InlineData("merge")]
    [InlineData("squash")]
    public async Task Real_client_round_trips_author_replies_and_isolates_branches_after_merge(string strategy)
    {
        var source = new DirectoryInfo(AppContext.BaseDirectory);
        while (source is not null && !File.Exists(Path.Combine(source.FullName, "bin/git-review"))) source = source.Parent;
        Assert.NotNull(source);
        var root = Path.Combine(Path.GetTempPath(), "comments-team-vs-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var script = Path.Combine(source!.FullName, "tests/helpers/comments-team-history.sh");
        var cwd = Path.Combine(root, "reviewer");
        var cli = new CliInvoker(() => Path.Combine(source.FullName, "bin/git-review"));
        var refreshes = 0;
        var actions = new CommentsActions(cli, new MutationLock(), _ => Task.FromResult(CommentBufferSave.Unchanged), () => { refreshes++; return Task.CompletedTask; });
        async Task Review(string verb, params string[] args)
        {
            var result = await cli.InvokeAsync(verb, args, cwd);
            Assert.True(result.ExitCode == 0, result.Stderr);
        }
        async Task Add(string kind, string text)
        {
            var report = await actions.ReadAsync(cwd);
            Assert.NotNull(report.Guard);
            var result = await actions.RunAsync(cwd, "add", kind, null, report.Guard!, input: text);
            Assert.NotNull(result);
            Assert.True(result!.ExitCode == 0, $"Exit={result.ExitCode}, timed out={result.TimedOut}, error={result.ErrorCode}: {result.Stderr}");
        }
        try
        {
            Run(script, "init", root);
            await Review("start", "--no-walk", "feature/team");
            await Add("local", "Private reviewer sentinel");
            await Add("shared", "Reviewer question");
            var first = await actions.ReadAsync(cwd);
            var context = first.Documents.Single(d => d.Kind == "shared").Context;
            await Review("finish");
            Assert.DoesNotContain("Private reviewer sentinel", File.ReadAllText(Path.Combine(cwd, ".review/comments.md")));
            Run(script, "publish", root);
            await Review("clean", "feature/team");
            await Review("start", "--no-walk", "feature/team");
            await Review("comments", "init", "--document", "shared");
            var continued = await actions.ReadAsync(cwd);
            var shared = continued.Documents.Single(d => d.Kind == "shared");
            Assert.Equal(context, shared.Context);
            Assert.DoesNotContain(continued.Records("comments-diagnostic"), row => row[1] == "source-conflict");
            Assert.Contains("Author response", File.ReadAllText(shared.Path));
            Assert.Contains("Author response", File.ReadAllText(Path.Combine(cwd, ".review/comments.md")));
            File.Copy(Path.Combine(cwd, ".review/comments.md"), shared.Path, overwrite: true);
            Assert.Contains("Author response", File.ReadAllText(shared.Path));
            await Review("finish");
            Assert.DoesNotContain((await actions.ReadAsync(cwd)).Records("comments-diagnostic"), row => row[1] == "source-conflict");
            Run(script, "merge", root, strategy);
            foreach (var branch in new[] { "before-merge", "after-merge" })
            {
                await Review("start", "--no-walk", branch);
                var report = await actions.ReadAsync(cwd);
                Assert.Equal("fresh", report.Records("comments-identity").Single()[0]);
                await Add("shared", "Independent question");
                report = await actions.ReadAsync(cwd);
                shared = report.Documents.Single(d => d.Kind == "shared" && d.Context != context);
                Assert.Contains("Independent question", File.ReadAllText(shared.Path));
                Assert.DoesNotContain("Author response", File.ReadAllText(shared.Path));
                await Review("abort");
            }
            Assert.Equal(4, refreshes);
        }
        finally
        {
            // Git object files are read-only on Windows, including hardlinks
            // created by local clones. Do not hide an assertion behind cleanup.
            foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
                File.SetAttributes(file, FileAttributes.Normal);
            Directory.Delete(root, recursive: true);
        }
    }

    private static void Run(string script, params string[] args)
    {
        var start = new ProcessStartInfo("sh") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
        start.ArgumentList.Add(script);
        foreach (var arg in args) start.ArgumentList.Add(arg);
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        Assert.True(process.WaitForExit(30000), "Git fixture timed out");
        Assert.True(process.ExitCode == 0, error.GetAwaiter().GetResult() + output.GetAwaiter().GetResult());
    }
}
