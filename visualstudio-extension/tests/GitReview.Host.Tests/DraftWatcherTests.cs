using Xunit;

namespace GitReview.Host.Tests;

/// <summary>
/// The watcher against a real directory: what it covers -- an OS event arriving for a
/// file this process did not write through any API of ours -- cannot be faked without
/// testing the fake. Same reason CliInvokerTests spawns real git.
/// </summary>
public class DraftWatcherTests : IDisposable
{
    private readonly string _dir = Path.Combine(
        Path.GetTempPath(), "git-review-draft-watcher", Guid.NewGuid().ToString("N"));

    public DraftWatcherTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        try
        {
            Directory.Delete(_dir, recursive: true);
        }
        catch
        {
            // A leftover temp directory is not worth failing a test over.
        }
    }

    private static async Task<bool> Fired(Task signal, int ms = 5000) =>
        signal == await Task.WhenAny(signal, Task.Delay(ms)).ConfigureAwait(false);

    [Fact]
    public async Task AMarkdownFileWrittenInAWatchedDirectoryWakesThePanel()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        watcher.Sync(new[] { _dir });

        File.WriteAllText(Path.Combine(_dir, "feature.md"), "## 1. src/a.ts");

        Assert.True(await Fired(signal.Task), "the write raised no event");
    }

    [Fact]
    public async Task WithoutSyncNothingIsWatched()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => signal.TrySetResult(true));

        File.WriteAllText(Path.Combine(_dir, "feature.md"), "## 1. src/a.ts");

        Assert.False(await Fired(signal.Task, 1500), "fired for a directory nobody asked for");
    }

    [Fact]
    public async Task WhatGitDropsBesideTheDraftIsNotADraft()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        watcher.Sync(new[] { _dir });

        File.WriteAllText(Path.Combine(_dir, "index.lock"), "x");

        Assert.False(await Fired(signal.Task, 1500), "fired for a file that is not a draft");
    }

    [Fact]
    public async Task SyncingTheSameSetAgainKeepsWatching()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        watcher.Sync(new[] { _dir });
        // The no-op path: every refresh calls Sync with the same set, and a rebuild
        // there would drop the events landing while it happens.
        watcher.Sync(new[] { _dir });

        File.WriteAllText(Path.Combine(_dir, "feature.md"), "## 1. src/a.ts");

        Assert.True(await Fired(signal.Task), "the second Sync stopped the watcher");
    }

    [Fact]
    public async Task ADirectoryThatIsGoneIsOneFewerThingToWatch()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        // A `forget --draft` from a terminal between the report and this call.
        var missing = Path.Combine(_dir, "gone");
        watcher.Sync(new[] { missing, _dir });

        File.WriteAllText(Path.Combine(_dir, "feature.md"), "## 1. src/a.ts");

        Assert.True(await Fired(signal.Task), "a missing directory took the live one down with it");
    }

    [Fact]
    public async Task AfterDisposeThePanelIsNotWokenAgain()
    {
        var signal = new TaskCompletionSource<bool>();
        var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        watcher.Sync(new[] { _dir });
        watcher.Dispose();

        File.WriteAllText(Path.Combine(_dir, "feature.md"), "## 1. src/a.ts");

        Assert.False(await Fired(signal.Task, 1500), "fired after dispose");
    }
}
