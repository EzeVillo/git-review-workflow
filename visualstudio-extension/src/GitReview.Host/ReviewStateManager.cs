using GitReview.Domain;

namespace GitReview.Host;

/// <summary>
/// Refresh pipeline: version probe → status --porcelain → list/config when needed.
/// Sole source of ReviewState for the panel.
/// </summary>
public sealed class ReviewStateManager
{
    private readonly CliInvoker _cli;
    private readonly Func<IReadOnlyList<string>> _repoRoots;
    private readonly Func<string?> _gitReviewPath;
    private ReviewState _state = new(Situation.CliMissing);
    private readonly object _gate = new();
    private int _refreshGen;

    public event Action<ReviewState>? StateChanged;

    public ReviewState Current
    {
        get { lock (_gate) return _state; }
    }

    /// <summary>
    /// False until a refresh has resolved a state. The seed above is a placeholder,
    /// not an answer, and drawing it tells the reviewer the CLI is missing before
    /// anyone has looked -- so the panel waits instead. Same rule as the JetBrains
    /// service's hasResolvedState and the extension's empty webview.
    /// </summary>
    public bool HasResolved { get; private set; }

    public ReviewStateManager(
        CliInvoker cli,
        Func<IReadOnlyList<string>> repoRoots,
        Func<string?>? gitReviewPath = null)
    {
        _cli = cli;
        _repoRoots = repoRoots;
        _gitReviewPath = gitReviewPath ?? (() => null);
    }

    public async Task<ReviewState> RefreshAsync(CancellationToken ct = default)
    {
        var gen = Interlocked.Increment(ref _refreshGen);
        var roots = _repoRoots();
        var sole = SoleTarget.PickSoleTarget(roots);

        if (roots.Count > 1)
        {
            return Publish(new ReviewState(
                Situation.Error,
                Stderr: "Open a single-folder workspace that is a git repository. git review uses one root (like the CLI cwd); multi-root is not supported."), gen);
        }

        if (sole is null)
        {
            return Publish(new ReviewState(
                Situation.Error,
                Stderr: UserCopy.NoSoleRoot), gen);
        }

        // Version probe: `git review --version` (verb is the flag after "review").
        var ver = await _cli.InvokeAsync("--version", Array.Empty<string>(), sole, cancellationToken: ct)
            .ConfigureAwait(false);

        if (IsMissing(ver))
        {
            return Publish(new ReviewState(
                Situation.CliMissing,
                Stderr: string.IsNullOrWhiteSpace(ver.Stderr) ? "not found" : ver.Stderr), gen);
        }

        var versionLine = CliMessage.FirstCliLine(ver.Stdout);
        if (string.IsNullOrEmpty(versionLine))
        {
            // Some builds print version on stderr or fail only on status; continue.
        }
        else if (CliVersion.IsOutdated(versionLine))
        {
            return Publish(new ReviewState(Situation.CliOutdated, Stderr: versionLine), gen);
        }

        var status = await _cli.InvokeAsync(
                "status", new[] { "--porcelain" }, sole, cancellationToken: ct)
            .ConfigureAwait(false);

        if (IsMissing(status))
        {
            return Publish(new ReviewState(
                Situation.CliMissing,
                Stderr: CliMessage.CliErrorText(status.Stderr, status.Stdout, "CLI not found")), gen);
        }

        if (status.TimedOut)
        {
            return Publish(new ReviewState(
                Situation.Error,
                Stderr: "status --porcelain timed out"), gen);
        }

        var exit = status.ExitCode;
        ReviewState next;

        if (exit == 3)
        {
            // Out of range: the walk cursor no longer meets the range, usually because
            // the reviewer committed on top of the staged diff. The CLI writes that to
            // stderr and prints no porcelain at all, so this must not be parsed -- it
            // used to be, which made the entry that the reviewer can act on ("undo the
            // commits with git reset --soft, or abort") come out of the panel as
            // "porcelain output has no state record" under a generic error.
            next = new ReviewState(Situation.OutOfRange, Stderr: status.Stderr);
        }
        else if (exit == 0)
        {
            try
            {
                var parsed = Porcelain.ParsePorcelain(status.Stdout);
                var hasConflict = parsed.Finish is not null;
                var situation = SituationIds.For(exit, hasConflict, hasFinishPending: false);
                next = new ReviewState(
                    Situation: situation,
                    State: parsed.State,
                    Entries: parsed.Entries,
                    Files: parsed.FilesList,
                    Subjects: parsed.Subjects,
                    Authors: parsed.Authors,
                    Base: parsed.Base,
                    Finish: parsed.Finish,
                    Readonly: parsed.Readonly,
                    KeysOnly: parsed.KeysOnly,
                    Draft: parsed.Draft);
            }
            catch (Exception e)
            {
                // What the CLI said beats what the parser says: porcelain it could not
                // read is more often a CLI that already explained itself than a bug in
                // the tokenizer, and the reviewer can act on the former.
                next = new ReviewState(
                    Situation.Error,
                    Stderr: status.Stderr.Trim().Length > 0 ? status.Stderr : e.Message);
            }
        }
        else if (exit == 2)
        {
            // no-review: list + config
            var listTask = _cli.InvokeAsync("list", new[] { "--porcelain" }, sole, cancellationToken: ct);
            var configTask = _cli.InvokeAsync("config", new[] { "--porcelain" }, sole, cancellationToken: ct);
            await Task.WhenAll(listTask, configTask).ConfigureAwait(false);
            var list = await listTask.ConfigureAwait(false);
            var config = await configTask.ConfigureAwait(false);

            var branches = list.ExitCode == 0
                ? Porcelain.ParseListPorcelain(list.Stdout)
                : Array.Empty<BranchRecord>();
            EffectiveConfig? eff = null;
            IReadOnlyList<CandidateBranch>? candidates = null;
            IReadOnlyList<CandidateRemote>? remotes = null;
            if (config.ExitCode == 0)
            {
                try
                {
                    var cp = ConfigPorcelain.ParseConfigPorcelain(config.Stdout);
                    eff = cp.Config;
                    candidates = cp.Candidates;
                    remotes = cp.Remotes;
                }
                catch { /* leave null */ }
            }

            var hasPending = branches.Any(b => b.Finish?.State == "pending");
            var situation = SituationIds.For(2, hasFinishConflict: false, hasFinishPending: hasPending);
            next = new ReviewState(
                Situation: situation,
                Branches: branches,
                Config: eff,
                Candidates: candidates,
                Remotes: remotes);
        }
        else
        {
            next = new ReviewState(
                Situation.Error,
                Stderr: CliMessage.CliErrorText(
                    status.Stderr, status.Stdout, "Something went wrong reading the review state."));
        }

        return Publish(next, gen);
    }

    private static bool IsMissing(InvokeResult r) =>
        r.ErrorCode is not null
        || (r.ExitCode is not null and not 0
            && (r.Stderr.Contains("is not a git command", StringComparison.OrdinalIgnoreCase)
                || r.Stderr.Contains("not found", StringComparison.OrdinalIgnoreCase)
                || r.Stderr.Contains("ENOENT", StringComparison.OrdinalIgnoreCase)
                || r.ErrorCode is "Win32Exception" or "FileNotFoundException"));

    private ReviewState Publish(ReviewState state, int gen)
    {
        if (gen != Volatile.Read(ref _refreshGen)) return Current;
        HasResolved = true;
        lock (_gate) _state = state;
        StateChanged?.Invoke(state);
        return state;
    }
}
