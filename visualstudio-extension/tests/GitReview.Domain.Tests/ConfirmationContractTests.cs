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
