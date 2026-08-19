using System.Windows;
using System.Windows.Media;
using GitReview.Domain;
using GitReview.Fixtures;
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

        Check("min_cli_version", CliVersion.MinCliVersion == "0.7.0");
        // 26, not the contract's 27: openAllChanges is not_in: [visualstudio].
        Check("product_actions_26", ActionArgvMap.ProductActions.Count == 26);
        Check("npm_install", InstallHint.NpmInstallCmd.Contains("git-review-workflow"));
        Check("support_star", SupportLinks.StarUrl.Contains("git-review-workflow"));

        // Every fixture has to produce a layout the panel can actually draw, in both
        // the resolved and the loading pass. "at least one control" passed for almost
        // anything, which made this the weakest gate in the suite for eight of the
        // fixtures; the shape checks below are what the WPF renderer needs to be true.
        foreach (var (name, model) in PanelFixtures.All())
        {
            try
            {
                var layout = PanelLayoutBuilder.PanelLayout(model);
                var problems = LayoutProblems(layout);
                var loading = PanelLayoutBuilder.PanelLayout(model, loading: true);
                problems.AddRange(LayoutProblems(loading).Select(p => $"loading: {p}"));
                Check($"fixture:{name}", problems.Count == 0, string.Join("; ", problems));
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
        // No "open every change at once" here: this host would open one comparison
        // window per file. Contract: not_in: [visualstudio]. Checked by id and
        // against the action list — the enum has no OpenAllChanges member, so a
        // label check could never have failed.
        Check("whole:no-open-all",
            whole.CollectControls().All(c => c.Id.Wire() != "openAllChanges")
            && !ActionArgvMap.ProductActions.Contains("openAllChanges"));
        Check("whole:file-rows", whole.Blocks.Any(b => b is Block.FileRows));

        VerifyChrome("dark", PanelChrome.DefaultDark, Check);
        VerifyChrome("light", PanelChrome.DefaultLight, Check);
        VerifyButtons(Check);

        Console.WriteLine(failures == 0
            ? $"verify: ok ({PanelFixtures.All().Count} fixtures)"
            : $"verify: {failures} failure(s)");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>
    /// What the WPF renderer needs of a layout, checked on every fixture: a screen
    /// with nothing on it, a control with no accessible name, or a row the panel
    /// cannot lay out are all things that draw as a blank pane rather than throw.
    /// </summary>
    private static List<string> LayoutProblems(PanelLayout layout)
    {
        var problems = new List<string>();
        if (layout.Blocks.Count == 0) problems.Add("no blocks");

        var controls = layout.CollectControls();
        if (!controls.Any(c => c.Id == ControlId.Refresh))
            problems.Add("no refresh in the title bar");
        foreach (var c in controls)
        {
            if (string.IsNullOrWhiteSpace(c.AccessibleName))
                problems.Add($"{c.Id.Wire()} has no accessible name");
            if (c.Label is null && c.Emphasis != Emphasis.Icon)
                problems.Add($"{c.Id.Wire()} has no label and is not an icon");
        }
        // Row controls are exempt, for the same reason PanelLayout's own invariant
        // exempts them: a row control is a per-row affordance repeated once per
        // row, so counting them would make the rule depend on how many drafts or
        // reviews the reviewer happens to have.
        if (controls.Count(c => c.Emphasis == Emphasis.Primary && c.Index is null) > 1)
            problems.Add("more than one primary");

        foreach (var block in Flatten(layout.Blocks))
        {
            switch (block)
            {
                case Block.Row row when row.Controls.Count is < 1 or > 2:
                    problems.Add($"row with {row.Controls.Count} controls");
                    break;
                case Block.Paragraph p when string.IsNullOrWhiteSpace(p.Text):
                    problems.Add("empty paragraph");
                    break;
                case Block.Heading h when string.IsNullOrWhiteSpace(h.Text):
                    problems.Add("empty heading");
                    break;
                case Block.InventoryRows inv:
                    foreach (var row in inv.Rows)
                    {
                        if (string.IsNullOrWhiteSpace(row.Name)) problems.Add("inventory row with no name");
                        if (row.Controls.Count == 0 && string.IsNullOrWhiteSpace(row.HelpTooltip))
                            problems.Add($"inventory row {row.Name} has neither controls nor a tooltip");
                    }
                    break;
            }
        }
        return problems;
    }

    private static IEnumerable<Block> Flatten(IEnumerable<Block> blocks)
    {
        foreach (var b in blocks)
        {
            yield return b;
            if (b is Block.ToolsSection ts)
                foreach (var nested in Flatten(ts.NestedBlocks)) yield return nested;
        }
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
        Contrast("secondary", chrome.SecondaryBackground, chrome.Foreground, 4.5);
        // A disabled label is exempt from AA, but not from being read: this is the
        // pair that used to come out of WPF's stock template as #838383 on #F4F4F4.
        Contrast("disabled", chrome.DisabledBackground, chrome.DisabledForeground, 3.0);

        // Fills that carry no text still have to be visible against the panel.
        Contrast("skeleton", chrome.Background, chrome.Skeleton, 1.1);
        Contrast("border", chrome.Background, chrome.Border, 1.1);
        Contrast("row-hover", chrome.Background, chrome.RowHover, 1.02);
        // Hover has to differ from rest, and a disabled button from the panel it sits on.
        Contrast("button-hover", chrome.SecondaryBackground, chrome.ButtonHover, 1.1);
        Contrast("primary-hover", chrome.PrimaryBackground, chrome.PrimaryHover, 1.1);
        Contrast("disabled-fill", chrome.Background, chrome.DisabledBackground, 1.1);

        void Contrast(string name, Brush back, Brush front, double min)
        {
            var ratio = Ratio(Solid(back), Solid(front));
            check($"chrome:{variant}:{name}", ratio >= min, $"{ratio:0.00} < {min:0.00}");
        }
    }

    /// <summary>
    /// The panel's buttons have to keep taking their colors from the style in
    /// <see cref="PanelButtons"/> and not from assignments on the instance. WPF's
    /// stock template paints hover and disabled from inside the template, and a
    /// local Background is exactly what stops a style trigger from overriding it —
    /// which is how a disabled Continue came out as the Windows fill with a #838383
    /// label on it, a white block over the dark theme. Renders for real (Main is
    /// STA), because that is the only place where the triggers have run.
    /// </summary>
    private static void VerifyButtons(Action<string, bool, string> check)
    {
        // A repository whose saved reviews cannot all be resumed: one has an active
        // review of the same branch, one has no metadata. Both keep Continue disabled.
        var listPorcelain = string.Join("\n", new[]
        {
            "branch\treview/feature/i18n\t0\t0\t1",
            "branch\treview-saved/feature/i18n\t1\t0\t0\twhole",
            "branch\treview-saved/feature/search\t1\t0\t0\twalk\t2\t3",
        });
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.NoReview,
                Config: new EffectiveConfig("main", "origin"),
                Branches: Porcelain.ParseListPorcelain(listPorcelain)),
            new PanelInputs(false));

        var chrome = PanelChrome.DefaultDark;
        var panel = new PanelView(chrome) { Width = 380, Height = 700 };
        panel.Render(PanelLayoutBuilder.PanelLayout(model));
        panel.Measure(new Size(380, 700));
        panel.Arrange(new Rect(0, 0, 380, 700));
        panel.UpdateLayout();

        var buttons = Descendants(panel).OfType<System.Windows.Controls.Button>().ToList();
        check("buttons:styled", buttons.Count > 0 && buttons.All(b => b.Style is not null),
            $"{buttons.Count(b => b.Style is null)} of {buttons.Count} on the stock template");

        var disabled = buttons.Where(b => !b.IsEnabled).ToList();
        check("buttons:disabled-present", disabled.Count > 0, "fixture stopped producing one");
        check("buttons:disabled-fill",
            disabled.All(b => ReferenceEquals(b.Background, chrome.DisabledBackground)),
            string.Join(", ", disabled
                .Where(b => !ReferenceEquals(b.Background, chrome.DisabledBackground))
                .Select(b => $"{b.Content}={Describe(b.Background)}")));
        check("buttons:disabled-text",
            disabled.All(b => ReferenceEquals(b.Foreground, chrome.DisabledForeground)),
            string.Join(", ", disabled
                .Where(b => !ReferenceEquals(b.Foreground, chrome.DisabledForeground))
                .Select(b => $"{b.Content}={Describe(b.Foreground)}")));
    }

    private static string Describe(Brush? b) =>
        b is SolidColorBrush s ? s.Color.ToString() : b?.ToString() ?? "null";

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            yield return child;
            foreach (var d in Descendants(child)) yield return d;
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
