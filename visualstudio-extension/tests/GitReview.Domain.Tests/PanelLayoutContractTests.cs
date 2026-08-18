using System.Text.RegularExpressions;
using Xunit;
using YamlDotNet.Core;
using YamlDotNet.RepresentationModel;

namespace GitReview.Domain.Tests;

/// <summary>
/// Structural parity gate: layout of each fixture vs panel_layout in the canonical YAML.
/// Port of jetbrains PanelLayoutContractTest.
/// </summary>
public class PanelLayoutContractTests
{
    private static readonly HashSet<ControlId> TitleOnly = new()
    {
        ControlId.Refresh,
        ControlId.FinishReview,
        ControlId.SaveReview,
        ControlId.AbortReview,
        ControlId.PreviewEdits,
    };

    [Fact]
    public void Canonical_file_is_present()
    {
        var file = CanonicalFile();
        Assert.True(File.Exists(file), $"canonical missing at {file} — never skip this gate");
    }

    [Fact]
    public void Walk_control_sequence_matches_canonical_ids_and_labels()
    {
        AssertLayoutAgainstCanonical("review-walk", PanelLayoutBuilder.PanelLayout(Fixtures.ReviewWalk()));
    }

    [Fact]
    public void Draft_walk_keeps_same_control_sequence_as_any_walk()
    {
        AssertLayoutAgainstCanonical("review-walk", PanelLayoutBuilder.PanelLayout(Fixtures.ReviewWalkDraft()));
    }

    [Fact]
    public void Step_control_sequence_matches_canonical()
    {
        AssertLayoutAgainstCanonical("review-step", PanelLayoutBuilder.PanelLayout(Fixtures.ReviewStep()));
    }

    [Fact]
    public void Setup_control_sequence_matches_canonical()
    {
        AssertLayoutAgainstCanonical("no-review-setup", PanelLayoutBuilder.PanelLayout(Fixtures.NoReviewSetup()));
    }

    [Fact]
    public void Finish_pending_controls_match_canonical()
    {
        AssertLayoutAgainstCanonical("finish-pending", PanelLayoutBuilder.PanelLayout(Fixtures.FinishPending()));
    }

    [Fact]
    public void Cli_missing_controls_match_canonical()
    {
        AssertLayoutAgainstCanonical("cli-missing", PanelLayoutBuilder.PanelLayout(Fixtures.CliMissing()));
    }

    /// <summary>
    /// Whole has no "open every change at once" control in this client, and that is the
    /// point of the test: the other two open one multi-diff window, while
    /// IVsDifferenceService opens a comparison window per pair of files, so the same
    /// button would spray a window per changed file. Recorded as
    /// <c>not_in: [visualstudio]</c> in the canonical contract.
    /// </summary>
    [Fact]
    public void Whole_has_no_open_all_changes()
    {
        var layout = PanelLayoutBuilder.PanelLayout(Fixtures.ReviewWhole());
        Assert.DoesNotContain(layout.CollectControls(), c => c.Label == "Diff");
        Assert.DoesNotContain("openAllChanges", ActionArgvMap.ProductActions);
        Assert.Contains(layout.Blocks, b => b is Block.FileRows);
    }

    [Fact]
    public void Cli_missing_title_contains_min_version()
    {
        var layout = PanelLayoutBuilder.PanelLayout(Fixtures.CliMissing());
        var para = layout.Blocks.OfType<Block.Paragraph>().First();
        Assert.Contains(CliVersion.MinCliVersion, para.Text);
        Assert.Contains("was not found", para.Text);
    }

    [Fact]
    public void Cli_outdated_title_keeps_installed_word()
    {
        var layout = PanelLayoutBuilder.PanelLayout(Fixtures.CliOutdated());
        var para = layout.Blocks.OfType<Block.Paragraph>().First();
        Assert.Contains("The installed git-review CLI is older than", para.Text);
    }

    /// <summary>
    /// 26, not the contract's 27: <c>openAllChanges</c> is <c>not_in: [visualstudio]</c>.
    /// </summary>
    [Fact]
    public void Product_actions_count_is_26()
    {
        Assert.Equal(26, ActionArgvMap.ProductActions.Count);
    }

    [Fact]
    public void Min_cli_version_constant()
    {
        Assert.Equal("0.6.0", CliVersion.MinCliVersion);
    }

    [Fact]
    public void Support_urls_match_canonical_contract()
    {
        Assert.Equal("https://github.com/EzeVillo/git-review-workflow", SupportLinks.StarUrl);
        Assert.Contains("bug_report.yml", SupportLinks.BugUrl);
    }

    private static void AssertLayoutAgainstCanonical(string key, PanelLayout layout)
    {
        var expected = ExtractControlSpecs(key);
        var actual = layout.CollectControls()
            .Where(c => !TitleOnly.Contains(c.Id))
            .Select(c => (c.Id.Wire(), c.Label, c.Emphasis.Id()))
            .ToList();

        var j = 0;
        foreach (var a in actual)
        {
            if (j < expected.Count && a.Item1 == expected[j].Id)
            {
                if (expected[j].Label is not null)
                    Assert.Equal(expected[j].Label, a.Item2);
                if (expected[j].Emphasis is not null)
                    Assert.Equal(expected[j].Emphasis, a.Item3);
                j++;
            }
        }
        Assert.True(j == expected.Count,
            $"situation {key}: matched {j}/{expected.Count} expected controls. actual=[{string.Join(", ", actual.Select(x => x.Item1))}] expected=[{string.Join(", ", expected.Select(x => x.Id))}]");
    }

    private sealed record Spec(string Id, string? Label, string? Emphasis);

    private static List<Spec> ExtractControlSpecs(string situationKey)
    {
        var yaml = LoadCanonical();
        var root = (YamlMappingNode)yaml.Documents[0].RootNode;
        var panelLayout = (YamlMappingNode)root.Children[new YamlScalarNode("panel_layout")];
        if (!panelLayout.Children.TryGetValue(new YamlScalarNode(situationKey), out var sitNode))
            throw new InvalidOperationException($"panel_layout missing situation {situationKey}");
        var sit = (YamlMappingNode)sitNode;
        var blocks = (YamlSequenceNode)sit.Children[new YamlScalarNode("blocks")];
        return ExtractFromBlocks(blocks);
    }

    private static List<Spec> ExtractFromBlocks(YamlSequenceNode blocks)
    {
        var specs = new List<Spec>();
        foreach (var b in blocks)
        {
            if (b is not YamlMappingNode map) continue;
            var blockType = Scalar(map, "block");
            if (blockType == "row" || blockType is null && map.Children.ContainsKey(new YamlScalarNode("controls")))
            {
                if (map.Children.TryGetValue(new YamlScalarNode("controls"), out var controlsNode)
                    && controlsNode is YamlSequenceNode controls)
                {
                    foreach (var c in controls)
                    {
                        if (c is YamlMappingNode cm)
                            specs.Add(new Spec(Scalar(cm, "id")!, Scalar(cm, "label"), Scalar(cm, "emphasis")));
                    }
                }
            }
            else if (blockType == "code_command")
            {
                specs.Add(new Spec(
                    Scalar(map, "control") ?? "copyCliInstall",
                    Scalar(map, "label"),
                    "secondary"));
            }
            else if (blockType == "banner" || map.Children.ContainsKey(new YamlScalarNode("row")))
            {
                if (map.Children.TryGetValue(new YamlScalarNode("row"), out var rowNode)
                    && rowNode is YamlMappingNode row
                    && row.Children.TryGetValue(new YamlScalarNode("controls"), out var rc)
                    && rc is YamlSequenceNode rcs)
                {
                    foreach (var c in rcs)
                    {
                        if (c is YamlMappingNode cm)
                            specs.Add(new Spec(Scalar(cm, "id")!, Scalar(cm, "label"), Scalar(cm, "emphasis")));
                    }
                }
            }
            else if (blockType == "tools_section" || map.Children.ContainsKey(new YamlScalarNode("blocks")))
            {
                if (map.Children.TryGetValue(new YamlScalarNode("blocks"), out var nested)
                    && nested is YamlSequenceNode ns)
                    specs.AddRange(ExtractFromBlocks(ns));
            }
        }
        return specs;
    }

    private static string? Scalar(YamlMappingNode map, string key)
    {
        if (!map.Children.TryGetValue(new YamlScalarNode(key), out var n)) return null;
        if (n is not YamlScalarNode s) return null;
        // RepresentationModel keeps a plain `null`/`~` as the literal text "null", untagged.
        if (s.Style == ScalarStyle.Plain && (string.IsNullOrEmpty(s.Value) || s.Value is "null" or "Null" or "NULL" or "~"))
            return null;
        return s.Value;
    }

    private static YamlStream LoadCanonical()
    {
        var text = File.ReadAllText(CanonicalFile()).Replace("\r\n", "\n");
        var yaml = new YamlStream();
        yaml.Load(new StringReader(text));
        return yaml;
    }

    private static string CanonicalFile()
    {
        // tests/GitReview.Domain.Tests → visualstudio-extension → repo root
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "contracts", "client-product-surface.yaml");
            if (File.Exists(candidate)) return candidate;
            // also walk up from project
            candidate = Path.Combine(dir.FullName, "..", "..", "..", "..", "..", "contracts", "client-product-surface.yaml");
            candidate = Path.GetFullPath(candidate);
            if (File.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        // fallback relative to repo when running from solution
        var fromCwd = Path.GetFullPath(Path.Combine(
            Directory.GetCurrentDirectory(),
            "..", "..", "..", "..", "contracts", "client-product-surface.yaml"));
        return fromCwd;
    }
}

internal static class Fixtures
{
    public static PanelModel CliMissing() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(Situation.CliMissing, Stderr: "not found"),
        new PanelInputs(false));

    public static PanelModel CliOutdated() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(Situation.CliOutdated, Stderr: "0.3.0"),
        new PanelInputs(false));

    public static PanelModel NoReviewSetup() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(Situation.NoReview, Config: new EffectiveConfig(null, "origin")),
        new PanelInputs(false));

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

    public static PanelModel ReviewWalk()
    {
        var walkPorcelain =
            "state\treview/feature\tfeature\tdeadbeefcafebabe\twalk\tapplied\t1\t3\t3\t\"src/a.kt\"\t1\n" +
            "entry\t1\tsrc/a.kt\t1\t1\nentry\t2\tsrc/b.kt\t0\t1\nentry\t3\tsrc/c.kt\t0\t0";
        var walkParsed = Porcelain.ParsePorcelain(walkPorcelain);
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.Review, State: walkParsed.State, Entries: walkParsed.Entries),
            new PanelInputs(false, Why: new PanelWhy(WhyState.Present, "Because it matters.")));
        return model with { AtFirst = true, AtLast = false };
    }

    public static PanelModel ReviewWalkDraft()
    {
        var porcelain =
            "state\treview/feature\tfeature\tdeadbeefcafebabe\twalk\tapplied\t1\t3\t3\t\"src/a.kt\"\t0\n" +
            "entry\t1\tsrc/a.kt\t0\t1\nentry\t2\tsrc/b.kt\t0\t1\nentry\t3\tsrc/c.kt\t0\t0\ndraft";
        var parsed = Porcelain.ParsePorcelain(porcelain);
        var model = PanelModelBuilder.BuildPanelModel(
            new ReviewState(Situation.Review, State: parsed.State, Entries: parsed.Entries, Draft: parsed.Draft),
            new PanelInputs(false, Why: new PanelWhy(WhyState.Present, "Because I read it first.")));
        return model with { AtFirst = true, AtLast = false };
    }

    public static PanelModel ReviewStep() => PanelModelBuilder.BuildPanelModel(
        new ReviewState(
            Situation.Review,
            State: new StateRecord(
                "review/f", "f", "tipsha01", ReviewMode.Step, WalkthroughStatus.None,
                Position: 2, Total: 4, Recorded: 4, Current: "abc1234"),
            Entries: new[]
            {
                new EntryRecord(1, "aaa1111", Banked: false),
                new EntryRecord(2, "abc1234", Banked: true),
                new EntryRecord(3, "ccc3333", Banked: false),
                new EntryRecord(4, "ddd4444", Banked: false),
            },
            Files: new[]
            {
                new EntryRecord(1, Unquote.ToPathRef("src/a.kt")),
                new EntryRecord(2, Unquote.ToPathRef("src/b.kt")),
            },
            Subjects: new Dictionary<int, string> { [2] = "Fix the thing" },
            Authors: new Dictionary<int, string> { [2] = "Ada" }),
        new PanelInputs(false, LastOpened: "src/a.kt"));

    public static PanelModel ReviewWhole()
    {
        var entries = new[]
        {
            new EntryRecord(1, Unquote.ToPathRef("file1.kt")),
            new EntryRecord(2, Unquote.ToPathRef("file2.kt")),
        };
        return PanelModelBuilder.BuildPanelModel(
            new ReviewState(
                Situation.Review,
                State: new StateRecord("review/f", "f", "tipsha01", ReviewMode.Whole, WalkthroughStatus.None),
                Entries: entries,
                Base: "main"),
            new PanelInputs(false, LastOpened: "file1.kt"));
    }
}
