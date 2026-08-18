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
