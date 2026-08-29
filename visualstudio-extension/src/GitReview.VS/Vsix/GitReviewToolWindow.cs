using System.ComponentModel.Design;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using GitReview.Domain;
using GitReview.VS.ToolWindows;
using Microsoft.VisualStudio.PlatformUI;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using DomainControl = GitReview.Domain.Control;
using SolutionEvents = Microsoft.VisualStudio.Shell.Events.SolutionEvents;

namespace GitReview.VS.Vsix;

/// <summary>
/// The tool window itself. It hosts the same <see cref="PanelView"/> the standalone
/// preview renders, driven by the same controller — this class only supplies what
/// belongs to the IDE: where the repository is, which CLI path the options page has,
/// the host half of the action matrix, and the theme.
/// </summary>
[Guid(GitReviewPackage.ToolWindowGuidString)]
public sealed class GitReviewToolWindow : ToolWindowPane
{
    private GitReviewPanelController? _controller;

    /// <summary>
    /// Advised on the running document table, and only for the authoring guides: they
    /// are the one thing the panel draws that no watcher of ours is looking at.
    /// </summary>
    private DocumentSaveListener? _saveListener;
    private IReadOnlyList<string> _roots = Array.Empty<string>();

    /// <summary>
    /// Whether the shell named a workspace directory the last time it was asked --
    /// which is what separates "this folder is not a git repository" from "the shell
    /// has not said where the folder is yet". See <see cref="VsWorkspace.WorkspaceProbe"/>.
    /// </summary>
    private bool _workspaceLocated;

    /// <summary>True while the retry below is still waiting for that answer.</summary>
    private bool _workspacePending;

    /// <summary>
    /// The one object the shell ever sees as this pane's content. <c>WindowPane.Content</c>
    /// is an ordinary auto-property that the shell reads exactly once, in
    /// <c>IVsUIElementPane.CreateUIElementPane</c>, which runs while the frame is being
    /// created — that is, before <see cref="OnToolWindowCreated"/>. Assigning
    /// <c>Content</c> after that writes a field nobody reads again: the shell keeps
    /// rendering whatever it got, so the pane stays exactly as the constructor left it.
    /// Hence a container fixed at construction time whose child gets swapped instead.
    /// </summary>
    private readonly Grid _host = new();

    /// <summary>Kept alive because it is what is subscribed to the panel's HostAction.</summary>
    private ActionDispatcher? Actions { get; set; }
    private bool _listening;

    /// <summary>
    /// Waits for the workspace to be able to say where it is. Visual Studio restores
    /// an open tool window while the solution or folder is still loading, so the roots
    /// read at construction time are routinely empty — and nothing else would come back
    /// for them: OnAfterOpenSolution has already fired by the time this window
    /// subscribes, and the panel's own probe timer only runs for cli-missing /
    /// cli-outdated, never for the "need a single git repository root" this produces.
    /// Left out, opening Visual Studio with the panel docked gives a panel that is
    /// wrong until someone presses Refresh by hand.
    ///
    /// While it runs the panel is held on its waiting surface rather than refreshed:
    /// the wait is the whole point, and refreshing in the middle of it publishes the
    /// shell's silence as "Something went wrong reading the review state." for as long
    /// as the solution takes to load. It only ever runs when the shell has named no
    /// directory at all, so a folder that really is not a repository is still answered
    /// at once.
    /// </summary>
    private DispatcherTimer? _rootsTimer;

    public GitReviewToolWindow() : base(null)
    {
        Caption = UserCopy.ProductTitle;
        // Refresh / Finish / Save / Cancel / Preview edits, as the window's own
        // toolbar — the Visual Studio equivalent of the VS Code view title and of
        // the IntelliJ tool-window title actions. The shell reads this while it is
        // creating the frame, so it belongs here next to Content; the buttons are
        // declared in GitReviewPackage.vsct and answered for by GitReviewPackage.
        ToolBar = new CommandID(new Guid(GitReviewPackage.CommandSetGuidString), GitReviewPackage.ToolbarId);
        ToolBarLocation = (int)VSTWT_LOCATION.VSTWT_TOP;
        // Set here and never again — see _host. The panel itself is filled in from
        // OnToolWindowCreated, once there is a package to read the settings from.
        Content = _host;
    }

    /// <summary>
    /// The title actions of the layout currently on screen, for the toolbar's
    /// QueryStatus. Null until the panel has rendered once.
    /// </summary>
    internal IReadOnlyList<DomainControl>? TitleActions => _controller?.LastLayout?.TitleActions;

    /// <summary>Runs a toolbar button through the panel's own action path.</summary>
    internal void InvokeAction(string wire) => _controller?.InvokeAction(wire);

    /// <summary>
    /// Same path, for a menu entry: the state is refreshed first. A toolbar button is
    /// clicked on a panel the reviewer is looking at, but Tools → git review can be used
    /// with the window freshly created — or minutes old — and the pickers behind several
    /// of those actions are only as good as the state they read.
    /// </summary>
    internal async Task InvokeActionAsync(string wire)
    {
        var controller = _controller;
        if (controller is null) return;
        await controller.RefreshAsync();
        controller.InvokeAction(wire);
    }

    /// <summary>The only way this class puts anything on screen.</summary>
    private void SetPaneContent(UIElement element)
    {
        _host.Children.Clear();
        _host.Children.Add(element);
    }

    public override void OnToolWindowCreated()
    {
        base.OnToolWindowCreated();
        ThreadHelper.ThrowIfNotOnUIThread();

        if (!_listening)
        {
            VSColorTheme.ThemeChanged += OnThemeChanged;
            SolutionEvents.OnAfterOpenSolution += OnSolutionOpened;
            SolutionEvents.OnAfterCloseSolution += OnSolutionClosed;
            _listening = true;
        }

        Build();
    }

    /// <summary>
    /// Roots are resolved on the UI thread and cached: the panel refreshes from a
    /// timer and from background continuations, and asking Visual Studio for the
    /// solution off the UI thread is not allowed.
    /// </summary>
    private void RefreshRoots()
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        var probe = VsWorkspace.Probe(ServiceProvider());
        _roots = probe.Roots;
        _workspaceLocated = probe.Located;
    }

    /// <summary>
    /// The shell has not told us where the workspace is -- as opposed to having told us
    /// about a folder that git does not call a repository, which is an answer, and one
    /// the panel is meant to show right away.
    /// </summary>
    private bool WorkspaceUnknown() => _roots.Count == 0 && !_workspaceLocated;

    private void Build()
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        try
        {
            BuildCore();
        }
        catch (Exception ex)
        {
            // Nothing upstream of this (OnToolWindowCreated, the shell's tool-window
            // creation path) guards against a throw here, and it happens before the
            // panel is ever put into _host — so left unguarded, this is a permanently
            // blank pane with zero trace in any log. Fixed, non-themed colors on
            // purpose: if VsTheme.Chrome() itself is what is throwing, or the theme
            // brushes are what is broken, this still has to be visible.
            SetPaneContent(new System.Windows.Controls.TextBox
            {
                Text = "git review failed to build the panel:\n" + ex,
                IsReadOnly = true,
                TextWrapping = System.Windows.TextWrapping.Wrap,
                Background = System.Windows.Media.Brushes.Black,
                Foreground = System.Windows.Media.Brushes.Yellow,
                FontFamily = new System.Windows.Media.FontFamily("Consolas"),
                FontSize = 12,
            });
        }
    }

    private void BuildCore()
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        DisposeController();

        RefreshRoots();
        var package = (GitReviewPackage)Package;
        var chrome = VsTheme.Chrome();
        _controller = new GitReviewPanelController(
            () => _roots,
            () => package.GitReviewPath,
            chrome,
            log: static line => System.Diagnostics.Debug.WriteLine("[git review] " + line),
            workspacePending: () => _workspacePending);
        // The shell draws the five title actions; drawing them inside the pane as
        // well would be the same five buttons twice.
        _controller.View.ShowTitleActions = false;
        _controller.TitleActionsChanged += OnTitleActionsChanged;
        Actions = new VsHostActions(ServiceProvider(), _controller, () => _roots, RevealSelf).Attach();

        // Cuarta senal de refresco, solo para las guias de autoria: no tienen
        // watcher, asi que el guardado es lo que le dice al panel que la escribiste.
        _saveListener = DocumentSaveListener.Attach(
            ServiceProvider(),
            path => _controller?.NotifyDocumentSaved(path));

        SetPaneContent(_controller.View);
        // Started before the refresh, not after: it is what tells the refresh that
        // there is nothing to read yet.
        if (WorkspaceUnknown()) StartRootsRetry();
        _ = _controller.RefreshAsync();
    }

    private void StartRootsRetry()
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        StopRootsRetry();
        _workspacePending = true;
        // Bounded on purpose: a workspace that never arrives still has to end up saying
        // so rather than waiting forever. This is only here to outlast the load.
        var attempts = 0;
        _rootsTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _rootsTimer.Tick += (_, _) =>
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            RefreshRoots();
            if (WorkspaceUnknown() && ++attempts < 30) return;
            StopRootsRetry();
            // Unconditional: the refresh at build time was held back by the flag this
            // just cleared, so whatever the answer turns out to be -- a review, or the
            // missing root after all -- this is the call that produces it.
            if (_controller is not null) _ = _controller.RefreshAsync();
        };
        _rootsTimer.Start();
    }

    private void StopRootsRetry()
    {
        _workspacePending = false;
        _rootsTimer?.Stop();
        _rootsTimer = null;
    }

    /// <summary>
    /// El vehiculo del reveal: trae esta ventana al frente SIN llevarle el foco,
    /// asi que el revisor sigue escribiendo donde estaba y lo que cambia es que
    /// el panel deja de estar tapado.
    ///
    /// <c>ShowNoActivate</c> y no <c>Show</c>: el segundo activa la ventana, que
    /// es exactamente lo que no se quiere. Un <c>Frame</c> que no es un
    /// IVsWindowFrame no puede pasar en el shell real, pero se guarda igual: un
    /// reveal es un acuse, y ningun acuse tiene por que tirar la mutacion abajo.
    ///
    /// La decision de SI corresponde revelar no esta aca: esta en
    /// <see cref="PanelReveal"/>, contra el `reveals:` del canonico.
    /// </summary>
    private void RevealSelf()
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (Frame is IVsWindowFrame frame)
        {
            frame.ShowNoActivate();
        }
    }

    private IServiceProvider ServiceProvider() => (IServiceProvider)Package;

    /// <summary>
    /// Tells the shell to re-run QueryStatus on the toolbar. Command bars are only
    /// re-queried when something asks them to, so without this a review that has just
    /// started keeps showing the buttons of the situation before it.
    /// </summary>
    private void OnTitleActionsChanged()
    {
        // Posted rather than awaited: this is raised from inside the panel's render,
        // whose try/catch reads any throw as "the renderer is broken" and replaces
        // the whole pane with the fatal text. The render marshals itself onto this
        // dispatcher first, so the off-thread branch is belt and braces.
        if (!_host.Dispatcher.CheckAccess())
        {
            _ = _host.Dispatcher.BeginInvoke((Action)OnTitleActionsChanged);
            return;
        }
        ThreadHelper.ThrowIfNotOnUIThread();
        if (ServiceProvider().GetService(typeof(SVsUIShell)) is IVsUIShell shell)
            shell.UpdateCommandUI(0);
    }

    private void DisposeController()
    {
        if (_controller is null) return;
        _controller.TitleActionsChanged -= OnTitleActionsChanged;
        _saveListener?.Dispose();
        _saveListener = null;
        _controller.Dispose();
        _controller = null;
    }

    private void OnThemeChanged(ThemeChangedEventArgs e) =>
        ThreadHelper.JoinableTaskFactory.Run(async () =>
        {
            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            // The chrome is baked into the view when it is built, so a theme switch
            // rebuilds the panel rather than repainting it.
            Build();
        });

    /// <summary>
    /// A solution or folder was opened. Same shape as the tail of <see cref="BuildCore"/>
    /// and for the same reason: this fires before the shell will say where the folder is,
    /// so refreshing unconditionally here is the startup flash again, one solution switch
    /// at a time.
    /// </summary>
    private void OnSolutionOpened(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        WorkspaceChanged(canWait: true);
    }

    /// <summary>
    /// A solution or folder was closed. Nothing is arriving, so there is nothing to wait
    /// for: no root is the right answer and the panel should say so now.
    /// </summary>
    private void OnSolutionClosed(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        WorkspaceChanged(canWait: false);
    }

    private void WorkspaceChanged(bool canWait)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        StopRootsRetry();
        RefreshRoots();
        if (canWait && WorkspaceUnknown()) StartRootsRetry();
        if (_controller is not null) _ = _controller.RefreshAsync();
    }

    protected override void OnClose()
    {
        if (_listening)
        {
            VSColorTheme.ThemeChanged -= OnThemeChanged;
            SolutionEvents.OnAfterOpenSolution -= OnSolutionOpened;
            SolutionEvents.OnAfterCloseSolution -= OnSolutionClosed;
            _listening = false;
        }
        StopRootsRetry();
        DisposeController();
        Actions = null;
        base.OnClose();
    }
}
