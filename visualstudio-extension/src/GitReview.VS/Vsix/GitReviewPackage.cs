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
    public const string OptionsPageName = "General";

    private static readonly Guid CommandSet = new(CommandSetGuidString);

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
        }
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
