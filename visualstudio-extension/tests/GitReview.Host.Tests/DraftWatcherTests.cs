using System.Reflection;
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

    /// <summary>
    /// Raise a real <see cref="FileSystemWatcher.Error"/> on a live watcher, through
    /// the protected member .NET itself calls. The two things that raise it for real
    /// -- an internal buffer overflow and a watched directory that goes away -- are
    /// respectively a race against thousands of writes and an OS error code that is
    /// not the same everywhere, so neither can carry a test. What is being tested is
    /// what this class does once the error arrives.
    /// </summary>
    private static void RaiseError(FileSystemWatcher watcher)
    {
        var onError = typeof(FileSystemWatcher).GetMethod(
            "OnError", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.NotNull(onError);
        onError!.Invoke(
            watcher,
            new object[] { new ErrorEventArgs(new InternalBufferOverflowException()) });
    }

    [Fact]
    public async Task AnErrorRebuildsTheWatcherAndRefreshes()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        watcher.Sync(new[] { _dir });
        var dead = Assert.Single(watcher.LiveWatchers);

        RaiseError(dead);

        // The events swallowed by the error are never redelivered, so reviving the
        // watcher without a refresh leaves the panel on the old count.
        Assert.True(await Fired(signal.Task), "the error refreshed nothing");
        var live = Assert.Single(watcher.LiveWatchers);
        Assert.NotSame(dead, live);
        Assert.Equal(dead.Path, live.Path);
        Assert.True(live.EnableRaisingEvents);
    }

    [Fact]
    public async Task TheRebuiltWatcherStillWakesThePanel()
    {
        var signal = new TaskCompletionSource<bool>();
        // The callback reads the variable, not its value: swapping it below moves the
        // next refresh onto a fresh signal, so the write is told apart from the error.
        using var watcher = new DraftWatcher(() => Volatile.Read(ref signal).TrySetResult(true));
        watcher.Sync(new[] { _dir });

        RaiseError(Assert.Single(watcher.LiveWatchers));
        Assert.True(await Fired(signal.Task), "the error refreshed nothing");

        signal = new TaskCompletionSource<bool>();
        File.WriteAllText(Path.Combine(_dir, "feature.md"), "## 1. src/a.ts");

        Assert.True(await Fired(signal.Task), "the rebuilt watcher is not armed");
    }

    [Fact]
    public async Task AnErrorOnADirectoryThatIsGoneRebuildsNothing()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        var doomed = Path.Combine(_dir, "review-walkthrough");
        Directory.CreateDirectory(doomed);
        watcher.Sync(new[] { doomed });
        var dead = Assert.Single(watcher.LiveWatchers);

        Directory.Delete(doomed);
        RaiseError(dead);

        // Nothing to rebuild -- and nothing to retry either, which is what keeps a
        // rebuild from becoming a spin.
        Assert.Empty(watcher.LiveWatchers);
        // The draft going away is still a change the panel has to hear about.
        Assert.True(await Fired(signal.Task), "the directory going away refreshed nothing");
    }

    [Fact]
    public async Task AnErrorAfterDisposeRebuildsNothing()
    {
        var signal = new TaskCompletionSource<bool>();
        var watcher = new DraftWatcher(() => signal.TrySetResult(true));
        watcher.Sync(new[] { _dir });
        var dead = Assert.Single(watcher.LiveWatchers);
        watcher.Dispose();

        RaiseError(dead);

        Assert.Empty(watcher.LiveWatchers);
        Assert.False(await Fired(signal.Task, 1500), "rebuilt after dispose");
    }

    [Fact]
    public void AWatcherThatKeepsFailingIsNotRebuiltForever()
    {
        using var watcher = new DraftWatcher(() => { });
        watcher.Sync(new[] { _dir });

        // Every rebuild fails again the moment it is armed. Nothing here writes a
        // file, so no delivered event clears the budget.
        for (var i = 0; i < DraftWatcher.MaxRearms; i++)
        {
            RaiseError(Assert.Single(watcher.LiveWatchers));
        }

        RaiseError(Assert.Single(watcher.LiveWatchers));

        Assert.Empty(watcher.LiveWatchers);
    }

    [Fact]
    public async Task AnEventDeliveredClearsTheRebuildBudget()
    {
        var signal = new TaskCompletionSource<bool>();
        using var watcher = new DraftWatcher(() => Volatile.Read(ref signal).TrySetResult(true));
        watcher.Sync(new[] { _dir });
        for (var i = 0; i < DraftWatcher.MaxRearms; i++)
        {
            RaiseError(Assert.Single(watcher.LiveWatchers));
        }
        // Drain the refresh the errors scheduled, so the next signal can only come
        // from the write below -- the debounce is one-shot and nothing else is armed.
        Assert.True(await Fired(signal.Task), "the errors refreshed nothing");

        signal = new TaskCompletionSource<bool>();
        File.WriteAllText(Path.Combine(_dir, "feature.md"), "## 1. src/a.ts");
        Assert.True(await Fired(signal.Task), "the rebuilt watcher is not armed");

        // A watcher that delivers is a working watcher: a session long enough to
        // overflow more than three times must not end up unwatched.
        signal = new TaskCompletionSource<bool>();
        var dead = Assert.Single(watcher.LiveWatchers);
        RaiseError(dead);

        var live = Assert.Single(watcher.LiveWatchers);
        Assert.NotSame(dead, live);
        Assert.True(await Fired(signal.Task), "the error refreshed nothing");
    }
}
