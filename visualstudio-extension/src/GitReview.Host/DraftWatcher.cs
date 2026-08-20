using System.Linq;

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

    private readonly Action _onChange;
    private readonly object _gate = new();
    private readonly List<FileSystemWatcher> _watchers = new();
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
            foreach (var dir in dirs)
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
                    continue;
                }
                watcher.Created += OnChanged;
                watcher.Changed += OnChanged;
                watcher.Deleted += OnChanged;
                watcher.Renamed += OnRenamed;
                try
                {
                    watcher.EnableRaisingEvents = true;
                }
                catch (Exception)
                {
                    watcher.Dispose();
                    continue;
                }
                _watchers.Add(watcher);
            }
        }
    }

    private void OnChanged(object sender, FileSystemEventArgs e) => Schedule();

    private void OnRenamed(object sender, RenamedEventArgs e) => Schedule();

    private void Schedule()
    {
        lock (_gate)
        {
            if (_disposed) return;
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
            _dirs = Array.Empty<string>();
        }
        _debounce.Dispose();
    }
}
