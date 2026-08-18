using System.Windows;
using System.Windows.Media;
using GitReview.Domain;
using GitReview.VS.Preview;
using GitReview.VS.ToolWindows;

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

        VerifyChrome("dark", PanelChrome.DefaultDark, Check);
        VerifyChrome("light", PanelChrome.DefaultLight, Check);

        Console.WriteLine(failures == 0
            ? $"verify: ok ({PanelFixtures.All().Count} fixtures)"
            : $"verify: {failures} failure(s)");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>
    /// Both chrome variants have to stand on their own: <see cref="VsTheme"/> takes
    /// the host's colors where an environment key owns one, but every brush with no
    /// key behind it is served from here, and the fallback serves all of them. Two
    /// ways that went wrong before, both invisible until someone opened the panel in
    /// the other theme: a brush defaulting to <c>SystemColors</c>, which follows
    /// Windows rather than the IDE, and a fill picked for one variant sitting under
    /// text picked for the other.
    /// </summary>
    private static void VerifyChrome(string variant, PanelChrome chrome, Action<string, bool, string> check)
    {
        var system = typeof(SystemColors).GetProperties()
            .Where(p => typeof(Brush).IsAssignableFrom(p.PropertyType))
            .Select(p => p.GetValue(null))
            .OfType<Brush>()
            .ToList();

        var brushes = typeof(PanelChrome).GetProperties()
            .Where(p => p.PropertyType == typeof(Brush))
            .Select(p => (p.Name, Brush: (Brush)p.GetValue(chrome)!))
            .ToList();

        var borrowed = brushes.Where(b => system.Any(sc => ReferenceEquals(sc, b.Brush))).ToList();
        check($"chrome:{variant}:no-system-colors", borrowed.Count == 0,
            string.Join(", ", borrowed.Select(b => b.Name)));

        // Text over its own fill. The thresholds are WCAG AA: 4.5 for body text,
        // 3 for the muted and link weights, which the other two clients get from
        // the host's own tokens rather than from a ratio.
        Contrast("foreground", chrome.Background, chrome.Foreground, 4.5);
        Contrast("muted", chrome.Background, chrome.MutedForeground, 3.0);
        Contrast("link", chrome.Background, chrome.LinkForeground, 3.0);
        Contrast("badge", chrome.BadgeBackground, chrome.BadgeForeground, 4.5);
        Contrast("code", chrome.CodeBackground, chrome.Foreground, 4.5);
        Contrast("warning", chrome.WarningBackground, chrome.Foreground, 4.5);
        Contrast("primary", chrome.PrimaryBackground, chrome.PrimaryForeground, 4.5);
        Contrast("row-selected", chrome.RowSelected, chrome.Foreground, 3.0);

        // Fills that carry no text still have to be visible against the panel.
        Contrast("skeleton", chrome.Background, chrome.Skeleton, 1.1);
        Contrast("border", chrome.Background, chrome.Border, 1.1);
        Contrast("row-hover", chrome.Background, chrome.RowHover, 1.02);

        void Contrast(string name, Brush back, Brush front, double min)
        {
            var ratio = Ratio(Solid(back), Solid(front));
            check($"chrome:{variant}:{name}", ratio >= min, $"{ratio:0.00} < {min:0.00}");
        }
    }

    private static Color Solid(Brush b) => ((SolidColorBrush)b).Color;

    private static double Ratio(Color a, Color b)
    {
        var (la, lb) = (Luminance(a), Luminance(b));
        var (hi, lo) = la > lb ? (la, lb) : (lb, la);
        return (hi + 0.05) / (lo + 0.05);
    }

    private static double Luminance(Color c) =>
        0.2126 * Channel(c.R) + 0.7152 * Channel(c.G) + 0.0722 * Channel(c.B);

    private static double Channel(byte v)
    {
        var s = v / 255.0;
        return s <= 0.03928 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
    }
}
