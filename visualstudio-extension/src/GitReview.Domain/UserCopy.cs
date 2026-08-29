namespace GitReview.Domain;

public sealed record UnopenedDraft(string? File);

/// <summary>
/// User-facing copy shared with the VS Code extension and JetBrains plugin.
/// Keep strings byte-for-byte aligned.
/// </summary>
public static class UserCopy
{
    public const string ProductTitle = "git review";
    public const string DiscardBusy = MutationLock.DiscardReason;

    /// <summary>
    /// Lo que se dice cuando el testigo de estado (StaleGuard) rechaza una
    /// mutacion porque el repositorio cambio entre la confirmacion y la
    /// invocacion. <b>Uno solo para los ocho comandos</b>, y antes eran diez.
    /// <para>
    /// Las diez variantes decian la misma cosa con el verbo cambiado -- "nothing
    /// was finished", "nothing was saved", "nothing was undone" --, y ese verbo
    /// no es informacion: es el boton que el revisor acaba de apretar, que
    /// todavia tiene bajo el cursor. Lo unico que no puede deducir es POR QUE no
    /// paso nada, y eso es identico en los diez casos.
    /// </para>
    /// <para>
    /// No lleva "try again": el panel ya se refresco solo, asi que el estado que
    /// se ve al leer el mensaje es el nuevo.
    /// </para>
    /// </summary>
    public const string Stale = "The repository changed while you were deciding, so nothing happened.";

    public const string NoBranchesForBase = "No branches to pick a base from were found.";
    public const string NoBranchesForReview = "No branches to pick a review from were found.";
    public const string NoRemotes = "No remotes to pick from were found.";
    public const string NoSavedReviews = "No saved reviews.";
    // Los pickers de housekeeping están cerrados sobre lo que la CLI reportó, así que
    // con la lista vacía no hay nada que elegir. El de --delta nombra la salida que sí
    // alcanza a los marcadores huérfanos — el caso por el que ahí había texto libre.
    public const string NoReviewsToClean = "No reviews to clean were found.";
    public const string NoReviewsToDiscard = "No reviews to discard were found.";
    public const string NoDeltaSources =
        "No reviews were found to name a delta marker. "
        + "Use \"Forget stale delta markers\" for markers whose branch is gone.";
    public const string NotResumable = "That review is not resumable.";
    public const string NoActivePreview = "No active review to preview.";
    public const string NoSoleRoot = "Need a single git repository root.";
    public const string CouldNotReadConfig = "Could not read the review configuration.";
    public const string CouldNotParseConfig = "Could not parse the review configuration.";
    public const string CouldNotReadOffers = "Could not read reading options for this branch.";
    public const string ConfigureBaseFirst =
        "Configure a base branch first (git review → Set the Base Branch).";
    public const string ReadonlyFinish =
        "This is a read-only compare review; there is nothing to finish. Use Cancel when done.";
    public const string OutOfRangeFallback =
        "Run 'git review status' in a terminal for the diagnosis and recovery command.";

    // --- Panel draft block (012) ------------------------------------------------

    public const string DiscardDraftButton = "Discard";

    public static string DiscardDraftTitle(string branch) =>
        $"Discard the reading order you wrote for {branch}?";

    public static string DiscardDraftDetail(string branch, string path) =>
        $"This deletes {path}. It cannot be undone.";

    public static string DiscardDraftProgress(string branch) =>
        $"Discarding the reading order for {branch}…";

    // --- Panel authoring-guide block --------------------------------------------

    public const string DiscardGuideButton = "Discard";

    public const string DiscardGuideTitle = "Discard the authoring guide you wrote?";

    public static string DiscardGuideDetail(string path) =>
        $"This deletes {path}. It cannot be undone.";

    public const string DiscardGuideProgress = "Discarding your authoring guide…";

    public const string CreateGuideProgress = "Creating the authoring guide…";


    /// <summary>
    /// What "Copy for agent" puts on the clipboard for one draft row.
    ///
    /// A pointer, not a prompt: the brief lives inside the file, in the
    /// instruction block at the top, and repeating it here would give an agent
    /// two sources for the same rules. <paramref name="path"/> is the absolute
    /// path the CLI reported for that row — never one this client built.
    ///
    /// Byte for byte identical to userCopy.ts and UserCopy.kt.
    /// </summary>
    public static string DraftAgentPrompt(string path) =>
        $"Fill in the reading order at {path}. The instructions are inside the file, "
        + "in the comment at the top. Do not change the file list or the numbering rules.";

    /// <summary>
    /// What "Copy for agent" puts on the clipboard for the author's own
    /// walkthrough.
    ///
    /// A pointer, like the draft one, and for the same reason. Two sentences
    /// differ, and both are about the situation rather than the format: the file
    /// usually already holds finished prose (a walkthrough is written when the PR
    /// is done, and then the PR keeps moving), so the one damaging thing an agent
    /// can do here is rewrite it whole. Saying "fill in the reading order" over a
    /// full file is an instruction to start over, and it would undo exactly what
    /// updating in place exists to preserve.
    ///
    /// Byte for byte identical to userCopy.ts and UserCopy.kt.
    /// </summary>
    public static string WalkthroughAgentPrompt(string path) =>
        $"Update the reading order at {path}. The instructions are inside the file, "
        + "in the comment at the top. Entries that already have a number and a why are "
        + "finished: leave them as they are, and fill in only the ones marked \"## ?.\".";

    public const string SetBaseTitle = "Set the base branch";
    public const string SetBasePrompt =
        "Where PRs land (main, develop, …) — full reviews compare against it";
    public const string SetRemoteTitle = "Set the remote";
    public const string SetRemotePrompt = "Remote a full review fetches from";

    public const string StartBranchTitle = "Start a review — branch";
    public const string StartBranchPlaceholder = "Branch to review";
    public const string StartOriginTitle = "Start a review — origin";
    public const string StartOriginPlaceholder = "Remote, local, or offline";
    public const string StartRangeTitle = "Start a review — range";
    public const string StartRangePlaceholder = "Full range, or only what is new since the last review";
    /// <summary>
    /// El ULTIMO paso del asistente, y por eso lleva la rama: elegir una forma
    /// de lectura aca ya arranca la review. La frase es la que decia la pantalla
    /// de confirmacion que este paso reemplaza.
    /// </summary>
    public static string StartLayoutTitle(string branch) =>
        $"Start reviewing {branch} — how do you want to read it?";

    /// <summary>
    /// The only thing a draft update says that no row answers: what was kept,
    /// what came in and what fell out. The row shows the NEW annotated/total
    /// pair, never what moved to get there.
    ///
    /// Written here rather than forwarding the CLI's stdout, which says the same
    /// with an absolute path and the next command — and that command is the
    /// "Validate and start" button on that very row. The three numbers arrive in
    /// the `merged` record of <c>walkthrough draft --porcelain</c>.
    ///
    /// Zeroes are not spelled out. An update that adds and drops nothing is a
    /// real outcome — the range moved without changing which files it touches —
    /// and earns its sentence, but making somebody read "0 added, 0 dropped" to
    /// find out neither happened is the noise this sentence exists to avoid.
    ///
    /// Byte for byte identical to userCopy.ts and UserCopy.kt.
    /// </summary>
    public static string DraftUpdated(int kept, int added, int dropped)
    {
        if (added == 0 && dropped == 0)
        {
            return $"Reading order updated: nothing moved, {kept} kept.";
        }
        var text = $"Reading order updated: {kept} kept";
        if (added > 0) text += $", {added} added";
        if (dropped > 0) text += $", {dropped} no longer in the PR";
        return text + ".";
    }

    public const string StartLayoutPlaceholder =
        "Walkthrough, commit by commit, keys only, or whole diff";

    public const string DraftFailed = "Could not draft a reading order.";
    public const string DraftBuildFailed = "Could not check your reading order.";
    public const string DraftWaitTitle = "Draft your reading order";
    public const string DraftContinueButton = "Continue";
    public const string DraftKeysPlaceholder =
        "Your draft marks key entries: read all of them, or only those";

    public static string DraftProgress(string branch, bool build) =>
        build ? $"Validating your draft for {branch}…" : $"Drafting a walkthrough for {branch}…";

    public static string DraftWaitMessage(string branch) =>
        $"Fill in the reading order for {branch}, then continue.";

    public static string DraftInvalidMessage(string error) =>
        $"The draft is not valid yet: {error}";

    public static string DraftWaitMessage(string branch, string? error, UnopenedDraft? unopened)
    {
        var head = error is not null ? DraftInvalidMessage(error) : DraftWaitMessage(branch);
        if (unopened is null) return head;
        return unopened.File is not null
            ? $"{head} It could not be opened here — the draft is at {unopened.File}."
            : $"{head} It could not be opened here — look for review-walkthrough/{branch}.md " +
              "inside this repository's git directory.";
    }

    public static readonly IReadOnlyList<(bool KeysOnly, string Label)> DraftKeysLabels = new[]
    {
        (false, "Walkthrough — the whole reading order you wrote"),
        (true, "Walkthrough — keys only — only the entries you marked key"),
    };

    public static readonly IReadOnlyList<(ReviewSource Source, string Label)> SourceLabels = new[]
    {
        (ReviewSource.Remote, "Remote — fetch and review the remote tip of the branch"),
        (ReviewSource.Local,
            "Local — review the local branch without fetching; base may still use the remote"),
        (ReviewSource.Offline,
            "Offline — review the local branch with no network; base is resolved locally"),
    };

    public static readonly IReadOnlyList<(ReviewRange Range, string Label)> RangeLabels = new[]
    {
        (ReviewRange.Full, "Full range — everything since the base branch"),
        (ReviewRange.Delta,
            "Only what is new — commits since your last review of this branch"),
    };

    public static string StartingProgress(string branch) => $"Starting the review of {branch}…";

    public const string StartFailed = "Could not start the review.";

    public static string ContinueTitle(string source) => $"Continue the saved review of {source}?";
    public static string ContinueDetail(string source) =>
        $"This switches to review/{source} and restores your edits in the working tree.";
    public const string ContinueButton = "Continue";
    public static string ContinuingProgress(string source) => $"Continuing the review of {source}…";
    public const string ContinueFailed = "Could not resume the review.";

    public static string AbortTitle(string source) => $"Cancel the review of {source}?";
    public const string AbortDetail =
        "This returns to the branch you started the review from; your uncommitted edits will be discarded.";
    public const string AbortButton = "Cancel Review";
    public static string AbortingProgress(string source) => $"Cancelling the review of {source}…";
    public const string AbortFailed = "Could not cancel the review.";

    public static string SaveTitle(string source) => $"Save the review of {source} for later?";
    public const string SaveDetail =
        "This pauses the review and returns to the branch you started from; your edits are kept and you can resume later.";
    public const string SaveButton = "Save for Later";
    public static string SavingProgress(string source) => $"Saving the review of {source} for later…";
    public const string SaveFailed = "Could not pause the review.";

    public static string FinishLocationTitle(string source) =>
        $"Finish the review of {source} — where do your edits go?";
    public const string FinishLocationPlaceholder =
        "A separate branch, or onto the PR branch itself";
    public const string FinishLocationSeparate =
        "A separate branch — review-fixes/<branch>, staged on top of the PR tip";
    public const string FinishLocationOnto =
        "Onto the PR branch itself — stage the edits directly on the PR branch";

    public static string FinishingProgress(string source) => $"Finishing the review of {source}…";
    public const string FinishFailed = "Could not finish the review.";

    /// <summary>
    /// El acuse de un finish en verde, o <c>null</c> cuando el panel ya lo dio.
    /// <para>
    /// Pending es el caso normal y devuelve null: el panel entra en
    /// finish-pending y su banner dice lo mismo con mas contexto -- el destino,
    /// que hay que commitear desde Source Control, y los dos botones --. El
    /// toast era esa frase otra vez, un segundo antes.
    /// </para>
    /// <para>
    /// NoEdits es el residual: sin registro pending no hay banner, asi que sin
    /// esta linea un finish exitoso no dejaria ninguna senal.
    /// </para>
    /// </summary>
    public static string? FinishSuccess(string destination, FinishOutcome outcome) => outcome switch
    {
        FinishOutcome.Pending => null,
        _ => $"{destination} is ready.",
    };

    public static string FinishDestination(bool ontoSource, string source) =>
        ontoSource ? source : $"review-fixes/{source}";

    public const string UndoTitle = "Undo this finish?";
    public const string UndoDetailPending =
        "This returns you to the review branch with your edits restored.";
    public const string UndoDetailConflict =
        "This discards any in-progress resolution and returns you to editing the review.";
    public const string UndoButton = "Undo Finish";
    public const string UndoingProgress = "Undoing the finish…";
    public const string UndoAbortFailed = "Could not undo the finish.";
    public const string UndoForceDetail =
        "This permanently discards the work made since the finish. It cannot be undone.";
    public const string UndoForceButton = "Discard Work and Undo";
    public const string ForceUndoingProgress = "Force-undoing the finish…";
    public const string ForceUndoFailed = "Could not undo the finish, even discarding the newer work.";

    public const string ResumeProgress = "Resuming the finish…";
    public const string ResumeFailed = "Could not continue the finish.";

    public const string CompareLowerTitle = "Compare: lower bound (from)";
    public const string CompareUpperTitle = "Compare: upper bound (to)";
    public const string CompareLayoutTitle = "How to read the comparison";
    public const string CompareLayoutPlaceholder =
        "Walkthrough, keys only, commit by commit, or whole diff";
    public const string CompareConfirmDetail =
        "Your working tree must be clean to start it.";
    public const string CompareButton = "Compare";
    public const string CompareFailed = "Could not compare those two revisions.";

    public static string CompareConfirmTitle(string lower, string upper, ReviewLayout layout) =>
        $"Compare {lower}..{upper} {LayoutOffers.LayoutSummary(layout)}? This creates a read-only review (finish will refuse).";

    public static string ComparingProgress(string lower, string upper) =>
        $"Comparing {lower}..{upper}…";

    /// <summary>
    /// The choice between reconciling a walkthrough and starting it over, asked
    /// BEFORE the verb runs.
    ///
    /// It used to hang off the CLI FAILING: init ran, and when it died because the
    /// file was already there, that is where the three clients offered to overwrite.
    /// Since init updates instead of refusing, that path stopped existing — and with
    /// it the only way to reach --force from a panel.
    ///
    /// Byte for byte identical to userCopy.ts and UserCopy.kt.
    /// </summary>
    public const string WalkthroughExistsTitle = "This branch already has a walkthrough.";
    public const string WalkthroughExistsDetail =
        "Update keeps everything you already wrote for files that are still in the PR, and adds the ones that are new.\n\n"
        + "Start over replaces it with a blank list. The file is committed to the PR, so git checkout -- .review/walkthrough.md brings the old one back.";
    /// <summary>
    /// On the REVIEWER's side there is no equivalent pair, and the asymmetry is
    /// deliberate.
    ///
    /// There was one: a modal that, over any draft whose review had closed, asked
    /// whether to reconcile or start from scratch. It asked because the wizard could
    /// not know which of the two was needed — the draft record's state says whether
    /// the order has been read, not whether it still covers the range — so it handed
    /// the doubt to the reviewer. The CLI answers it now, holding both tips, by
    /// offering draft-update only when there IS something to reconcile; with no
    /// question, there is no modal.
    ///
    /// And starting over is not restored here: on the author's side the file is
    /// tracked and git checkout -- brings it back, on the reviewer's side it lives
    /// outside git and there is no way back. A button for that does not belong in a
    /// step people walk straight past; it belongs in Discard, which confirms.
    /// </summary>
    public const string WalkthroughUpdateButton = "Update";
    public const string WalkthroughStartOverButton = "Start over";

    public const string WalkthroughInitProgress = "Initializing walkthrough…";
    public const string WalkthroughOverwriteProgress = "Overwriting walkthrough…";
    public const string WalkthroughInitFailed = "Could not create the walkthrough.";
    public const string WalkthroughForceFailed = "Could not replace the walkthrough.";

    public const string WalkthroughBuildTitle = "Check and renumber the walkthrough?";
    public const string WalkthroughBuildDetail =
        "This puts the files in the order you wrote and numbers them 1 to N. If something is missing, nothing changes and you will see what to fix.";
    public const string WalkthroughBuildButton = "Build";
    public const string WalkthroughBuildProgress = "Building walkthrough…";
    public const string WalkthroughBuildFailed = "Could not build the walkthrough.";

    public const string PreviewFailed = "Could not preview your edits.";
    public const string PreviewEmpty = "(no edits to preview)";

    public const string CleanPickTitle = "Clean review leftovers";
    public const string CleanOneLabel = "Clean leftovers for one branch…";
    public const string CleanAllLabel = "Clean all leftover review branches";
    public const string CleanBranchTitle = "Branch to clean";
    public const string ForgetPickTitle = "Forget review state";
    public const string ForgetSavedOneLabel = "Discard one saved review…";
    public const string ForgetSavedAllLabel = "Discard every saved review";
    public const string ForgetDeltaOneLabel = "Forget delta marker for one branch…";
    public const string ForgetDeltaAllLabel = "Forget every delta marker";
    public const string ForgetDeltaStaleLabel = "Forget stale delta markers";
    public const string ForgetSavedSourceTitle = "Saved review to discard";
    public const string ForgetDeltaSourceTitle = "Branch for delta marker";

    public const string InstallDocsUrl =
        "https://github.com/EzeVillo/git-review-workflow#readme";

    public static string NavigateFailed(string direction) =>
        direction == "next"
            ? "Could not move to the next entry."
            : "Could not move to the previous entry.";

    public const string OpenRangeFailed = "Could not read the files of this review's range.";
    public static string OpenNoChangesLeft(string display) =>
        $"{display} has no changes left in this review.";
    public static string OpenCommitFailed(string sha) => $"Could not read the files of commit {sha}.";
    public static string OpenCommitEmpty(string sha) => $"Commit {sha} changes no files.";

    public static string FailureFallback(string action, ActionParams? params_ = null)
    {
        params_ ??= ActionParams.Empty.Instance;
        return action switch
        {
            "abortReview" => AbortFailed,
            "saveReview" => SaveFailed,
            "continueReview" => ContinueFailed,
            "finishReview" => FinishFailed,
            "undoFinish" => params_ is ActionParams.UndoFinish { Force: true }
                ? ForceUndoFailed
                : UndoAbortFailed,
            "resumeFinish" => ResumeFailed,
            "compareReview" => CompareFailed,
            "walkthroughInit" => params_ is ActionParams.WalkthroughInit { Force: true }
                ? WalkthroughForceFailed
                : WalkthroughInitFailed,
            "walkthroughBuild" => WalkthroughBuildFailed,
            "previewEdits" or "previewEditsStat" => PreviewFailed,
            "setBase" or "setRemote" => "Could not save the setting.",
            "next" => NavigateFailed("next"),
            "prev" => NavigateFailed("prev"),
            "startReview" => StartFailed,
            "cleanReview" or "forgetReview" =>
                params_ is ActionParams.Housekeeping hk
                && HousekeepingLogic.VerbForHousekeeping(hk.Action) == "forget"
                    ? "Could not forget that."
                    : "Could not clean up.",
            _ => "Something went wrong.",
        };
    }
}
