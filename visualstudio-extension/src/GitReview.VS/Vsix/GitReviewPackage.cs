// Optional VSIX package entry. Compiled always; VSSDK attributes activate when
// GitReviewPackVsix=true and Community.VisualStudio.Toolkit is referenced.
//
// Layout of the tool window content is PanelView driven by PanelLayout — the
// same block tree as JetBrains PanelRenderer and the VS Code webview.

using System.Runtime.InteropServices;
using GitReview.VS.Settings;
using GitReview.VS.ToolWindows;

namespace GitReview.VS.Vsix;

/// <summary>
/// Visual Studio package host. When the full VSSDK workload is installed, wire
/// this class with ProvideToolWindow / PackageRegistration attributes (see README).
/// </summary>
[Guid(PackageGuidString)]
public class GitReviewPackage
{
    public const string PackageGuidString = "a3f8c2e1-7b4d-4e9a-9c1f-2d5e6a8b0c3d";
    public const string ToolWindowGuidString = "b4e9d3f2-8c5e-4f0b-ad2a-3e6f7b9c1d4e";

    public static GitReviewPanelController? ActivePanel { get; private set; }

    public static GitReviewPanelController CreatePanel(Func<IReadOnlyList<string>> roots)
    {
        ActivePanel?.Dispose();
        ActivePanel = new GitReviewPanelController(
            roots,
            () => GitReviewOptions.Current.Path);
        return ActivePanel;
    }
}
