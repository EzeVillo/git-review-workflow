using GitReview.Fixtures;
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

    /// <summary>This client's name in the contract's <c>not_in:</c> lists.</summary>
    private const string ThisClient = "visualstudio";

    [Fact]
    public void Canonical_file_is_present()
    {
        var file = CanonicalFile();
        Assert.True(File.Exists(file), $"canonical missing at {file} — never skip this gate");
    }

    [Fact]
    public void Walk_control_sequence_matches_canonical_ids_and_labels()
    {
        AssertLayoutAgainstCanonical("review-walk", PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalk()), mode: "walk");
    }

    [Fact]
    public void Draft_walk_keeps_same_control_sequence_as_any_walk()
    {
        AssertLayoutAgainstCanonical("review-walk", PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWalkDraft()), mode: "walk");
    }

    [Fact]
    public void Step_control_sequence_matches_canonical()
    {
        AssertLayoutAgainstCanonical("review-step", PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewStep()), mode: "step");
    }

    [Fact]
    public void Whole_control_sequence_matches_canonical()
    {
        AssertLayoutAgainstCanonical("review-whole", PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole()), mode: "whole");
    }

    [Fact]
    public void Finish_conflict_control_sequence_matches_canonical()
    {
        AssertLayoutAgainstCanonical("finish-conflict", PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishConflict()), mode: "walk");
    }

    [Fact]
    public void Setup_control_sequence_matches_canonical()
    {
        AssertLayoutAgainstCanonical("no-review-setup", PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewSetup()));
    }

    /// <summary>
    /// The biggest situation in the contract (eight controls) and the one that
    /// offers the destructive ones — it went unasserted while the five smaller
    /// ones were covered.
    /// </summary>
    [Fact]
    public void No_review_ready_control_sequence_matches_canonical()
    {
        AssertLayoutAgainstCanonical("no-review", PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady()));
    }

    [Fact]
    public void Finish_pending_controls_match_canonical()
    {
        AssertLayoutAgainstCanonical("finish-pending", PanelLayoutBuilder.PanelLayout(PanelFixtures.FinishPending()));
    }

    [Fact]
    public void Cli_missing_controls_match_canonical()
    {
        AssertLayoutAgainstCanonical("cli-missing", PanelLayoutBuilder.PanelLayout(PanelFixtures.CliMissing()));
    }

    [Fact]
    public void Cli_outdated_controls_match_canonical()
    {
        AssertLayoutAgainstCanonical("cli-outdated", PanelLayoutBuilder.PanelLayout(PanelFixtures.CliOutdated()));
    }

    [Fact]
    public void Out_of_range_controls_match_canonical()
    {
        AssertLayoutAgainstCanonical("out-of-range", PanelLayoutBuilder.PanelLayout(PanelFixtures.OutOfRange()));
    }

    [Fact]
    public void Error_controls_match_canonical()
    {
        AssertLayoutAgainstCanonical("error", PanelLayoutBuilder.PanelLayout(PanelFixtures.Error()));
    }

    /// <summary>
    /// Whole has no "open every change at once" control in this client, and that is the
    /// point of the test: the other two open one multi-diff window, while
    /// IVsDifferenceService opens a comparison window per pair of files, so the same
    /// button would spray a window per changed file. Recorded as
    /// <c>not_in: [visualstudio]</c> in the canonical contract, which is where
    /// <see cref="AssertLayoutAgainstCanonical"/> reads it from — asserting by id, since
    /// the enum has no <c>OpenAllChanges</c> member and a label check could never fail.
    /// </summary>
    [Fact]
    public void Whole_has_no_open_all_changes()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.ReviewWhole());
        Assert.Contains("openAllChanges", ForbiddenIds("review-whole"));
        Assert.DoesNotContain("openAllChanges", ActionArgvMap.ProductActions);
        Assert.DoesNotContain(layout.CollectControls(), c => c.Id.Wire() == "openAllChanges");
        Assert.Contains(layout.Blocks, b => b is Block.FileRows);
    }

    [Fact]
    public void Cli_missing_title_contains_min_version()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.CliMissing());
        var para = layout.Blocks.OfType<Block.Paragraph>().First();
        Assert.Contains(CliVersion.MinCliVersion, para.Text);
        Assert.Contains("was not found", para.Text);
    }

    [Fact]
    public void Cli_outdated_title_keeps_installed_word()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.CliOutdated());
        var para = layout.Blocks.OfType<Block.Paragraph>().First();
        Assert.Contains("The installed git-review CLI is older than", para.Text);
    }

    /// <summary>
    /// The contract's action list minus what it marks <c>not_in: [visualstudio]</c>,
    /// compared as a set: a bare count passes a rename plus an addition, which is
    /// exactly the pair that drifts.
    /// </summary>
    [Fact]
    public void Product_actions_are_the_contract_minus_not_in()
    {
        var expected = CanonicalActions()
            .Where(kv => !kv.Value.Contains(ThisClient))
            .Select(kv => kv.Key)
            .OrderBy(x => x, StringComparer.Ordinal)
            .ToList();
        var actual = ActionArgvMap.ProductActions
            .OrderBy(x => x, StringComparer.Ordinal)
            .ToList();
        Assert.Equal(expected, actual);
        // The count the absence is documented by, kept as a tripwire on the pair above.
        Assert.Equal(26, ActionArgvMap.ProductActions.Count);
        Assert.Equal(27, CanonicalActions().Count);
    }

    /// <summary>Every action the map claims to offer has to produce an argv (or a no-op verb).</summary>
    [Fact]
    public void Every_product_action_is_routable()
    {
        foreach (var action in ActionArgvMap.ProductActions)
        {
            var ex = Record.Exception(() => ActionArgvMap.ActionToArgv(action, ParamsFor(action)));
            Assert.True(ex is null, $"{action} is listed as a product action but does not route: {ex?.Message}");
        }
        Assert.Throws<ArgumentException>(() => ActionArgvMap.ActionToArgv("notAnAction"));
    }

    [Fact]
    public void Min_cli_version_constant()
    {
        Assert.Equal("0.7.0", CliVersion.MinCliVersion);
        Assert.Equal(CliVersion.MinCliVersion, CanonicalScalar("min_cli_version"));
    }

    [Fact]
    public void Support_urls_match_canonical_contract()
    {
        Assert.Equal("https://github.com/EzeVillo/git-review-workflow", SupportLinks.StarUrl);
        Assert.Contains("bug_report.yml", SupportLinks.BugUrl);
    }

    [Fact]
    public void The_draft_block_is_the_first_block_of_no_review_and_the_body_follows_whole()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewDrafts());
        var blocks = layout.Blocks;
        // First block the heading, second the rows: it is not a sub-layout that
        // replaces — the usual body follows underneath.
        Assert.Equal("Reading orders you started", Assert.IsType<Block.Heading>(blocks[0]).Text);
        Assert.IsType<Block.DraftRows>(blocks[1]);
        Assert.Contains(blocks, b => b is Block.InventoryRows);
        Assert.Contains(layout.CollectControls(), c => c.Id == ControlId.StartReview);
    }

    [Fact]
    public void Draft_rows_carry_the_four_canonical_controls()
    {
        var canonical = DraftControlSpecs();
        Assert.Equal(
            new[] { "copyDraftPrompt", "discardDraft", "openDraft", "startFromDraft" },
            canonical.Keys.OrderBy(k => k, StringComparer.Ordinal).ToArray());

        var rows = layoutDraftRows();
        Assert.Equal(2, rows.Count);

        // The first row carries the four; the second, all but startFromDraft — its
        // instruction block was deleted by hand, so the CLI does not know which flags
        // it was generated with and guessing them would make --build die on drift.
        Assert.Equal(
            new[] { "openDraft", "copyDraftPrompt", "startFromDraft", "discardDraft" },
            rows[0].Controls.Select(c => c.Id.Wire()).ToArray());
        Assert.Equal(
            new[] { "openDraft", "copyDraftPrompt", "discardDraft" },
            rows[1].Controls.Select(c => c.Id.Wire()).ToArray());

        foreach (var control in rows[0].Controls)
        {
            var spec = canonical[control.Id.Wire()];
            Assert.Equal(spec.Label, control.Label);
            Assert.Equal(spec.Emphasis, control.Emphasis.Id());
            Assert.Equal(spec.Confirms, PanelLayoutBuilder.RequiresConfirmation(control.Id));
            // Each control carries ITS row's index: an action on one row cannot
            // touch the others.
            Assert.Equal(0, control.Index);
        }
        Assert.All(rows[1].Controls, c => Assert.Equal(1, c.Index));
    }

    [Fact]
    public void The_progress_is_what_the_cli_reported()
    {
        var rows = layoutDraftRows();
        Assert.Equal("feature/telemetry", rows[0].Name);
        Assert.Equal("3/9", rows[0].Meta);
        Assert.Equal("feature/pagos", rows[1].Name);
        Assert.Equal("0/5", rows[1].Meta);
    }

    [Fact]
    public void No_drafts_means_no_block_at_all()
    {
        var blocks = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewReady()).Blocks;
        Assert.DoesNotContain(blocks, b => b is Block.DraftRows);
        Assert.DoesNotContain(
            blocks,
            b => b is Block.Heading h && h.Text == "Reading orders you started");
    }

    private static IReadOnlyList<DraftRow> layoutDraftRows() =>
        PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewDrafts())
            .Blocks.OfType<Block.DraftRows>().Single().Rows;

    private static Dictionary<string, (string Label, string Emphasis, bool Confirms)> DraftControlSpecs()
    {
        var root = (YamlMappingNode)LoadCanonical().Documents[0].RootNode;
        var map = (YamlMappingNode)root.Children[new YamlScalarNode("draft_controls")];
        var specs = new Dictionary<string, (string, string, bool)>(StringComparer.Ordinal);
        foreach (var pair in map.Children)
        {
            var id = ((YamlScalarNode)pair.Key).Value!;
            var node = (YamlMappingNode)pair.Value;
            specs[id] = (
                ((YamlScalarNode)node.Children[new YamlScalarNode("label")]).Value!,
                ((YamlScalarNode)node.Children[new YamlScalarNode("emphasis")]).Value!,
                ((YamlScalarNode)node.Children[new YamlScalarNode("confirms")]).Value == "true");
        }
        return specs;
    }

    [Fact]
    public void Install_hints_match_canonical_contract()
    {
        Assert.Equal(InstallHint.NpmInstallCmd, CanonicalScalar("npm_install"));
        Assert.Equal(InstallHint.NpmUpdateCmd, CanonicalScalar("npm_update"));
    }

    private static ActionParams? ParamsFor(string action) => action switch
    {
        "startReview" => new ActionParams.Start(
            new ReviewIntent("f", ReviewLayout.Walk, ReviewRange.Full, ReviewSource.Remote), "main"),
        "continueReview" => new ActionParams.Continue("f"),
        "compareReview" => new ActionParams.Compare(Array.Empty<string>(), "a", "b"),
        "cleanReview" or "discardInventory" or "forgetReview" =>
            new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.CleanAll)),
        "setBase" or "setRemote" => new ActionParams.SetConfig("base", "main"),
        _ => null,
    };

    /// <param name="mode">
    /// The fixture's review mode, when the situation declares mode-gated blocks
    /// (<c>when: walk</c> / <c>step</c> / <c>whole</c>). Those branches are mutually
    /// exclusive, so flattening them all into one expected sequence asks a walk panel
    /// for the step row too.
    /// </param>
    private static void AssertLayoutAgainstCanonical(string key, PanelLayout layout, string? mode = null)
    {
        var expected = ExtractControlSpecs(key, mode);
        var actual = layout.CollectControls()
            .Where(c => !TitleOnly.Contains(c.Id))
            .Select(c => (Id: c.Id.Wire(), c.Label, Emphasis: c.Emphasis.Id()))
            .ToList();

        // 1. Nothing the canonical does not declare for this situation. Without this
        //    the matcher below only proves the expected controls are present, in
        //    order — a spurious button anywhere in the panel slid straight past it,
        //    which a mutation (an extra primary "Clean all" row in every review)
        //    confirmed. `when:`-gated blocks may be absent, never extra, so the
        //    containment only runs in this direction.
        var allowed = AllowedIds(key);
        var stray = actual.Where(a => !allowed.Contains(a.Id)).Select(a => a.Id).Distinct().ToList();
        Assert.True(stray.Count == 0,
            $"situation {key}: controls the canonical does not declare: [{string.Join(", ", stray)}]. " +
            $"allowed=[{string.Join(", ", allowed.OrderBy(x => x, StringComparer.Ordinal))}]");

        // 2. And nothing the canonical marks as not_in for this client.
        var forbidden = ForbiddenIds(key);
        var offered = actual.Where(a => forbidden.Contains(a.Id)).Select(a => a.Id).Distinct().ToList();
        Assert.True(offered.Count == 0,
            $"situation {key}: offers [{string.Join(", ", offered)}], which the contract marks " +
            $"not_in: [{ThisClient}] — reponerla es editar el contrato primero");

        // 3. The declared ones, in order, with their label and emphasis.
        var j = 0;
        foreach (var a in actual)
        {
            if (j < expected.Count && a.Id == expected[j].Id)
            {
                if (expected[j].Label is not null)
                    Assert.Equal(expected[j].Label, a.Label);
                if (expected[j].Emphasis is not null)
                    Assert.Equal(expected[j].Emphasis, a.Emphasis);
                j++;
            }
        }
        Assert.True(j == expected.Count,
            $"situation {key}: matched {j}/{expected.Count} expected controls. actual=[{string.Join(", ", actual.Select(x => x.Id))}] expected=[{string.Join(", ", expected.Select(x => x.Id))}]");
    }

    private sealed record Spec(string Id, string? Label, string? Emphasis);

    private static YamlMappingNode SituationNode(string situationKey)
    {
        var yaml = LoadCanonical();
        var root = (YamlMappingNode)yaml.Documents[0].RootNode;
        var panelLayout = (YamlMappingNode)root.Children[new YamlScalarNode("panel_layout")];
        if (!panelLayout.Children.TryGetValue(new YamlScalarNode(situationKey), out var sitNode))
            throw new InvalidOperationException($"panel_layout missing situation {situationKey}");
        return (YamlMappingNode)sitNode;
    }

    private static YamlSequenceNode BlocksOf(YamlMappingNode situation) =>
        (YamlSequenceNode)situation.Children[new YamlScalarNode("blocks")];

    private static List<Spec> ExtractControlSpecs(string situationKey, string? mode = null) =>
        ExtractFromBlocks(BlocksOf(SituationNode(situationKey)), skipNotIn: true, mode: mode);

    /// <summary>
    /// Every id this situation may render: what it declares, plus the inventory
    /// controls when it hosts an <c>inventory_rows</c> block (those are declared once
    /// under the canonical's own <c>inventory_controls:</c> key, not per situation).
    /// </summary>
    private static HashSet<string> AllowedIds(string situationKey)
    {
        var situation = SituationNode(situationKey);
        var blocks = BlocksOf(situation);
        var ids = ExtractFromBlocks(blocks, skipNotIn: false).Select(s => s.Id).ToHashSet(StringComparer.Ordinal);
        if (MentionsBlock(blocks, "inventory_rows"))
        {
            foreach (var id in RowControlIds("inventory_controls")) ids.Add(id);
        }
        // Same shape for the draft block: its four controls are per-row, so they
        // cannot be declared inside panel_layout — their subject is the row, not
        // the situation — and they live in a map of their own, like the
        // inventory's.
        if (MentionsBlock(blocks, "draft_block"))
        {
            foreach (var id in RowControlIds("draft_controls")) ids.Add(id);
        }
        return ids;
    }

    private static HashSet<string> ForbiddenIds(string situationKey)
    {
        var blocks = BlocksOf(SituationNode(situationKey));
        var all = ExtractFromBlocks(blocks, skipNotIn: false).Select(s => s.Id).ToHashSet(StringComparer.Ordinal);
        var kept = ExtractFromBlocks(blocks, skipNotIn: true).Select(s => s.Id).ToHashSet(StringComparer.Ordinal);
        all.ExceptWith(kept);
        return all;
    }

    private static bool MentionsBlock(YamlSequenceNode blocks, string blockType)
    {
        foreach (var b in blocks)
        {
            if (b is not YamlMappingNode map) continue;
            if (Scalar(map, "block") == blockType) return true;
            if (map.Children.TryGetValue(new YamlScalarNode("blocks"), out var nested)
                && nested is YamlSequenceNode ns
                && MentionsBlock(ns, blockType)) return true;
        }
        return false;
    }

    /// <summary>
    /// The ids of a per-row control map (<c>inventory_controls</c>,
    /// <c>draft_controls</c>). Those controls belong to a row, not to a
    /// situation, which is why the canonical keeps them outside
    /// <c>panel_layout</c> and why the matcher has to be told about them.
    /// </summary>
    private static IEnumerable<string> RowControlIds(string key)
    {
        var root = (YamlMappingNode)LoadCanonical().Documents[0].RootNode;
        if (!root.Children.TryGetValue(new YamlScalarNode(key), out var node)
            || node is not YamlMappingNode map)
            return Array.Empty<string>();
        return map.Children.Keys.OfType<YamlScalarNode>().Select(k => k.Value!).ToList();
    }

    private static bool NotInThisClient(YamlMappingNode map)
    {
        if (!map.Children.TryGetValue(new YamlScalarNode("not_in"), out var node)) return false;
        return node is YamlSequenceNode seq
               && seq.OfType<YamlScalarNode>().Any(s => s.Value == ThisClient);
    }

    private static readonly string[] ModeGates = { "walk", "step", "whole" };

    /// <summary>A block gated on a mode other than the fixture's does not render.</summary>
    private static bool GatedOut(YamlMappingNode map, string? mode)
    {
        if (mode is null) return false;
        var when = Scalar(map, "when");
        return when is not null && ModeGates.Contains(when) && when != mode;
    }

    private static List<Spec> ExtractFromBlocks(YamlSequenceNode blocks, bool skipNotIn, string? mode = null)
    {
        var specs = new List<Spec>();
        foreach (var b in blocks)
        {
            if (b is not YamlMappingNode map) continue;
            if (skipNotIn && NotInThisClient(map)) continue;
            if (GatedOut(map, mode)) continue;
            var blockType = Scalar(map, "block");
            if (blockType == "row" || blockType is null && map.Children.ContainsKey(new YamlScalarNode("controls")))
            {
                if (map.Children.TryGetValue(new YamlScalarNode("controls"), out var controlsNode)
                    && controlsNode is YamlSequenceNode controls)
                {
                    foreach (var c in controls)
                    {
                        if (c is YamlMappingNode cm && !(skipNotIn && NotInThisClient(cm)))
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
                        if (c is YamlMappingNode cm && !(skipNotIn && NotInThisClient(cm)))
                            specs.Add(new Spec(Scalar(cm, "id")!, Scalar(cm, "label"), Scalar(cm, "emphasis")));
                    }
                }
            }
            else if (blockType == "tools_section" || map.Children.ContainsKey(new YamlScalarNode("blocks")))
            {
                if (map.Children.TryGetValue(new YamlScalarNode("blocks"), out var nested)
                    && nested is YamlSequenceNode ns)
                    specs.AddRange(ExtractFromBlocks(ns, skipNotIn, mode));
            }
        }
        return specs;
    }

    /// <summary>action id → the clients its <c>not_in:</c> lists (empty when it has none).</summary>
    private static Dictionary<string, IReadOnlyList<string>> CanonicalActions()
    {
        var root = (YamlMappingNode)LoadCanonical().Documents[0].RootNode;
        var actions = (YamlMappingNode)root.Children[new YamlScalarNode("actions")];
        var result = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        foreach (var (k, v) in actions.Children)
        {
            var id = ((YamlScalarNode)k).Value!;
            var notIn = new List<string>();
            if (v is YamlMappingNode m
                && m.Children.TryGetValue(new YamlScalarNode("not_in"), out var n)
                && n is YamlSequenceNode seq)
            {
                notIn.AddRange(seq.OfType<YamlScalarNode>().Select(s => s.Value!));
            }
            result[id] = notIn;
        }
        return result;
    }

    private static string CanonicalScalar(string key)
    {
        var root = (YamlMappingNode)LoadCanonical().Documents[0].RootNode;
        return ((YamlScalarNode)root.Children[new YamlScalarNode(key)]).Value!;
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
