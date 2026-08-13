using GitReview.Domain;
using GitReview.VS.Preview;

namespace GitReview.VS;

/// <summary>
/// Entry point for standalone preview / smoke runs.
/// Inside Visual Studio the MEF / package class is the entry (when VSIX is packed).
/// </summary>
public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Any(a => a is "--preview" or "-p"))
            return PreviewApp.Run();

        if (args.Any(a => a is "--verify" or "-v"))
            return RunVerify();

        Console.WriteLine("git review workflow — Visual Studio client");
        Console.WriteLine();
        Console.WriteLine("  --preview   Open WPF panel fixture gallery (←/→)");
        Console.WriteLine("  --verify    Run layout + constant smoke checks (no xUnit)");
        Console.WriteLine();
        Console.WriteLine("Domain constants (anti-drift):");
        Console.WriteLine($"  min_cli_version = {CliVersion.MinCliVersion}");
        Console.WriteLine($"  npm_install     = {InstallHint.NpmInstallCmd}");
        Console.WriteLine($"  npm_update      = {InstallHint.NpmUpdateCmd}");
        Console.WriteLine($"  support.star    = {SupportLinks.StarUrl}");
        Console.WriteLine($"  support.bug     = {SupportLinks.BugUrl}");
        Console.WriteLine($"  multi-root fragment present: multi-root is not supported");
        return 0;
    }

    /// <summary>
    /// Structural smoke: every fixture produces a layout; walk/setup/cli labels match
    /// the product surface (same gate as PanelLayoutContractTests).
    /// </summary>
    private static int RunVerify()
    {
        var failures = 0;
        void Check(string name, bool ok, string detail = "")
        {
            if (ok) Console.WriteLine($"  ok  {name}");
            else
            {
                failures++;
                Console.WriteLine($"  FAIL {name} {detail}");
            }
        }

        Check("min_cli_version", CliVersion.MinCliVersion == "0.6.0");
        Check("product_actions_27", ActionArgvMap.ProductActions.Count == 27);
        Check("npm_install", InstallHint.NpmInstallCmd.Contains("git-review-workflow"));
        Check("support_star", SupportLinks.StarUrl.Contains("git-review-workflow"));

        foreach (var (name, model) in PanelFixtures.All())
        {
            try
            {
                var layout = PanelLayoutBuilder.PanelLayout(model);
                var controls = layout.CollectControls();
                Check($"fixture:{name}", controls.Count >= 1, $"controls={controls.Count}");
            }
            catch (Exception ex)
            {
                Check($"fixture:{name}", false, ex.Message);
            }
        }

        var walk = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk());
        var walkIds = walk.CollectControls()
            .Where(c => c.Id is not (ControlId.Refresh or ControlId.FinishReview
                or ControlId.SaveReview or ControlId.AbortReview or ControlId.PreviewEdits))
            .Select(c => c.Id.Wire())
            .ToList();
        Check("walk:openEntry", walkIds.Contains("openEntry"));
        Check("walk:openChange", walkIds.Contains("openChange"));
        Check("walk:showWhy", walkIds.Contains("showWhy"));
        Check("walk:prev", walkIds.Contains("prev"));
        Check("walk:next", walkIds.Contains("next"));

        var setup = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewSetup());
        var setupLabels = setup.CollectControls().Select(c => c.Label).ToList();
        Check("setup:Set the base branch", setupLabels.Contains("Set the base branch"));

        var cli = PanelLayoutBuilder.PanelLayout(PanelFixtures.CliMissing());
        var title = cli.Blocks.OfType<Block.Paragraph>().First().Text;
        Check("cli-missing:title", title.Contains(CliVersion.MinCliVersion) && title.Contains("was not found"));

        var outdated = PanelLayoutBuilder.PanelLayout(PanelFixtures.CliOutdated());
        var ot = outdated.Blocks.OfType<Block.Paragraph>().First().Text;
        Check("cli-outdated:installed", ot.Contains("The installed git-review CLI is older than"));

        var whole = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole());
        Check("whole:openAllChanges",
            whole.CollectControls().Any(c => c.Id == ControlId.OpenAllChanges && c.Label == "Diff"));

        Console.WriteLine(failures == 0
            ? $"verify: ok ({PanelFixtures.All().Count} fixtures)"
            : $"verify: {failures} failure(s)");
        return failures == 0 ? 0 : 1;
    }
}
