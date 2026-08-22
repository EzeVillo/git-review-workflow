namespace GitReview.Domain;

/// <summary>
/// What to watch to see a draft grow.
///
/// The reviewer's draft lives in the gitdir (<c>&lt;gitdir&gt;/review-walkthrough/
/// &lt;src&gt;.md</c>), outside the working tree and outside the refs: an agent filling it
/// in moves no HEAD, touches no index and writes no config, so none of the panel's
/// refresh signals sees it. Without a watcher the progress on the draft block stays
/// frozen at 3/9 until somebody hits Refresh -- exactly while the reviewer is looking
/// at the panel to find out whether the agent is done.
///
/// The directories come from the paths the CLI already reported (the <c>draft</c>
/// records of <c>config --porcelain</c> and <c>status --porcelain</c>), never from
/// rebuilding the gitdir layout -- the same rule that has *Open draft* open the path
/// the CLI gave instead of deriving it. Deliberate consequence: a draft in a directory
/// no report has named yet has nobody watching it.
/// </summary>
public static class DraftWatch
{
    /// <summary>
    /// The directories to watch, unique and in a stable order -- the order is what lets
    /// the caller compare two results instead of rebuilding the watchers on every
    /// refresh, and rebuilding them drops the events that land while it happens.
    /// </summary>
    public static IReadOnlyList<string> WatchDirs(ReviewState state)
    {
        var dirs = new SortedSet<string>(StringComparer.Ordinal);
        Add(state.DraftPath);
        foreach (var draft in state.DraftsList) Add(draft.Path);
        return dirs.ToArray();

        void Add(string? file)
        {
            var dir = ContainerOf(file);
            if (dir is not null) dirs.Add(dir);
        }
    }

    /// <summary>
    /// Whether <paramref name="file"/> is one of the authoring guides the CLI
    /// reported.
    ///
    /// The guides get no watcher of their own, and that is deliberate: the reviewer's
    /// lives in the ROOT of the gitdir, which changes on every git operation, so
    /// watching that directory would be a storm of notifications over the file that
    /// changes least. The document save is the exact signal instead, and it only fires
    /// on paths the CLI already reported -- the same reported-path rule that has Open
    /// open what the CLI gave instead of deriving it.
    ///
    /// Without it there is one moment the panel lies: you press Create, the empty file
    /// opens, you write the conventions, Ctrl+S -- and the badge still says "empty",
    /// because the state comes off the disk and nobody looked again.
    /// </summary>
    public static bool IsReportedGuide(ReviewState state, string? file)
    {
        if (string.IsNullOrWhiteSpace(file)) return false;
        var target = Normalise(file!);
        foreach (var guide in state.GuidesList)
        {
            if (string.Equals(Normalise(guide.Path), target, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static string Normalise(string path) => path.Replace('\\', '/');

    /// <summary>The directory holding <paramref name="file"/>, or null.</summary>
    private static string? ContainerOf(string? file)
    {
        if (string.IsNullOrWhiteSpace(file)) return null;
        // Both separators: the CLI resolves with `git rev-parse --absolute-git-dir`,
        // which answers with '/' even on Windows, and FileSystemWatcher takes either.
        var cut = Math.Max(file!.LastIndexOf('/'), file.LastIndexOf('\\'));
        return cut > 0 ? file.Substring(0, cut) : null;
    }
}
