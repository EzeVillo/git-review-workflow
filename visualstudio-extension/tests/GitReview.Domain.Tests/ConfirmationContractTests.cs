using System.Text.RegularExpressions;
using Xunit;
using YamlDotNet.RepresentationModel;

namespace GitReview.Domain.Tests;

/// <summary>
/// FR-032: <c>RequiresConfirmation(id)</c> matches <c>confirms:</c> in the canonical
/// YAML, for every control id — in both directions. A control that should confirm
/// and does not is one click from a deleted branch; one that confirms and should not
/// is a dialog in the middle of navigation.
/// </summary>
public class ConfirmationContractTests
{
    [Fact]
    public void Requires_confirmation_matches_the_canonical_confirms_for_every_control_id()
    {
        var expected = new Dictionary<string, bool>(StringComparer.Ordinal);
        var root = (YamlMappingNode)LoadCanonical().Documents[0].RootNode;

        void Walk(YamlNode? node)
        {
            switch (node)
            {
                case YamlMappingNode map:
                {
                    foreach (var key in new[] { "id", "control" })
                    {
                        if (map.Children.TryGetValue(new YamlScalarNode(key), out var idNode)
                            && idNode is YamlScalarNode { Value: { } id })
                        {
                            var confirms = Bool(map, "confirms");
                            expected[id] = expected.GetValueOrDefault(id) || confirms;
                        }
                    }
                    foreach (var v in map.Children.Values) Walk(v);
                    break;
                }
                case YamlSequenceNode seq:
                    foreach (var v in seq) Walk(v);
                    break;
            }
        }

        Walk(Get(root, "panel_layout"));
        Walk(Get(root, "title_actions"));

        // The two per-row control maps. They cannot be declared inside
        // panel_layout because their subject is the row, not the situation.
        foreach (var key in new[] { "inventory_controls", "draft_controls" })
        {
            if (Get(root, key) is not YamlMappingNode rowControls) continue;
            foreach (var (k, v) in rowControls.Children)
            {
                var id = ((YamlScalarNode)k).Value!;
                var confirms = v is YamlMappingNode m && Bool(m, "confirms");
                expected[id] = expected.GetValueOrDefault(id) || confirms;
            }
        }

        // guide_rows, walkthrough_row and fixes_rows: same role as the two above
        // (controls whose subject is the row), but theirs hang off a "controls" key
        // because the block also declares the rows and their states.
        foreach (var key in new[] { "guide_rows", "walkthrough_row", "fixes_rows" })
        {
            if (Get(root, key) is not YamlMappingNode block) continue;
            if (Get(block, "controls") is not YamlMappingNode rowControls) continue;
            foreach (var (k, v) in rowControls.Children)
            {
                var id = ((YamlScalarNode)k).Value!;
                var confirms = v is YamlMappingNode m && Bool(m, "confirms");
                expected[id] = expected.GetValueOrDefault(id) || confirms;
            }
        }

        // The contract has to have said something about every id, or the comparison
        // below would silently pass on "false" for a control nobody described.
        var described = Enum.GetValues<ControlId>().Count(id => expected.ContainsKey(id.Wire()));
        Assert.True(described >= 20, $"only {described} of the control ids appear in the canonical contract");

        foreach (var id in Enum.GetValues<ControlId>())
        {
            var want = expected.GetValueOrDefault(id.Wire());
            Assert.Equal(want, PanelLayoutBuilder.RequiresConfirmation(id));
        }
    }

    private static YamlNode? Get(YamlMappingNode map, string key) =>
        map.Children.TryGetValue(new YamlScalarNode(key), out var n) ? n : null;

    private static bool Bool(YamlMappingNode map, string key) =>
        map.Children.TryGetValue(new YamlScalarNode(key), out var n)
        && n is YamlScalarNode s
        && bool.TryParse(s.Value, out var b)
        && b;

    private static YamlStream LoadCanonical()
    {
        var file = CanonicalFile();
        Assert.True(File.Exists(file), $"canonical missing at {file}");
        var yaml = new YamlStream();
        yaml.Load(new StringReader(File.ReadAllText(file).Replace("\r\n", "\n")));
        return yaml;
    }

    /// <summary>
    /// THAT THE TABLE GOVERNS, not merely that it agrees.
    ///
    /// The test above compares two declarations with each other, and that is
    /// exactly what is not enough: for a while the canonical said
    /// <c>startFromDraft: {confirms: true}</c>, ConfirmingIds held StartFromDraft,
    /// and the control had long stopped confirming — five suites green, because
    /// RequiresConfirmation was only read in a no-op <c>default:</c>.
    ///
    /// These two asserts close the loop through the source: every declared id has
    /// a caller that passes it through the gate, and there is no other gate.
    /// </summary>
    [Fact]
    public void Every_confirming_id_is_passed_through_the_single_gate()
    {
        var sources = VsSources();
        // walkthroughInit is the declared EXCEPTION: it does not confirm with a
        // yes/no but with a two-course picker ("Update" / "Start over"), which
        // Confirm cannot express — its "no" is a cancel. It stays confirms: true
        // in the canonical because there IS a modal between the click and the
        // mutation, which is what that key means.
        //
        // forgetReview has no ControlId at all: it has no panel control, so the
        // canonical has nowhere to declare it. It shares clean's gate.
        var byPicker = new[] { ControlId.WalkthroughInit };
        // The id REALLY passed, taken from the first argument rather than looked
        // up loose in the file: a Contains goes green with the call site changed,
        // because the control's name shows up in the file for other reasons.
        //
        // Two entries and not one: ConfirmAndRunHousekeepingAsync takes the id and
        // delegates, because one dialog serves several controls. A third delegation
        // reports itself — its id would simply not be in this set.
        var gate = new Regex(
            @"(?:GitReviewDialogs\.Confirm|ConfirmAndRunHousekeepingAsync)\(\s*ControlId\.(\w\w*)",
            RegexOptions.Singleline);
        var passed = sources
            .SelectMany(f => gate.Matches(f.Value).Cast<Match>())
            .Select(m => m.Groups[1].Value)
            .ToHashSet();
        foreach (ControlId id in Enum.GetValues(typeof(ControlId)))
        {
            if (!PanelLayoutBuilder.RequiresConfirmation(id)) continue;
            if (byPicker.Contains(id)) continue;
            Assert.True(
                passed.Contains(id.ToString()),
                $"{id.Wire()} is confirms: true but is never passed to GitReviewDialogs.Confirm");
        }
        foreach (var name in passed)
        {
            var id = (ControlId)Enum.Parse(typeof(ControlId), name);
            Assert.True(
                PanelLayoutBuilder.RequiresConfirmation(id),
                $"GitReviewDialogs.Confirm is called with {id.Wire()}, which the canonical marks confirms: false");
        }
    }

    [Fact]
    public void No_confirmation_dialog_exists_outside_the_gate()
    {
        foreach (var file in VsSources())
        {
            if (Path.GetFileName(file.Key) == "GitReviewDialogs.cs") continue;
            Assert.DoesNotContain("new ConfirmDialog(", file.Value);
        }
    }

    /// <summary>The GitReview.VS sources, the only layer that may open a dialog.</summary>
    private static Dictionary<string, string> VsSources()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        string? root = null;
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "src", "GitReview.VS");
            if (Directory.Exists(candidate)) { root = candidate; break; }
            dir = dir.Parent;
        }
        Assert.NotNull(root);
        var files = Directory.GetFiles(root!, "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                        && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .ToDictionary(f => f, File.ReadAllText);
        Assert.NotEmpty(files);
        return files;
    }

    private static string CanonicalFile()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "contracts", "client-product-surface.yaml");
            if (File.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }
        return Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory, "..", "..", "..", "..", "..", "contracts", "client-product-surface.yaml"));
    }
}
