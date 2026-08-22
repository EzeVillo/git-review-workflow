using System.Diagnostics;
using System.Windows;
using System.Windows.Threading;
using GitReview.Domain;
using GitReview.Host;
using DomainControl = GitReview.Domain.Control;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// Wires PanelView ↔ ReviewStateManager ↔ MutationRunner.
/// Host-agnostic enough to run in a WPF preview window or a VS tool window.
/// </summary>
public sealed class GitReviewPanelController : IDisposable
{
    private readonly PanelView _view;
    private readonly ReviewStateManager _state;
    private readonly MutationRunner _mutations;
    private readonly CliInvoker _cli;
    private readonly Func<IReadOnlyList<string>> _roots;
    private readonly Func<bool> _workspacePending;
    private readonly Func<string?> _cwd;
    private readonly Dispatcher _dispatcher;
    private readonly DispatcherTimer _probeTimer;
    private readonly DispatcherTimer _skeletonTimer;
    private readonly DispatcherTimer _whyCeilingTimer;
    private readonly IDisposable _busySub;
    private readonly IDisposable _discardSub;
    /// <summary>
    /// Refresh signal for the one thing that is neither git nor a mutation of ours:
    /// an agent filling in a draft. Fires off the UI thread, so it comes back through
    /// the dispatcher like everything else the panel draws.
    /// </summary>
    private readonly DraftWatcher _draftWatcher;
    private PanelWhy? _why;
    private string? _whyKey;
    private string? _lastOpened;
    private bool _refreshing;
    private bool _whyCeilingReached;
    private bool _panelVisible = true;
    private int _refreshSeq;
    private bool _disposed;
    private string _titleSignature = "";

    public PanelView View => _view;
    public ReviewStateManager State => _state;
    public MutationRunner Mutations => _mutations;

    /// <summary>The invoker the panel already uses, for hosts that need a raw call
    /// (the start wizard, and reading a file's base side for a diff).</summary>
    public CliInvoker Cli => _cli;

    /// <summary>
    /// The single git root this panel is showing, or null when there isn't exactly one.
    /// Resolved through the same <see cref="SoleTarget"/> rule the mutations use, so a
    /// host action and the CLI call it leads to can never end up in different repositories.
    /// </summary>
    public string? Cwd => _cwd();

    /// <summary>
    /// The why of the current walk entry as the panel has it -- the same value the
    /// rendered model carries. A host action that needs the text ("open in editor")
    /// reads it from here rather than rebuilding the model, which is built without
    /// the why and would therefore always look like one that is still loading.
    /// </summary>
    public PanelWhy? Why => EffectiveWhy;

    /// <summary>
    /// The why only while the entry it was read for is still the one on screen. The
    /// state and the why arrive separately -- a navigation publishes the new entry as
    /// soon as the verb returns, its prose a couple of seconds later -- so the loaded
    /// text has to be dropped the moment it stops belonging to what is drawn, or the
    /// new entry is briefly captioned with the previous entry's why. Same rule, and
    /// the same key, as the extension's whyTarget/whyKey.
    /// </summary>
    private PanelWhy? EffectiveWhy => _whyKey == WhyKeyOf(_state.Current) ? _why : null;

    /// <summary>The entry a why belongs to: the review branch plus the raw path.</summary>
    private static string? WhyKeyOf(ReviewState state)
    {
        var review = state.State;
        if (!SituationIds.IsReviewReadable(state.Situation) || review?.Mode != ReviewMode.Walk)
            return null;
        var entry = PanelModelBuilder.CurrentEntry(state.EntriesList, review.Position);
        return entry?.Id is PathRef pr ? review.Branch + pr.Raw : null;
    }

    /// <summary>Raise from host to open a file/diff/editor/dialog.</summary>
    public event Func<string, int?, string?, Task>? HostAction;

    /// <summary>
    /// Whether the panel draws the skeleton instead of the surface. True while a
    /// refresh is in flight and -- up to <see cref="PanelLayoutTiming.WhyCeilingMs"/>
    /// -- while the current entry's why is still loading: navigating is one wait for
    /// the reviewer even though it arrives in two parts (the verb plus status
    /// --porcelain, then the why), and drawing the model in between would show the
    /// entry with a second loading state inside it. Past the ceiling the entry is
    /// drawn anyway with the why loading in place, exactly as in VS Code and
    /// IntelliJ: a slow why must not hold the entry back.
    /// </summary>
    private bool Loading =>
        _refreshing || (EffectiveWhy?.State == WhyState.Loading && !_whyCeilingReached);

    /// <summary>
    /// The layout the panel is currently showing, for hosts that draw part of it
    /// themselves. In Visual Studio the five title actions are a tool-window toolbar
    /// rather than buttons inside the pane, and its QueryStatus reads them from here:
    /// which of them exists and whether it is enabled stays a projection of the CLI
    /// situation computed in the domain, not a second set of conditions in the host.
    /// </summary>
    public PanelLayout? LastLayout { get; private set; }

    /// <summary>
    /// Raised when the set of title actions -- or any of their enabled states --
    /// changes. A host command bar has to be told to re-query; without this the
    /// toolbar keeps last render's buttons until something else makes the shell
    /// refresh its command UI.
    /// </summary>
    public event Action? TitleActionsChanged;

    /// <param name="workspacePending">
    /// Whether the host still cannot say where the workspace is. Empty roots are two
    /// different situations and only the host can tell them apart: a folder that is
    /// not a git repository (a real answer, and the panel says so), or a shell that
    /// has not finished opening the solution yet (no answer at all). While this says
    /// the second, the panel waits instead of refreshing -- the state manager reads
    /// empty roots as "need a single git repository root", which is what every
    /// Visual Studio start showed for its first seconds with the window docked.
    /// </param>
    public GitReviewPanelController(
        Func<IReadOnlyList<string>> roots,
        Func<string?>? gitReviewPath = null,
        PanelChrome? chrome = null,
        Action<string>? log = null,
        Func<bool>? workspacePending = null)
    {
        _roots = roots;
        _workspacePending = workspacePending ?? (static () => false);
        _cwd = () => SoleTarget.PickSoleTarget(roots());
        _cli = new CliInvoker(gitReviewPath, log: log);
        _state = new ReviewStateManager(_cli, roots, gitReviewPath);
        _mutations = new MutationRunner(_cli, _state, _cwd);
        _view = new PanelView(chrome);
        // The dialogs the action matrix opens are plain WPF windows with no host theme of
        // their own: they take the panel's, so a picker opened from a dark IDE is not a
        // white flash. Set here because the host resolves the chrome once, per build.
        if (chrome is not null) GitReviewDialogs.Chrome = chrome;
        _view.ActionRequested += OnAction;
        _dispatcher = Dispatcher.CurrentDispatcher;

        _state.StateChanged += OnStateChanged;
        _busySub = _mutations.Lock.OnDidChangeBusy(_ => Render());
        // A discarded mutation is reported here and nowhere else, so it is reported
        // whoever asked for it: the panel's own buttons go through a path that could
        // say it, but Tools -> git review and the toolbar do not, and a navigation
        // dropped because a finish was still running looked like a click that did
        // nothing. Same ownership as the JetBrains service and the extension.
        _discardSub = _mutations.Lock.OnDidDiscard(reason =>
        {
            if (_disposed) return;
            if (!_dispatcher.CheckAccess())
            {
                _dispatcher.BeginInvoke((Action)(() => GitReviewDialogs.Info(reason)));
                return;
            }
            GitReviewDialogs.Info(reason);
        });

        _draftWatcher = new DraftWatcher(() =>
        {
            if (_disposed) return;
            _dispatcher.BeginInvoke((Action)(() =>
            {
                if (!_disposed) _ = RefreshAsync();
            }));
        });

        _probeTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(CliProbe.CliProbeIntervalMs) };
        _probeTimer.Tick += async (_, _) =>
        {
            try
            {
                if (CliProbe.ShouldProbeCli(_state.Current.Situation, _panelVisible))
                    await RefreshAsync().ConfigureAwait(true);
            }
            catch
            {
                // A background probe that throws must not take the host down with it
                // (in Visual Studio this runs in devenv): the next tick retries.
            }
        };
        _probeTimer.Start();

        _skeletonTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(PanelLayoutTiming.SkeletonDelayMs),
        };
        _skeletonTimer.Tick += (_, _) =>
        {
            _skeletonTimer.Stop();
            if (Loading) Render();
        };

        _whyCeilingTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(PanelLayoutTiming.WhyCeilingMs),
        };
        _whyCeilingTimer.Tick += (_, _) =>
        {
            _whyCeilingTimer.Stop();
            if (EffectiveWhy?.State != WhyState.Loading) return;
            _whyCeilingReached = true;
            Render();
        };
    }

    public void SetVisible(bool visible)
    {
        _panelVisible = visible;
        if (visible) _ = RefreshAsync();
    }

    /// <summary>
    /// A document the shell just saved. Refreshes only when it is one of the authoring
    /// guides the CLI reported: those have no watcher (the reviewer's lives in the root
    /// of the gitdir, which changes on every git operation), so the save is the signal.
    /// Anything else is one of the thousands of saves that are none of the panel's
    /// business.
    /// </summary>
    public void NotifyDocumentSaved(string path)
    {
        if (_disposed || !DraftWatch.IsReportedGuide(_state.Current, path)) return;
        _ = RefreshAsync();
    }

    public async Task RefreshAsync()
    {
        if (_workspacePending())
        {
            // Nothing to read yet, and nothing to report either: reading now would
            // publish the host's silence as a state. Draws the waiting surface -- the
            // host calls again as soon as the workspace answers.
            Render();
            return;
        }
        var seq = ++_refreshSeq;
        _refreshing = true;
        _whyCeilingReached = false;
        _whyCeilingTimer.Stop();
        _skeletonTimer.Stop();
        _skeletonTimer.Start();
        try
        {
            await _state.RefreshAsync().ConfigureAwait(true);
            if (seq != _refreshSeq) return;
            _draftWatcher.Sync(DraftWatch.WatchDirs(_state.Current));
            if (SituationIds.IsReviewReadable(_state.Current.Situation)
                && _state.Current.State?.Mode == ReviewMode.Walk)
            {
                StartWhy(seq);
            }
            else
            {
                _why = null;
                _whyKey = null;
            }
        }
        finally
        {
            if (seq == _refreshSeq)
            {
                _refreshing = false;
                if (!Loading) _skeletonTimer.Stop();
                Render();
            }
        }
    }

    /// <summary>
    /// Starts the current entry's why and returns: the refresh itself is over once
    /// status --porcelain has answered. Awaiting the read here is what kept the whole
    /// panel on the skeleton for as long as the CLI took to produce one entry's prose.
    /// </summary>
    private void StartWhy(int seq)
    {
        var st = _state.Current;
        var entry = PanelModelBuilder.CurrentEntry(st.EntriesList, st.State?.Position);
        var cwd = _cwd();
        _whyKey = WhyKeyOf(st);
        if (entry is null)
        {
            _why = new PanelWhy(WhyState.Absent);
            return;
        }
        if (cwd is null)
        {
            // Same answer the read would give: nothing to invoke it in. Left on
            // "loading" the entry would sit under a skeleton that never resolves.
            _why = new PanelWhy(WhyState.Failed);
            return;
        }
        _why = new PanelWhy(WhyState.Loading);
        _whyCeilingTimer.Stop();
        _whyCeilingTimer.Start();
        var raw = entry.Id is PathRef pr ? pr.Raw : entry.Id.ToString() ?? "";
        _ = LoadWhyAsync(seq, raw, cwd);
    }

    /// <summary>
    /// Reads one entry's why. Deliberately without a cancellation token of its own:
    /// the invoker already caps a read at <see cref="TimeoutClass.ReadTimeoutMs"/>,
    /// and cancelling at the 800 ms ceiling instead turned every call into a failure
    /// -- on Windows a status --why costs a couple of seconds, so the panel answered
    /// "Could not read the why for this entry" for every entry of every walk. The
    /// ceiling is a drawing deadline (<see cref="Loading"/>), not a deadline on the
    /// call: it shows the entry with the why still loading inside it, and this fills
    /// it in whenever the CLI gets there.
    /// </summary>
    private async Task LoadWhyAsync(int seq, string raw, string cwd)
    {
        PanelWhy why;
        try
        {
            var result = await _cli.InvokeAsync("status", new[] { "--why", raw }, cwd)
                .ConfigureAwait(true);
            if (result.ExitCode == 0 && !result.TimedOut)
            {
                var text = result.Stdout.TrimEnd();
                why = string.IsNullOrEmpty(text)
                    ? new PanelWhy(WhyState.Absent)
                    : new PanelWhy(WhyState.Present, text);
            }
            else
            {
                why = new PanelWhy(WhyState.Failed);
            }
        }
        catch
        {
            why = new PanelWhy(WhyState.Failed);
        }

        PublishWhy(seq, why);
    }

    /// <summary>
    /// Hands the loaded why to the panel. On the dispatcher thread, like everything
    /// that touches a DispatcherTimer: the read above is fire-and-forget, so its
    /// continuation only lands back here when the refresh that started it was itself
    /// on the UI thread -- and a timer stopped from anywhere else throws.
    /// </summary>
    private void PublishWhy(int seq, PanelWhy why)
    {
        if (_disposed) return;
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.BeginInvoke((Action)(() => PublishWhy(seq, why)));
            return;
        }
        // A refresh that started after this read owns the panel now: its entry is the
        // one on screen, and publishing this text would caption it with the why of the
        // entry the reviewer already left.
        if (seq != _refreshSeq) return;
        _why = why;
        _whyCeilingTimer.Stop();
        _skeletonTimer.Stop();
        Render();
    }

    private void OnStateChanged(ReviewState _) => Render();

    /// <summary>
    /// Draws the panel. Safe to call from any thread: everything it touches is WPF,
    /// so an off-thread call is marshalled to the dispatcher instead of throwing.
    /// Two of the callers are genuinely off-thread. <see cref="ReviewStateManager"/>
    /// raises StateChanged from wherever the refresh finished, and MutationLock
    /// notifies its busy listeners from wherever the mutation finished -- the CLI
    /// await inside RunAsync is ConfigureAwait(false), so releasing the lock lands on
    /// a thread-pool thread. Rendering from there throws "The calling thread cannot
    /// access this object because a different thread owns it", and because the catch
    /// below touches the view as well, the second throw escapes to OnAction and
    /// becomes a MessageBox: every CLI action would do its job and still end in an
    /// error dialog.
    /// </summary>
    private void Render()
    {
        if (_disposed) return;
        if (!_dispatcher.CheckAccess())
        {
            _dispatcher.BeginInvoke((Action)Render);
            return;
        }
        try
        {
            if (!_state.HasResolved || _workspacePending())
            {
                // Nothing has been read yet -- or the workspace the last read belonged
                // to is being replaced and the host cannot say where the new one is.
                // No layout to publish, and therefore no title actions either: a
                // toolbar built from a placeholder would offer buttons for a situation
                // nobody has established, and one left on the previous layout would
                // offer them for a repository the panel is no longer pointed at.
                LastLayout = null;
                NotifyTitleActions(Array.Empty<DomainControl>());
                _view.RenderWaiting();
                return;
            }
            var model = PanelModelBuilder.BuildPanelModel(
                _state.Current,
                new PanelInputs(_mutations.IsBusy, Why: EffectiveWhy, LastOpened: _lastOpened));
            var layout = PanelLayoutBuilder.PanelLayout(model, loading: Loading && !_mutations.IsBusy);
            // Published before the draw: a host toolbar reading it must not depend on
            // this renderer having handled every block variant in the layout.
            LastLayout = layout;
            NotifyTitleActions(layout.TitleActions);
            _view.Render(layout);
        }
        catch (Exception ex)
        {
            // None of the callers (skeleton timer tick, RefreshAsync's finally,
            // OnStateChanged, the busy listener) guard against this, and PanelView
            // clears itself before drawing: left unguarded, a throw here is a
            // permanently blank tool window with nothing in the debug output.
            _view.RenderFatal(ex);
        }
    }

    private void NotifyTitleActions(IReadOnlyList<DomainControl> actions)
    {
        var signature = string.Join(
            "|",
            actions.Select(c => c.Id.Wire() + (c.Enabled ? "+" : "-")));
        if (signature == _titleSignature) return;
        _titleSignature = signature;
        TitleActionsChanged?.Invoke();
    }

    /// <summary>
    /// Runs a control as if it had been clicked in the panel, so a host-drawn
    /// surface takes exactly the same path (host action matrix, confirmations,
    /// staleness re-check) as the button it replaces.
    /// </summary>
    public void InvokeAction(string wire, int? index = null, string? supportLinkId = null) =>
        OnAction(wire, index, supportLinkId);

    private async void OnAction(string wire, int? index, string? supportLinkId)
    {
        try
        {
            if (HostAction is not null)
            {
                await HostAction(wire, index, supportLinkId).ConfigureAwait(true);
                return;
            }
            await DefaultHandleAsync(wire, index, supportLinkId).ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, UserCopy.ProductTitle, MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async Task DefaultHandleAsync(string wire, int? index, string? supportLinkId)
    {
        switch (wire)
        {
            case "refresh":
                await RefreshAsync().ConfigureAwait(true);
                break;
            case "next":
            case "prev":
                await _mutations.RunActionAsync(wire).ConfigureAwait(true);
                await RefreshAsync().ConfigureAwait(true);
                break;
            case "copyCliInstall":
                var cmd = _state.Current.Situation == Situation.CliOutdated
                    ? InstallHint.NpmUpdateCmd
                    : InstallHint.NpmInstallCmd;
                Clipboard.SetText(cmd);
                break;
            case "installCli":
                Process.Start(new ProcessStartInfo(UserCopy.InstallDocsUrl) { UseShellExecute = true });
                break;
            case "openSupport":
                var url = SupportLinks.UrlFor(supportLinkId);
                if (url is not null)
                    Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                break;
            case "outOfRangeHelp":
                MessageBox.Show(UserCopy.OutOfRangeFallback, UserCopy.ProductTitle);
                break;
            case "showCliLog":
                var log = string.Join("\n", CliInvoker.CliLogSink.Snapshot());
                MessageBox.Show(string.IsNullOrEmpty(log) ? "(empty)" : log, "git review CLI log");
                break;
            default:
                // Mutations that need confirmations / wizards are handled by host.
                if (PanelLayoutBuilder.RequiresConfirmation(ControlIdExt.FromWire(wire) ?? ControlId.Refresh))
                {
                    // Host should intercept; fallback no-op with refresh
                    await RefreshAsync().ConfigureAwait(true);
                }
                break;
        }
    }

    public void RememberOpened(string display) => _lastOpened = display;

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _probeTimer.Stop();
        _skeletonTimer.Stop();
        _whyCeilingTimer.Stop();
        _busySub.Dispose();
        _discardSub.Dispose();
        _draftWatcher.Dispose();
        _state.StateChanged -= OnStateChanged;
        _view.ActionRequested -= OnAction;
    }
}
