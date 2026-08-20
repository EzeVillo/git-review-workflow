using System.Linq;
using System.Runtime.CompilerServices;

// The error path below is the one thing here a test cannot reach through the public
// surface: raising a real FileSystemWatcher.Error takes the very instance this class
// subscribed to, and provoking the overflow that raises it for real needs thousands
// of writes and a losing race. The two internal members exist for that, and only
// that -- no product code reads either.
[assembly: InternalsVisibleTo("GitReview.Host.Tests")]

namespace GitReview.Host;

/// <summary>
/// The third refresh signal, and the only one that is not git: the directories where
/// the CLI said the drafts are (see <see cref="GitReview.Domain.DraftWatch"/>). An
/// agent filling a draft in writes to the gitdir, which neither the shell's events nor
/// the tool window's visibility ever hears about.
///
/// One watcher per directory, never recursive: the draft sits directly in the reported
/// directory, and a recursive watcher under the gitdir would wake the panel for
/// everything git writes there.
/// </summary>
public sealed class DraftWatcher : IDisposable
{
    /// <summary>
    /// Writing a draft is a rename (Created) that usually brings its Changed along,
    /// and an agent can rewrite the file several times in a row; without this each
    /// pass would cost a full refresh. Short all the same: what is being measured is
    /// "the panel reacts on its own", not "the panel reacts within the minute".
    /// </summary>
    public const int DebounceMs = 250;

    /// <summary>
    /// How many times in a row one directory's watcher is rebuilt after an error
    /// before this stops rebuilding it. A watcher that fails again the moment it is
    /// armed -- a path that is there but unreadable, a share that dropped -- would
    /// otherwise rebuild forever, one refresh per round. Any event actually delivered
    /// clears the count, so a long session that overflows more than three times keeps
    /// its watchers: the budget is about a watcher that cannot come back, not about a
    /// busy one.
    /// </summary>
    internal const int MaxRearms = 3;

    private readonly Action _onChange;
    private readonly object _gate = new();
    private readonly List<FileSystemWatcher> _watchers = new();
    private readonly Dictionary<string, int> _rearms = new(StringComparer.OrdinalIgnoreCase);
    private readonly System.Threading.Timer _debounce;
    private IReadOnlyList<string> _dirs = Array.Empty<string>();
    private bool _disposed;

    public DraftWatcher(Action onChange)
    {
        _onChange = onChange;
        _debounce = new System.Threading.Timer(_ => Fire(), null, Timeout.Infinite, Timeout.Infinite);
    }

    /// <summary>
    /// Point the watcher at <paramref name="dirs"/>. A no-op when the set did not
    /// change, which is the case on nearly every refresh: rebuilding the watchers
    /// drops the events that land while it happens.
    /// </summary>
    public void Sync(IReadOnlyList<string> dirs)
    {
        lock (_gate)
        {
            if (_disposed || _dirs.SequenceEqual(dirs)) return;
            _dirs = dirs;
            DisposeWatchers();
            _rearms.Clear();
            foreach (var dir in dirs)
            {
                var watcher = CreateWatcher(dir);
                if (watcher is not null) _watchers.Add(watcher);
            }
        }
    }

    /// <summary>
    /// Build and arm one watcher, or answer null when the directory cannot be watched.
    /// Both <see cref="Sync"/> and the rebuild after an error come through here: a
    /// rebuilt watcher subscribed to less than the original would go quiet in a way
    /// nothing reports.
    /// </summary>
    private FileSystemWatcher? CreateWatcher(string dir)
    {
        FileSystemWatcher watcher;
        try
        {
            // The directory can be gone between the report and this call
            // (a `forget --draft` from a terminal): that is not an error,
            // it is one fewer thing to watch until the next refresh.
            watcher = new FileSystemWatcher(dir, "*.md")
            {
                IncludeSubdirectories = false,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
            };
        }
        catch (ArgumentException)
        {
            return null;
        }
        watcher.Created += OnChanged;
        watcher.Changed += OnChanged;
        watcher.Deleted += OnChanged;
        watcher.Renamed += OnRenamed;
        watcher.Error += OnError;
        try
        {
            watcher.EnableRaisingEvents = true;
        }
        catch (Exception)
        {
            watcher.Dispose();
            return null;
        }
        return watcher;
    }

    private void OnChanged(object sender, FileSystemEventArgs e) => Schedule();

    private void OnRenamed(object sender, RenamedEventArgs e) => Schedule();

    /// <summary>
    /// The OS handed this watcher an error, and .NET's answer to one is to raise this
    /// and -- for everything except an internal buffer overflow -- to switch the
    /// watcher off. Measured on Windows against .NET 8: removing the watched directory
    /// raises a Win32 "access denied" and leaves EnableRaisingEvents false, so the
    /// directory coming back is never seen again; a buffer overflow keeps the watcher
    /// alive but drops what did not fit (3000 writes arrived as 3 events, with the
    /// overflow itself the only notice). Neither heals on its own, because
    /// <see cref="Sync"/> returns early for as long as the reported set of directories
    /// does not change -- which is every refresh of an ordinary session. Left alone,
    /// the draft progress in the panel freezes for the rest of that session while the
    /// agent is still writing, with nothing at all to show for it.
    ///
    /// Hence both halves. Rebuild the watcher, because a switched-off one never comes
    /// back; and refresh once, because the events lost inside the error are not
    /// redelivered, so a revived watcher on its own still leaves the panel on the old
    /// count. Raising InternalBufferSize is not the answer to either: it is
    /// non-paged pool, and it only widens the window.
    /// </summary>
    private void OnError(object sender, ErrorEventArgs e)
    {
        if (sender is not FileSystemWatcher dead) return;
        lock (_gate)
        {
            // Not ours any more: an error from a watcher that Sync or Dispose already
            // replaced is a report about something already dealt with.
            if (_disposed || !_watchers.Remove(dead)) return;
            var dir = dead.Path;
            dead.Dispose();
            if (Rearmable(dir))
            {
                var replacement = CreateWatcher(dir);
                if (replacement is not null) _watchers.Add(replacement);
            }
            // Scheduled even when nothing was rebuilt: what went away may be the draft
            // itself, and that is exactly the change the panel has to hear about.
            _debounce.Change(DebounceMs, Timeout.Infinite);
        }
    }

    /// <summary>
    /// Whether a watcher for <paramref name="dir"/> is worth building again. Called
    /// under <c>_gate</c>.
    /// </summary>
    private bool Rearmable(string dir)
    {
        // A directory that is gone cannot be watched, and asking the OS again on every
        // error is how a rebuild turns into a spin. CreateWatcher's ArgumentException
        // covers the race; this covers the standing case, before any work is done.
        if (!Directory.Exists(dir)) return false;
        _rearms.TryGetValue(dir, out var used);
        if (used >= MaxRearms) return false;
        _rearms[dir] = used + 1;
        return true;
    }

    private void Schedule()
    {
        lock (_gate)
        {
            if (_disposed) return;
            // An event delivered is proof the watchers are working, which is the only
            // question the rebuild budget is asking.
            _rearms.Clear();
            _debounce.Change(DebounceMs, Timeout.Infinite);
        }
    }

    private void Fire()
    {
        lock (_gate)
        {
            if (_disposed) return;
        }
        _onChange();
    }

    /// <summary>
    /// The live watchers. Test-only, and the minimum that lets a test raise a real
    /// <see cref="FileSystemWatcher.Error"/> on the instance this class subscribed to.
    /// </summary>
    internal IReadOnlyList<FileSystemWatcher> LiveWatchers
    {
        get
        {
            lock (_gate)
            {
                return _watchers.ToArray();
            }
        }
    }

    private void DisposeWatchers()
    {
        foreach (var watcher in _watchers)
        {
            watcher.EnableRaisingEvents = false;
            watcher.Dispose();
        }
        _watchers.Clear();
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            DisposeWatchers();
            _rearms.Clear();
            _dirs = Array.Empty<string>();
        }
        _debounce.Dispose();
    }
}
