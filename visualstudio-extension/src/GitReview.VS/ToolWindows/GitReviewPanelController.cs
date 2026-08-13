using System.Diagnostics;
using System.Windows;
using System.Windows.Threading;
using GitReview.Domain;
using GitReview.Host;

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
    private readonly Func<string?> _cwd;
    private readonly Dispatcher _dispatcher;
    private readonly DispatcherTimer _probeTimer;
    private readonly DispatcherTimer _skeletonTimer;
    private PanelWhy? _why;
    private string? _lastOpened;
    private bool _loading;
    private bool _panelVisible = true;
    private int _refreshSeq;
    private bool _disposed;

    public PanelView View => _view;
    public ReviewStateManager State => _state;
    public MutationRunner Mutations => _mutations;

    /// <summary>Raise from host to open a file/diff/editor/dialog.</summary>
    public event Func<string, int?, string?, Task>? HostAction;

    public GitReviewPanelController(
        Func<IReadOnlyList<string>> roots,
        Func<string?>? gitReviewPath = null,
        PanelChrome? chrome = null,
        Action<string>? log = null)
    {
        _roots = roots;
        _cwd = () => SoleTarget.PickSoleTarget(roots());
        _cli = new CliInvoker(gitReviewPath, log: log);
        _state = new ReviewStateManager(_cli, roots, gitReviewPath);
        _mutations = new MutationRunner(_cli, _state, _cwd);
        _view = new PanelView(chrome);
        _view.ActionRequested += OnAction;
        _dispatcher = Dispatcher.CurrentDispatcher;

        _state.StateChanged += OnStateChanged;
        _mutations.Lock.OnDidChangeBusy(_ => Render());

        _probeTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(CliProbe.CliProbeIntervalMs) };
        _probeTimer.Tick += async (_, _) =>
        {
            if (CliProbe.ShouldProbeCli(_state.Current.Situation, _panelVisible))
                await RefreshAsync().ConfigureAwait(true);
        };
        _probeTimer.Start();

        _skeletonTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(PanelLayoutTiming.SkeletonDelayMs),
        };
        _skeletonTimer.Tick += (_, _) =>
        {
            _skeletonTimer.Stop();
            if (_loading) Render();
        };
    }

    public void SetVisible(bool visible)
    {
        _panelVisible = visible;
        if (visible) _ = RefreshAsync();
    }

    public async Task RefreshAsync()
    {
        var seq = ++_refreshSeq;
        _loading = true;
        _skeletonTimer.Stop();
        _skeletonTimer.Start();
        try
        {
            await _state.RefreshAsync().ConfigureAwait(true);
            if (seq != _refreshSeq) return;
            if (SituationIds.IsReviewReadable(_state.Current.Situation)
                && _state.Current.State?.Mode == ReviewMode.Walk)
            {
                await LoadWhyAsync().ConfigureAwait(true);
            }
            else
            {
                _why = null;
            }
        }
        finally
        {
            if (seq == _refreshSeq)
            {
                _loading = false;
                _skeletonTimer.Stop();
                Render();
            }
        }
    }

    private async Task LoadWhyAsync()
    {
        var st = _state.Current;
        var entry = PanelModelBuilder.CurrentEntry(st.EntriesList, st.State?.Position);
        if (entry is null)
        {
            _why = new PanelWhy(WhyState.Absent);
            return;
        }
        _why = new PanelWhy(WhyState.Loading);
        Render();

        var cwd = _cwd();
        if (cwd is null) return;
        var raw = entry.Id is PathRef pr ? pr.Raw : entry.Id.ToString() ?? "";
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(PanelLayoutTiming.WhyCeilingMs));
        try
        {
            var result = await _cli.InvokeAsync("status", new[] { "--why", raw }, cwd, cancellationToken: cts.Token)
                .ConfigureAwait(true);
            if (result.ExitCode == 0)
            {
                var text = result.Stdout.TrimEnd();
                _why = string.IsNullOrEmpty(text)
                    ? new PanelWhy(WhyState.Absent)
                    : new PanelWhy(WhyState.Present, text);
            }
            else
            {
                _why = new PanelWhy(WhyState.Failed);
            }
        }
        catch
        {
            _why = new PanelWhy(WhyState.Failed);
        }
    }

    private void OnStateChanged(ReviewState _) =>
        _dispatcher.BeginInvoke(Render);

    private void Render()
    {
        var model = PanelModelBuilder.BuildPanelModel(
            _state.Current,
            new PanelInputs(_mutations.IsBusy, Why: _why, LastOpened: _lastOpened));
        var layout = PanelLayoutBuilder.PanelLayout(model, loading: _loading && !_mutations.IsBusy);
        _view.Render(layout);
    }

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
        _view.ActionRequested -= OnAction;
    }
}
