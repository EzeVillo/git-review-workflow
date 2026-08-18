// The Visual Studio package: what makes this assembly an extension the IDE loads,
// rather than a library. The attributes below are read at build time and written to
// GitReview.VS.pkgdef, which is what registers the package, its menu resource and
// the tool window with whichever hive the .vsix is installed into.
//
// Compiled only for net472 (see GitReview.VS.csproj): devenv loads in-proc
// extensions on .NET Framework.

using System.ComponentModel.Design;
using System.Runtime.InteropServices;
using System.Threading;
using GitReview.Domain;
using GitReview.VS.Settings;
using GitReview.VS.ToolWindows;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Task = System.Threading.Tasks.Task;

namespace GitReview.VS.Vsix;

[PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
[ProvideMenuResource("Menus.ctmenu", 1)]
[ProvideToolWindow(
    typeof(GitReviewToolWindow),
    Style = VsDockStyle.Tabbed,
    Window = ToolWindowGuids80.SolutionExplorer)]
[ProvideOptionPage(typeof(GitReviewOptionsPage), UserCopy.ProductTitle, OptionsPageName, 0, 0, true)]
[Guid(PackageGuidString)]
public sealed class GitReviewPackage : AsyncPackage
{
    public const string PackageGuidString = "a3f8c2e1-7b4d-4e9a-9c1f-2d5e6a8b0c3d";
    public const string ToolWindowGuidString = "b4e9d3f2-8c5e-4f0b-ad2a-3e6f7b9c1d4e";
    public const string CommandSetGuidString = "c7d4e8a5-1f36-4b92-8a70-6d5e4c3b2a19";
    public const int ShowToolWindowCommandId = 0x0100;
    public const int ToolbarId = 0x1000;
    public const string OptionsPageName = "General";

    private static readonly Guid CommandSet = new(CommandSetGuidString);

    /// <summary>
    /// The tool window's toolbar: the five title actions, in the order the contract
    /// (and the other two clients) put them. Ids match the IDSymbols in the .vsct;
    /// the ControlId is what QueryStatus looks for in <see cref="PanelLayout.TitleActions"/>
    /// and what a click sends down the panel's own action path.
    /// </summary>
    private static readonly (int Id, ControlId Control)[] TitleBarCommands =
    {
        (0x0101, ControlId.Refresh),
        (0x0102, ControlId.FinishReview),
        (0x0103, ControlId.SaveReview),
        (0x0104, ControlId.AbortReview),
        (0x0105, ControlId.PreviewEdits),
    };

    /// <summary>
    /// Tools → git review: the 27 product actions of
    /// <c>contracts/client-product-surface.yaml</c>, in the order the .vsct declares
    /// them. This is the Visual Studio equivalent of the VS Code command palette and of
    /// the JetBrains Tools menu, and it is the *only* surface for the four actions the
    /// contract marks panel_excluded — an action reachable from neither is an action this
    /// client does not really have.
    ///
    /// Ids match the IDSymbols in the .vsct; the wire string is what the panel's own
    /// action path takes, so a menu entry runs the same code as the button of the same
    /// name and nothing about an action is implemented twice.
    /// </summary>
    private static readonly (int Id, string Wire)[] MenuCommands =
    {
        (0x0201, "refresh"),
        (0x0202, "startReview"),
        (0x0203, "continueReview"),
        (0x0204, "finishReview"),
        (0x0205, "saveReview"),
        (0x0206, "abortReview"),
        (0x0207, "undoFinish"),
        (0x0208, "resumeFinish"),
        (0x0209, "next"),
        (0x020A, "prev"),
        (0x020B, "goToEntry"),
        (0x020C, "openEntry"),
        (0x020D, "openChange"),
        (0x020E, "openAllChanges"),
        (0x020F, "showWhy"),
        (0x0210, "setBase"),
        (0x0211, "setRemote"),
        (0x0212, "cleanReview"),
        (0x0213, "forgetReview"),
        (0x0214, "discardInventory"),
        (0x0215, "previewEdits"),
        (0x0216, "previewEditsStat"),
        (0x0217, "compareReview"),
        (0x0218, "walkthroughInit"),
        (0x0219, "walkthroughBuild"),
        (0x021A, "installCli"),
        (0x021B, "showCliLog"),
    };

    /// <summary>
    /// The menu entries whose enablement follows the situation, and the control each one
    /// reads. Exactly the four the JetBrains plugin gates in <c>AnAction.update</c>, from
    /// the same projection the tool-window toolbar uses — reimplementing the conditions
    /// here would be a second copy of the matrix. The rest stay enabled and answer for
    /// themselves: several are meaningful in every situation, and the ones that are not
    /// say so in the words the CLI used.
    /// </summary>
    private static readonly Dictionary<string, ControlId> GatedMenuCommands = new()
    {
        ["finishReview"] = ControlId.FinishReview,
        ["saveReview"] = ControlId.SaveReview,
        ["abortReview"] = ControlId.AbortReview,
        ["previewEdits"] = ControlId.PreviewEdits,
    };

    /// <summary>
    /// Path to the git-review dispatcher as the options page has it. Read on every
    /// invocation rather than captured, so changing the setting takes effect without
    /// reopening the tool window.
    /// </summary>
    public string? GitReviewPath =>
        string.IsNullOrWhiteSpace(GitReviewOptions.Current.Path) ? null : GitReviewOptions.Current.Path;

    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);

        // Materialize the options page so GitReviewOptions.Current holds the stored
        // values before the panel's first refresh asks for the CLI path.
        _ = (GitReviewOptionsPage)GetDialogPage(typeof(GitReviewOptionsPage));

        if (await GetServiceAsync(typeof(IMenuCommandService)) is OleMenuCommandService commands)
        {
            commands.AddCommand(new MenuCommand(
                (_, _) => JoinableTaskFactory.RunAsync(ShowToolWindowAsync).FileAndForget("gitreview/showtoolwindow"),
                new CommandID(CommandSet, ShowToolWindowCommandId)));

            foreach (var (id, control) in TitleBarCommands)
            {
                var command = new OleMenuCommand(
                    (sender, _) => InvokeTitleAction(sender),
                    new CommandID(CommandSet, id));
                command.BeforeQueryStatus += UpdateTitleAction;
                commands.AddCommand(command);
            }

            foreach (var (id, wire) in MenuCommands)
            {
                var command = new OleMenuCommand(
                    (sender, _) => InvokeMenuAction(sender),
                    new CommandID(CommandSet, id));
                command.BeforeQueryStatus += UpdateMenuAction;
                commands.AddCommand(command);
            }
        }
    }

    /// <summary>
    /// The tool window, if one has been created. Never creates it: these commands
    /// only exist on that window's toolbar, so no window means nothing to answer for.
    /// </summary>
    private GitReviewToolWindow? Panel() =>
        FindToolWindow(typeof(GitReviewToolWindow), 0, create: false) as GitReviewToolWindow;

    private static ControlId? ControlFor(int commandId)
    {
        foreach (var (id, control) in TitleBarCommands)
            if (id == commandId)
                return control;
        return null;
    }

    /// <summary>
    /// Visibility and enablement of the toolbar, read straight off the layout the
    /// panel is showing. The buttons are DefaultInvisible in the .vsct, so a control
    /// the domain did not put in TitleActions for this situation simply is not there
    /// -- the same rule as the panel body, from the same computation.
    /// </summary>
    private void UpdateTitleAction(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (sender is not OleMenuCommand command) return;
        var control = ControlFor(command.CommandID.ID);
        if (control is null) return;

        var actions = Panel()?.TitleActions;
        if (actions is null)
        {
            // The panel has not rendered yet (the window is still being built).
            // Refresh is the one action that is unconditional in every situation, so
            // it stays reachable; the rest wait for a layout to justify them.
            command.Visible = control == ControlId.Refresh;
            command.Enabled = command.Visible;
            return;
        }

        var match = actions.FirstOrDefault(c => c.Id == control);
        command.Visible = match is not null;
        command.Enabled = match?.Enabled == true;
    }

    private void InvokeTitleAction(object sender)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (sender is not OleMenuCommand command) return;
        var control = ControlFor(command.CommandID.ID);
        if (control is null) return;
        Panel()?.InvokeAction(control.Value.Wire());
    }

    private static string? WireFor(int commandId)
    {
        foreach (var (id, wire) in MenuCommands)
            if (id == commandId)
                return wire;
        return null;
    }

    /// <summary>
    /// A menu entry is gated only if the toolbar gates it too, and off the same layout.
    /// The panel not having rendered yet is not a reason to grey the menu out: opening
    /// the window is part of running the command, and until then there is no situation to
    /// gate against.
    /// </summary>
    private void UpdateMenuAction(object sender, EventArgs e)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (sender is not OleMenuCommand command) return;
        var wire = WireFor(command.CommandID.ID);
        if (wire is null) return;

        command.Visible = true;
        if (!GatedMenuCommands.TryGetValue(wire, out var control))
        {
            command.Enabled = true;
            return;
        }
        var actions = Panel()?.TitleActions;
        if (actions is null)
        {
            command.Enabled = true;
            return;
        }
        var match = actions.FirstOrDefault(c => c.Id == control);
        command.Enabled = match?.Enabled == true;
    }

    /// <summary>
    /// Runs a menu entry through the panel's action path, opening the tool window first if
    /// it is not there yet — the actions read the review state the panel holds, so the
    /// menu cannot be a second way of reaching a panel that does not exist. The refresh
    /// before the action is what makes a picker (which branches? which saved review?) list
    /// what the repository has now rather than what it had when the window was last looked
    /// at.
    /// </summary>
    private void InvokeMenuAction(object sender)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (sender is not OleMenuCommand command) return;
        var wire = WireFor(command.CommandID.ID);
        if (wire is null) return;
        JoinableTaskFactory.RunAsync(async () =>
        {
            await ShowToolWindowAsync();
            var panel = Panel();
            if (panel is null) return;
            await panel.InvokeActionAsync(wire);
        }).FileAndForget("gitreview/menuaction");
    }

    private async Task ShowToolWindowAsync()
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync();
        var window = await ShowToolWindowAsync(
            typeof(GitReviewToolWindow),
            id: 0,
            create: true,
            cancellationToken: DisposalToken);
        if (window?.Frame is null)
            throw new NotSupportedException("Cannot create the git review tool window.");
    }
}
