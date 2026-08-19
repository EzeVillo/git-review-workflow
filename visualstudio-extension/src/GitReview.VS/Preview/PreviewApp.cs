using System.Windows;
using GitReview.Domain;
using GitReview.VS.ToolWindows;

namespace GitReview.VS.Preview;

/// <summary>
/// Standalone WPF preview of every PanelModel fixture (parity with JetBrains runPanelPreview).
/// Run: dotnet run --project src/GitReview.VS -- --preview
/// </summary>
public static class PreviewApp
{
    [STAThread]
    public static int Run()
    {
        var app = new Application();
        var window = new Window
        {
            Title = "git review — panel preview",
            Width = 380,
            Height = 720,
        };

        var fixtures = PanelFixtures.All();
        var index = 0;
        // The panel bakes its chrome in at construction (same as the tool window,
        // which rebuilds on VSColorTheme.ThemeChanged), so switching themes here
        // swaps the view rather than repainting it.
        var dark = true;
        PanelView panel = null!;

        var root = new System.Windows.Controls.DockPanel();
        var nav = new System.Windows.Controls.StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            Margin = new Thickness(4),
        };
        var prev = new System.Windows.Controls.Button { Content = "◀ Prev", Margin = new Thickness(0, 0, 4, 0), Padding = new Thickness(8, 4, 8, 4) };
        var next = new System.Windows.Controls.Button { Content = "Next ▶", Margin = new Thickness(0, 0, 12, 0), Padding = new Thickness(8, 4, 8, 4) };
        var theme = new System.Windows.Controls.Button { Padding = new Thickness(8, 4, 8, 4) };

        void Show(int i)
        {
            index = (i + fixtures.Count) % fixtures.Count;
            var (name, model) = fixtures[index];
            window.Title = $"git review preview — {name} ({(dark ? "dark" : "light")})";
            var layout = PanelLayoutBuilder.PanelLayout(model);
            panel.Render(layout);
        }

        void Rebuild()
        {
            var chrome = dark ? PanelChrome.DefaultDark : PanelChrome.DefaultLight;
            window.Background = chrome.Background;
            theme.Content = dark ? "Theme: dark" : "Theme: light";
            if (panel is not null) root.Children.Remove(panel);
            panel = new PanelView(chrome);
            root.Children.Add(panel);
            Show(index);
        }

        prev.Click += (_, _) => Show(index - 1);
        next.Click += (_, _) => Show(index + 1);
        theme.Click += (_, _) => { dark = !dark; Rebuild(); };
        nav.Children.Add(prev);
        nav.Children.Add(next);
        nav.Children.Add(theme);
        System.Windows.Controls.DockPanel.SetDock(nav, System.Windows.Controls.Dock.Top);
        root.Children.Add(nav);
        window.Content = root;

        window.KeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Left) Show(index - 1);
            if (e.Key == System.Windows.Input.Key.Right) Show(index + 1);
            if (e.Key == System.Windows.Input.Key.T) { dark = !dark; Rebuild(); }
        };

        Rebuild();
        app.Run(window);
        return 0;
    }
}

/// <summary>Shared fixtures — port of jetbrains PanelFixtures.</summary>
public static class PanelFixtures
{
    public static IReadOnlyList<(string Name, PanelModel Model)> All() => new[]
    {
        ("cli-missing", CliMissing()),
        ("cli-outdated", CliOutdated()),
        ("no-review setup", NoReviewSetup()),
        ("no-review ready", NoReviewReady()),
        ("no-review drafts", NoReviewDrafts()),
        ("finish-pending", FinishPending()),
        ("out-of-range", OutOfRange()),
        ("error", Error()),
        ("review walk", ReviewWalk()),
        ("review step", ReviewStep()),
        ("review whole", ReviewWhole()),
        ("finish-conflict", FinishConflict()),
        ("review walk draft", ReviewWalkDraft()),
        ("review walk busy", ReviewWalk(busy: true)),
        ("review whole empty", ReviewWholeEmpty()),
    };

    public static PanelModel CliMissing() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(Situation.CliMissing, Stderr: "not found"),
        new PanelInputs(false));

    public static PanelModel CliOutdated() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(Situation.CliOutdated, Stderr: "0.3.0"),
        new PanelInputs(false));

    public static PanelModel NoReviewSetup() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(Situation.NoReview, Config: new EffectiveConfig(null, "origin")),
        new PanelInputs(false));

    public static PanelModel NoReviewReady()
    {
        var listPorcelain = "branch\treview-saved/feature\t1\t0\t0\twalk\t2\t5\nbranch\treview/other\t0\t0\t1\tstep";
        return PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.NoReview,
                Config: new EffectiveConfig("main", "origin"),
                Branches: Porcelain.ParseListPorcelain(listPorcelain)),
            new PanelInputs(false));
    }

    /// <summary>
    /// Two reading orders started and not paused, plus the inventory below. The second
    /// row does NOT offer "Validate and start": its instruction block was deleted by
    /// hand, so the CLI reports `unknown` and the flags cannot be replicated.
    /// </summary>
    public static PanelModel NoReviewDrafts()
    {
        var cfg =
            "draft\tfeature/telemetry\t/repo/.git/review-walkthrough/feature/telemetry.md\t3\t9\tlocal\tdelta\n" +
            "draft\tfeature/pagos\t/repo/.git/review-walkthrough/feature/pagos.md\t0\t5\tunknown\tunknown\n";
        return PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.NoReview,
                Config: new EffectiveConfig("main", "origin"),
                Branches: Porcelain.ParseListPorcelain("branch\treview-saved/feature\t1\t0\t0\twalk\t2\t5"),
                Drafts: ConfigPorcelain.ParseConfigPorcelain(cfg).Drafts),
            new PanelInputs(false));
    }

    public static PanelModel FinishPending()
    {
        var branches = new[]
        {
            new BranchRecord("review/feature", false, true, false,
                Finish: new BranchFinish("pending", false)),
        };
        return PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.FinishPending, Branches: branches),
            new PanelInputs(false));
    }

    public static PanelModel OutOfRange() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(Situation.OutOfRange, Stderr: "base moved"),
        new PanelInputs(false));

    public static PanelModel Error() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(
            Situation.Error,
            Stderr: "Open a single-folder workspace that is a git repository. git review uses one root (like the CLI cwd); multi-root is not supported."),
        new PanelInputs(false));

    public static PanelModel ReviewWalk(
        bool busy = false,
        PanelWhy? why = null,
        bool atFirst = true,
        bool atLast = false,
        int position = 1)
    {
        why ??= new PanelWhy(WhyState.Present, "Because it matters.");
        var walkPorcelain =
            $"state\treview/feature\tfeature\tdeadbeefcafebabe\twalk\tapplied\t{position}\t3\t3\t\"src/a.kt\"\t1\n" +
            "entry\t1\tsrc/a.kt\t1\t1\nentry\t2\tsrc/b.kt\t0\t1\nentry\t3\tsrc/c.kt\t0\t0";
        var walkParsed = Porcelain.ParsePorcelain(walkPorcelain);
        var walkState = new ReviewState(
            Situation.Review,
            State: walkParsed.State,
            Entries: walkParsed.Entries);
        var model = PanelModelBuilder.BuildPanelModel(walkState, new PanelInputs(busy, Why: why));
        return model with { AtFirst = atFirst, AtLast = atLast || position >= (model.Total ?? 0) };
    }

    public static PanelModel ReviewWalkDraft()
    {
        var porcelain =
            "state\treview/feature\tfeature\tdeadbeefcafebabe\twalk\tapplied\t1\t3\t3\t\"src/a.kt\"\t0\n" +
            "entry\t1\tsrc/a.kt\t0\t1\nentry\t2\tsrc/b.kt\t0\t1\nentry\t3\tsrc/c.kt\t0\t0\ndraft";
        var parsed = Porcelain.ParsePorcelain(porcelain);
        var state = new ReviewState(
            Situation.Review,
            State: parsed.State,
            Entries: parsed.Entries,
            Draft: parsed.Draft);
        var model = PanelModelBuilder.BuildPanelModel(
            state,
            new PanelInputs(false, Why: new PanelWhy(WhyState.Present, "Because I read it first.")));
        return model with { AtFirst = true, AtLast = false };
    }

    public static PanelModel ReviewStep(bool busy = false, int position = 2, bool withFiles = true)
    {
        var stepFiles = withFiles
            ? new[]
            {
                new EntryRecord(1, Unquote.ToPathRef("src/a.kt")),
                new EntryRecord(2, Unquote.ToPathRef("src/b.kt")),
            }
            : Array.Empty<EntryRecord>();
        return PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord(
                    "review/f", "f", "tipsha01", ReviewMode.Step, WalkthroughStatus.None,
                    Position: position, Total: 4, Recorded: 4, Current: "abc1234"),
                Entries: new[]
                {
                    new EntryRecord(1, "aaa1111", Banked: false),
                    new EntryRecord(2, "abc1234", Banked: true),
                    new EntryRecord(3, "ccc3333", Banked: false),
                    new EntryRecord(4, "ddd4444", Banked: false),
                },
                Files: stepFiles,
                Subjects: new Dictionary<int, string> { [2] = "Fix the thing" },
                Authors: new Dictionary<int, string> { [2] = "Ada" }),
            new PanelInputs(busy, LastOpened: withFiles ? "src/a.kt" : null));
    }

    public static PanelModel ReviewWhole(int fileCount = 2)
    {
        var entries = Enumerable.Range(1, fileCount)
            .Select(i => new EntryRecord(i, Unquote.ToPathRef($"file{i}.kt")))
            .ToList();
        return PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord("review/f", "f", "tipsha01", ReviewMode.Whole, WalkthroughStatus.None),
                Entries: entries,
                Base: "main"),
            new PanelInputs(false, LastOpened: entries.Count > 0
                ? ((PathRef)entries[0].Id).Display
                : null));
    }

    public static PanelModel ReviewWholeEmpty() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(
            Situation.Review,
            State: new StateRecord("review/f", "f", "tipsha01", ReviewMode.Whole, WalkthroughStatus.None),
            Entries: Array.Empty<EntryRecord>(),
            Base: "main"),
        new PanelInputs(false));

    public static PanelModel FinishConflict() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(
            Situation.FinishConflict,
            State: new StateRecord(
                "review/feature", "feature", "deadbeef", ReviewMode.Walk, WalkthroughStatus.Applied,
                Position: 1, Total: 2, Recorded: 2, Current: Unquote.ToPathRef("src/a.kt")),
            Entries: new[]
            {
                new EntryRecord(1, Unquote.ToPathRef("src/a.kt"), Essential: true, Annotated: true),
                new EntryRecord(2, Unquote.ToPathRef("src/b.kt"), Essential: false, Annotated: true),
            },
            Finish: new StatusFinishRecord("conflict", false)),
        new PanelInputs(false, Why: new PanelWhy(WhyState.Present, "Why text.")));
}
