using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// Locks the English copy that has to stay byte-aligned with the VS Code extension
/// and the JetBrains plugin. Port of the jetbrains UserCopyTest.
/// </summary>
public class UserCopyTests
{
    [Fact]
    public void Abort_confirm_matches_the_other_clients()
    {
        Assert.Equal("Cancel the review of feature/x?", UserCopy.AbortTitle("feature/x"));
        Assert.Equal(
            "This returns to the branch you started the review from; your uncommitted edits will be discarded.",
            UserCopy.AbortDetail);
        Assert.Equal("Cancel Review", UserCopy.AbortButton);
    }

    [Fact]
    public void Save_confirm_matches_the_other_clients()
    {
        Assert.Equal("Save the review of feature/x for later?", UserCopy.SaveTitle("feature/x"));
        Assert.Equal("Save for Later", UserCopy.SaveButton);
        Assert.Contains("your edits are kept and you can resume later", UserCopy.SaveDetail);
    }

    [Fact]
    public void Continue_confirm_matches_the_other_clients()
    {
        Assert.Equal("Continue the saved review of feature/x?", UserCopy.ContinueTitle("feature/x"));
        Assert.Equal(
            "This switches to review/feature/x and restores your edits in the working tree.",
            UserCopy.ContinueDetail("feature/x"));
        Assert.Equal("Continue", UserCopy.ContinueButton);
    }

    [Fact]
    public void Finish_success_toasts_match_the_other_clients()
    {
        Assert.Equal(
            "review-fixes/feature/x is ready. Undo is available if you need it.",
            UserCopy.FinishSuccess("review-fixes/feature/x", FinishOutcome.Pending));
        Assert.Equal(
            "feature/x is ready.",
            UserCopy.FinishSuccess("feature/x", FinishOutcome.NoEdits));
    }

    /// <summary>
    /// Where the edits went, in one place: --onto-source stages them on the branch
    /// itself, everything else on review-fixes/.
    /// </summary>
    [Fact]
    public void Finish_destination_follows_onto_source()
    {
        Assert.Equal("review-fixes/a", UserCopy.FinishDestination(false, "a"));
        Assert.Equal("a", UserCopy.FinishDestination(true, "a"));
    }

    [Fact]
    public void Undo_force_gate_copy_matches_the_other_clients()
    {
        Assert.Equal("Undo this finish?", UserCopy.UndoTitle);
        Assert.Equal("Discard Work and Undo", UserCopy.UndoForceButton);
        Assert.Contains("cannot be undone", UserCopy.UndoForceDetail);
        Assert.Contains("permanently discards", UserCopy.UndoForceDetail);
        // The two undo details are not interchangeable: one restores, one discards.
        Assert.NotEqual(UserCopy.UndoDetailPending, UserCopy.UndoDetailConflict);
    }

    [Fact]
    public void Start_confirm_uses_the_layout_summary_and_shows_the_command()
    {
        Assert.Equal(
            "Start reviewing feature/x, as a walkthrough?",
            UserCopy.StartConfirmTitle("feature/x", ReviewLayout.Walk));
        Assert.Equal(
            "Start reviewing feature/x, commit by commit?",
            UserCopy.StartConfirmTitle("feature/x", ReviewLayout.Step));
        Assert.Equal(
            "git review start --step -- feature/x\nComparing against main.",
            UserCopy.StartConfirmDetail(new[] { "--step", "--", "feature/x" }, "main"));
        // With no base to name, the second line is omitted rather than left blank.
        Assert.Equal(
            "git review start -- feature/x",
            UserCopy.StartConfirmDetail(new[] { "--", "feature/x" }, null));
        Assert.Equal("Start the review", UserCopy.StartConfirmButton);
    }

    /// <summary>
    /// Every stale message names the action that did not happen, so the reviewer
    /// knows what to retry. A generic one would leave them guessing.
    /// </summary>
    [Fact]
    public void Stale_messages_name_the_action_that_did_not_run()
    {
        Assert.Equal(
            "The review state changed before the cancellation ran; nothing was cancelled.",
            UserCopy.StaleMessage("abortReview"));
        Assert.Equal(
            "The review state changed before the force-undo ran; nothing was undone.",
            UserCopy.StaleMessage("undoFinish", force: true));
        Assert.Equal(
            "The review state changed before the undo ran; nothing was undone.",
            UserCopy.StaleMessage("undoFinish"));
        Assert.Equal(
            "The review state changed before the save ran; nothing was saved.",
            UserCopy.StaleMessage("saveReview"));
        Assert.Equal(
            "The review state changed before the finish ran; nothing was finished.",
            UserCopy.StaleMessage("finishReview"));
        Assert.Equal(UserCopy.HousekeepingStale, UserCopy.StaleMessage("somethingElse"));

        // Every one of them says nothing happened — that is the point of the message.
        foreach (var action in new[] { "abortReview", "saveReview", "continueReview", "finishReview", "undoFinish", "startReview", "cleanReview" })
            Assert.Contains("nothing was", UserCopy.StaleMessage(action));
    }

    [Fact]
    public void Failure_fallbacks_name_the_command_that_failed()
    {
        Assert.Equal("git review abort failed.", UserCopy.FailureFallback("abortReview"));
        Assert.Equal(
            "git review finish --abort --force failed.",
            UserCopy.FailureFallback("undoFinish", new ActionParams.UndoFinish(true)));
        Assert.Equal(
            "git review finish --abort failed.",
            UserCopy.FailureFallback("undoFinish", new ActionParams.UndoFinish(false)));
        Assert.Equal(
            "git review walkthrough init --force failed.",
            UserCopy.FailureFallback("walkthroughInit", new ActionParams.WalkthroughInit(true)));
        Assert.Equal("git review next failed.", UserCopy.FailureFallback("next"));
        Assert.Equal("git review config failed.", UserCopy.FailureFallback("setBase"));
    }

    /// <summary>The housekeeping fallback names the verb that actually ran.</summary>
    [Fact]
    public void The_housekeeping_fallback_follows_the_verb()
    {
        Assert.Equal(
            "git review clean failed.",
            UserCopy.FailureFallback("cleanReview",
                new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.CleanAll))));
        Assert.Equal(
            "git review forget failed.",
            UserCopy.FailureFallback("forgetReview",
                new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.ForgetSavedAll))));
    }

    /// <summary>Every product action has a message; none of them falls through to a blank.</summary>
    [Fact]
    public void Every_action_has_a_failure_message()
    {
        foreach (var action in ActionArgvMap.ProductActions)
        {
            var message = UserCopy.FailureFallback(action);
            Assert.False(string.IsNullOrWhiteSpace(message), $"{action} has no failure message");
            Assert.EndsWith("failed.", message);
        }
    }

    [Fact]
    public void The_busy_message_is_the_locks_own()
    {
        Assert.Equal("Another operation is already in progress", UserCopy.DiscardBusy);
        Assert.Equal(MutationLock.DiscardReason, UserCopy.DiscardBusy);
    }

    [Fact]
    public void Picker_empty_state_messages_match_the_other_clients()
    {
        Assert.Equal("No branches to pick a base from were found.", UserCopy.NoBranchesForBase);
        Assert.Equal("No remotes to pick from were found.", UserCopy.NoRemotes);
        Assert.Equal("No active review to preview.", UserCopy.NoActivePreview);
        Assert.Equal(
            "This is a read-only compare review; there is nothing to finish. Use Cancel when done.",
            UserCopy.ReadonlyFinish);
        Assert.Equal("Need a single git repository root.", UserCopy.NoSoleRoot);
    }

    // --- draft wait notice (011) ----------------------------------------------

    [Fact]
    public void Wait_message_asks_to_fill_the_draft_when_it_is_on_screen()
    {
        Assert.Equal(
            "Fill in the reading order for feature/x, then continue.",
            UserCopy.DraftWaitMessage("feature/x", null, null));
        Assert.Equal(
            "The draft is not valid yet: no entries found",
            UserCopy.DraftWaitMessage("feature/x", "no entries found", null));
    }

    /// <summary>
    /// The real case: the open project is a subfolder of the repo, cwd/.git does not
    /// exist, the draft was written anyway and its path only goes out on the CLI's
    /// stdout, which no client shows.
    /// </summary>
    [Fact]
    public void Wait_message_says_where_the_draft_is_when_it_could_not_be_opened()
    {
        Assert.Equal(
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
            " — the draft is at /repo/.git/review-walkthrough/feature/x.md.",
            UserCopy.DraftWaitMessage("feature/x", null, new UnopenedDraft("/repo/.git/review-walkthrough/feature/x.md")));
        Assert.Equal(
            "The draft is not valid yet: no entries found It could not be opened here" +
            " — the draft is at /repo/.git/review-walkthrough/feature/x.md.",
            UserCopy.DraftWaitMessage("feature/x", "no entries found", new UnopenedDraft("/repo/.git/review-walkthrough/feature/x.md")));
    }

    [Fact]
    public void Wait_message_names_the_relative_file_when_the_path_could_not_be_built()
    {
        Assert.Equal(
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
            " — look for review-walkthrough/feature/x.md inside this repository's git directory.",
            UserCopy.DraftWaitMessage("feature/x", null, new UnopenedDraft(null)));
    }

    [Fact]
    public void Draft_progress_says_which_half_of_the_loop_is_running()
    {
        Assert.Equal("Drafting a walkthrough for feature/x…", UserCopy.DraftProgress("feature/x", false));
        Assert.Equal("Validating your draft for feature/x…", UserCopy.DraftProgress("feature/x", true));
        Assert.NotEqual(UserCopy.DraftFailed, UserCopy.DraftBuildFailed);
    }

    [Fact]
    public void Compare_confirm_says_it_creates_a_read_only_review()
    {
        var title = UserCopy.CompareConfirmTitle("a", "b", ReviewLayout.Step);
        Assert.Equal(
            "Compare a..b commit by commit? This creates a read-only review (finish will refuse).",
            title);
        Assert.Equal("Comparing a..b…", UserCopy.ComparingProgress("a", "b"));
    }
}
