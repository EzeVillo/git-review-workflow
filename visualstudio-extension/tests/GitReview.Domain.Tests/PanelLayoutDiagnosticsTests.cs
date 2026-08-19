using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

public class PanelLayoutDiagnosticsTests
{
    [Fact]
    public void Cli_missing_has_the_install_command_and_the_other_options_link()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.CliMissing());
        var code = layout.Blocks.OfType<Block.CodeCommand>().Single();
        Assert.Equal(InstallHint.NpmInstallCmd, code.Command);
        Assert.Equal(ControlId.CopyCliInstall, code.Copy.Id);
        Assert.Equal("Copy", code.Copy.Label);
        Assert.Equal("Copy install command", code.Copy.AccessibleName);

        var link = layout.CollectControls().First(c => c.Id == ControlId.InstallCli);
        Assert.Equal("Other install options", link.Label);
        Assert.Equal(Emphasis.Link, link.Emphasis);
    }

    /// <summary>
    /// Missing and outdated differ in one word and one command; offering
    /// <c>install</c> to someone who already has an old copy is the wrong advice.
    /// </summary>
    [Fact]
    public void Cli_outdated_uses_the_update_command()
    {
        var layout = PanelLayoutBuilder.PanelLayout(PanelFixtures.CliOutdated());
        Assert.Equal(InstallHint.NpmUpdateCmd, layout.Blocks.OfType<Block.CodeCommand>().Single().Command);
        var hints = layout.Blocks.OfType<Block.Paragraph>().Select(p => p.Text).ToList();
        Assert.Contains("Update with npm (recommended):", hints);
        Assert.DoesNotContain("Install with npm (recommended):", hints);
        Assert.NotEqual(InstallHint.NpmInstallCmd, InstallHint.NpmUpdateCmd);
    }

    [Fact]
    public void Npm_command_for_picks_the_matching_hint()
    {
        Assert.Equal(InstallHint.NpmInstallCmd, InstallHint.NpmCommandFor(InstallHint.CliInstallKind.Install));
        Assert.Equal(InstallHint.NpmUpdateCmd, InstallHint.NpmCommandFor(InstallHint.CliInstallKind.Update));
    }

    [Fact]
    public void Out_of_range_and_error_both_offer_how_to_fix_it_as_the_primary()
    {
        foreach (var model in new[] { PanelFixtures.OutOfRange(), PanelFixtures.Error() })
        {
            var layout = PanelLayoutBuilder.PanelLayout(model);
            var help = layout.CollectControls().First(c => c.Id == ControlId.OutOfRangeHelp);
            Assert.Equal("How to fix it", help.Label);
            Assert.Equal(Emphasis.Primary, help.Emphasis);
            Assert.Contains(layout.Blocks, b => b is Block.Stderr);
        }
    }

    /// <summary>
    /// The two diagnostics are told apart by their first line: one is a cursor the
    /// reviewer can move back, the other is a state nobody could read.
    /// </summary>
    [Fact]
    public void The_two_diagnostics_say_different_things()
    {
        Assert.Equal(
            "The cursor is out of range: the base moved.",
            PanelLayoutBuilder.PanelLayout(PanelFixtures.OutOfRange()).Blocks.OfType<Block.Paragraph>().First().Text);
        Assert.Equal(
            "Something went wrong reading the review state.",
            PanelLayoutBuilder.PanelLayout(PanelFixtures.Error()).Blocks.OfType<Block.Paragraph>().First().Text);
    }

    /// <summary>
    /// What the CLI said is the actionable half of these screens, so it is shown —
    /// but a blank stderr must not draw an empty box.
    /// </summary>
    [Fact]
    public void Stderr_is_shown_when_there_is_one_and_omitted_when_there_is_not()
    {
        foreach (var situation in new[] { Situation.OutOfRange, Situation.Error, Situation.CliMissing })
        {
            var withText = PanelModelBuilder.BuildPanelModel(
                new ReviewState(situation, Stderr: "fatal: something"), new PanelInputs(false));
            Assert.Contains(PanelLayoutBuilder.PanelLayout(withText).Blocks, b => b is Block.Stderr s && s.Text == "fatal: something");

            foreach (var blank in new[] { null, "", "   \n" })
            {
                var model = PanelModelBuilder.BuildPanelModel(
                    new ReviewState(situation, Stderr: blank), new PanelInputs(false));
                Assert.DoesNotContain(PanelLayoutBuilder.PanelLayout(model).Blocks, b => b is Block.Stderr);
            }
        }
    }

    [Fact]
    public void The_multi_root_error_names_the_one_root_rule()
    {
        var text = PanelLayoutBuilder.PanelLayout(PanelFixtures.Error())
            .Blocks.OfType<Block.Stderr>().First().Text;
        Assert.Contains("multi-root is not supported", text);
    }

    /// <summary>These screens have no review to act on, so the title bar is refresh only.</summary>
    [Fact]
    public void Diagnostic_screens_keep_only_refresh_in_the_title_bar()
    {
        foreach (var model in new[]
                 {
                     PanelFixtures.OutOfRange(), PanelFixtures.Error(),
                     PanelFixtures.CliMissing(), PanelFixtures.CliOutdated(),
                 })
        {
            Assert.Equal(
                new[] { ControlId.Refresh },
                PanelLayoutBuilder.PanelLayout(model).TitleActions.Select(t => t.Id));
        }
    }
}
