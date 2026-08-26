using GitReview.Domain;
using GitReview.Fixtures;
using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// The "Edits you extracted" section: the branches a finish left behind.
///
/// What these pin down is the rule the section is built on — every row the CLI
/// reported is drawn, including the one that cannot be deleted —, that the
/// per-row control never names more than one branch, and that the bulk
/// "Discard all" control runs clean --fixes-only with NO branch, which by
/// clean's own scoping never reaches a live review session.
/// </summary>
public class PanelLayoutFixesTests
{
    private static Block.ToolsSection? Section(PanelModel model) =>
        PanelLayoutBuilder.PanelLayout(model).Blocks
            .OfType<Block.ToolsSection>()
            .FirstOrDefault(s => s.Title == "Edits you extracted");

    private static IReadOnlyList<GuideRow> Rows(PanelModel model) =>
        Section(model)?.NestedBlocks.OfType<Block.FixesRows>().SelectMany(f => f.Rows).ToList()
            ?? new List<GuideRow>();

    [Fact]
    public void Every_branch_the_cli_reported_gets_a_row_in_its_order()
    {
        Assert.Equal(
            new[]
            {
                "review-fixes/feature/checkout",
                "review-fixes/fix/quoting",
                "review-fixes/perf/index",
                "review-fixes/docs/readme",
            },
            Rows(PanelFixtures.NoReviewFixes()).Select(r => r.Name));
    }

    [Fact]
    public void The_badge_says_each_state_and_none_folds_into_another()
    {
        Assert.Equal(
            new[] { "unmerged", "empty", "merged", "unknown" },
            Rows(PanelFixtures.NoReviewFixes()).Select(r => r.Badge));
    }

    [Fact]
    public void The_branch_you_are_on_is_drawn_and_its_control_is_off()
    {
        // Hiding it would leave a branch that exists with no surface naming it,
        // which is what this section came to fix; offering the button would
        // promise something the CLI skips.
        var current = Rows(PanelFixtures.NoReviewFixes())[1];
        var discard = Assert.Single(current.Controls);
        Assert.Equal(ControlId.DiscardFixes, discard.Id);
        Assert.False(discard.Enabled);
        Assert.Equal("You are on this branch; switch away first", discard.Tooltip);
    }

    [Fact]
    public void Every_other_row_offers_the_discard_naming_the_verb()
    {
        var rows = Rows(PanelFixtures.NoReviewFixes());
        foreach (var row in new[] { rows[0], rows[2], rows[3] })
        {
            var discard = Assert.Single(row.Controls);
            Assert.Equal(ControlId.DiscardFixes, discard.Id);
            Assert.True(discard.Enabled, $"{row.Name} should offer the discard");
            Assert.Equal("git review clean --fixes-only (with confirmation)", discard.Tooltip);
            Assert.Equal(Emphasis.Icon, discard.Emphasis);
        }
    }

    [Fact]
    public void Each_row_control_is_about_exactly_one_branch()
    {
        var controls = Rows(PanelFixtures.NoReviewFixes()).SelectMany(r => r.Controls).ToList();
        Assert.All(controls, c => Assert.Equal(ControlId.DiscardFixes, c.Id));
        Assert.All(controls, c => Assert.NotNull(c.Index));
    }

    [Fact]
    public void Discard_all_sits_above_the_rows_with_no_row_index()
    {
        var discardAll = Section(PanelFixtures.NoReviewFixes())!.NestedBlocks
            .OfType<Block.Row>()
            .SelectMany(r => r.Controls)
            .Single(c => c.Id == ControlId.DiscardAllFixes);
        Assert.Equal("Discard all", discardAll.Label);
        Assert.True(discardAll.Enabled);
        Assert.Null(discardAll.Index);
    }

    [Fact]
    public void Discard_all_runs_clean_fixes_only_with_no_branch()
    {
        // Unlike a bare `clean`, --fixes-only alone only ever enumerates
        // review-fixes branches, so it never reaches a live review session.
        var argv = ActionArgvMap.ActionToArgv(
            "cleanReview",
            new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.CleanFixesOneAll)));
        Assert.Equal("clean", argv.Verb);
        Assert.Equal(new[] { "--fixes-only" }, argv.Args);
    }

    [Fact]
    public void The_bulk_confirmation_says_review_sessions_are_left_alone()
    {
        var copy = HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(HousekeepingKind.CleanFixesOneAll));
        Assert.Contains("git review clean --fixes-only", copy.Detail);
        Assert.Contains("Review sessions", copy.Detail);
        Assert.Equal("Discard All", copy.Button);
    }

    [Fact]
    public void With_no_branches_there_is_no_section()
    {
        Assert.Null(Section(PanelFixtures.NoReviewReady()));
    }

    [Fact]
    public void The_section_sits_after_the_spent_reading_orders_and_before_compare()
    {
        var titles = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewFixes()).Blocks
            .OfType<Block.ToolsSection>()
            .Select(s => s.Title);
        Assert.Equal(
            new[] { "Walkthrough", "Edits you extracted", "Compare", "Settings", "Support" },
            titles);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void The_argv_always_carries_fixes_only_session_or_not(bool session)
    {
        // A value re-read on every refresh cannot decide which branches a command
        // deletes: a late clean <x> would take a live review down.
        var argv = ActionArgvMap.ActionToArgv(
            "cleanReview",
            new ActionParams.Housekeeping(new HousekeepingAction(
                HousekeepingKind.CleanFixesOne, "feature/x", Session: session)));
        Assert.Equal("clean", argv.Verb);
        Assert.Equal(new[] { "--fixes-only", "feature/x" }, argv.Args);
    }

    [Fact]
    public void The_confirmation_says_what_dropping_it_costs()
    {
        var unmerged = HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(
            HousekeepingKind.CleanFixesOne, "feature/x", FixesState: FixesState.Unmerged));
        Assert.Contains("git review clean --fixes-only feature/x", unmerged.Detail);
        Assert.Contains("the base branch does not have", unmerged.Detail);
        Assert.DoesNotContain("left standing", unmerged.Detail);
        Assert.Equal("Discard", unmerged.Button);

        var empty = HousekeepingLogic.ConfirmCopyFor(new HousekeepingAction(
            HousekeepingKind.CleanFixesOne, "feature/x", FixesState: FixesState.Empty, Session: true));
        Assert.Contains("no work of yours is lost", empty.Detail);
        Assert.Contains("review/feature/x is left standing", empty.Detail);
    }

    [Fact]
    public void A_state_we_do_not_understand_reads_as_unknown()
    {
        var parsed = Porcelain.ParseListFixes("fixes\treview-fixes/feature/x\t0\t0\tbrand-new\n");
        Assert.Equal(new[] { FixesState.Unknown }, parsed.Select(f => f.State));
    }
}
