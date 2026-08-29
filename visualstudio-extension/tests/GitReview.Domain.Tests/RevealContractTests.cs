using System.Text.RegularExpressions;
using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// <c>RevealsPanel(id)</c> matches <c>reveals:</c> in the canonical, AND governs.
///
/// The three checks are the ones that guard <c>confirms:</c>, and they are here
/// because of the lesson that table left: for a while it was declared in three
/// places and governed in none, because nobody consulted it to decide. A new
/// table is born with its gate or it is born decorative.
/// </summary>
public class RevealContractTests
{
    [Fact]
    public void Reveals_panel_matches_the_canonical_list()
    {
        var expected = CanonicalReveals();
        Assert.NotEmpty(expected);
        foreach (ControlId id in Enum.GetValues(typeof(ControlId)))
        {
            var want = expected.Contains(id.Wire());
            Assert.True(
                want == PanelLayoutBuilder.RevealsPanel(id),
                $"reveals mismatch for {id.Wire()}: canonical says {want}");
        }
    }

    [Fact]
    public void Every_revealing_id_is_passed_through_the_single_gate()
    {
        // The id REALLY passed, taken from the argument rather than looked up
        // loose in the file: a Contains goes green with the call site changed.
        var gate = new Regex(@"PanelReveal\.Reveal\(\s*ControlId\.(\w\w*)", RegexOptions.Singleline);
        var passed = VsSources()
            .SelectMany(f => gate.Matches(f.Value).Cast<Match>())
            .Select(m => m.Groups[1].Value)
            .ToHashSet();
        foreach (ControlId id in Enum.GetValues(typeof(ControlId)))
        {
            if (!PanelLayoutBuilder.RevealsPanel(id)) continue;
            Assert.True(
                passed.Contains(id.ToString()),
                $"{id.Wire()} is in reveals: but is never passed to PanelReveal.Reveal");
        }
        foreach (var name in passed)
        {
            var id = (ControlId)Enum.Parse(typeof(ControlId), name);
            Assert.True(
                PanelLayoutBuilder.RevealsPanel(id),
                $"PanelReveal.Reveal is called with {id.Wire()}, which the canonical does not list under reveals:");
        }
    }

    [Fact]
    public void No_other_surface_brings_the_panel_forward()
    {
        // The vehicle is PanelHost.RevealPanel, invoked only by PanelReveal.
        // GitReviewToolWindow provides it and VsHostActions wires it; anyone else
        // calling it would step around the table.
        foreach (var file in VsSources())
        {
            var name = Path.GetFileName(file.Key);
            if (name is "PanelReveal.cs" or "PanelHost.cs" or "GitReviewToolWindow.cs" or "VsHostActions.cs")
            {
                continue;
            }
            Assert.DoesNotContain("RevealPanel", file.Value);
            Assert.DoesNotContain("ShowNoActivate", file.Value);
        }
    }

    /// <summary>The ids under <c>reveals:</c>, read as a list of scalars.</summary>
    private static HashSet<string> CanonicalReveals()
    {
        var file = CanonicalFile();
        Assert.True(File.Exists(file), $"canonical missing at {file}");
        var text = File.ReadAllText(file).Replace("\r\n", "\n");
        var block = text.Split("\nreveals:\n");
        Assert.True(block.Length > 1, "canonical: reveals: is missing");
        var body = block[1].Split("\n#")[0];
        return new Regex(@"^\s*-\s+([A-Za-z][A-Za-z0-9]*)\s*$", RegexOptions.Multiline)
            .Matches(body)
            .Cast<Match>()
            .Select(m => m.Groups[1].Value)
            .ToHashSet();
    }

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
