namespace GitReview.Domain;

public enum HousekeepingKind
{
    CleanOne,
    CleanKeepFixes,
    CleanFixesOne,
    CleanFixesOneAll,
    CleanAll,
    ForgetSavedOne,
    ForgetSavedAll,
    ForgetDeltaOne,
    ForgetDeltaAll,
    ForgetDeltaStale,
}

public sealed record HousekeepingAction(
    HousekeepingKind Kind,
    string? Source = null,
    bool? Onto = null,
    /// <summary>
    /// CleanFixesOne only: what the CLI reported about that branch, so the
    /// confirmation can say how much it costs. Nothing is derived here -- the one
    /// that can ask git is the CLI. Null reads as Unknown.
    /// </summary>
    FixesState? FixesState = null,
    /// <summary>
    /// CleanFixesOne only: whether review/&lt;src&gt; still exists. It changes the
    /// copy and nothing else -- the argv carries --fixes-only always, because a
    /// value re-read on every refresh cannot decide which branches a command
    /// deletes.
    /// </summary>
    bool Session = false);

public sealed record ConfirmCopy(string Title, string Detail, string Button);

public static class HousekeepingLogic
{
    public static string SourceFromReviewName(string name)
    {
        foreach (var prefix in new[] { "review-saved/", "review/", "review-fixes/" })
        {
            if (name.StartsWith(prefix, StringComparison.Ordinal))
                return name[prefix.Length..];
        }
        return name;
    }

    public static (string Source, bool Onto)? PendingFinishInfo(ReviewState state)
    {
        if (state.Situation != Situation.FinishPending) return null;
        var pending = state.BranchesList.FirstOrDefault(b => b.Finish?.State == "pending");
        if (pending?.Finish is null) return null;
        return (Porcelain.SourceOf(pending), pending.Finish.Onto);
    }

    public static string? PendingFinishSource(ReviewState state) =>
        PendingFinishInfo(state)?.Source;

    public static string VerbForHousekeeping(HousekeepingAction action) =>
        action.Kind.ToString().StartsWith("Clean", StringComparison.Ordinal) ? "clean" : "forget";

    public static IReadOnlyList<string> ArgsForHousekeeping(HousekeepingAction action) => action.Kind switch
    {
        HousekeepingKind.CleanOne =>
            string.IsNullOrEmpty(action.Source)
                ? throw new ArgumentException("clean-one requires source")
                : new[] { action.Source! },
        HousekeepingKind.CleanKeepFixes =>
            string.IsNullOrEmpty(action.Source)
                ? throw new ArgumentException("clean-keep-fixes requires source")
                : new[] { "--keep-fixes", action.Source! },
        HousekeepingKind.CleanFixesOne =>
            string.IsNullOrEmpty(action.Source)
                ? throw new ArgumentException("clean-fixes-only requires source")
                : new[] { "--fixes-only", action.Source! },
        // No branch: --fixes-only alone only ever touches review-fixes/* (clean's
        // own scoping, see bin/git-review-verbs/clean), so this never reaches a
        // live review/* session the way a bare CleanAll does.
        HousekeepingKind.CleanFixesOneAll => new[] { "--fixes-only" },
        HousekeepingKind.CleanAll => Array.Empty<string>(),
        HousekeepingKind.ForgetSavedOne =>
            string.IsNullOrEmpty(action.Source)
                ? throw new ArgumentException("forget-saved-one requires source")
                : new[] { "--saved", action.Source! },
        HousekeepingKind.ForgetSavedAll => new[] { "--saved", "--all" },
        HousekeepingKind.ForgetDeltaOne =>
            string.IsNullOrEmpty(action.Source)
                ? throw new ArgumentException("forget-delta-one requires source")
                : new[] { "--delta", action.Source! },
        HousekeepingKind.ForgetDeltaAll => new[] { "--delta", "--all" },
        HousekeepingKind.ForgetDeltaStale => new[] { "--delta", "--stale" },
        _ => throw new ArgumentOutOfRangeException(),
    };

    public static bool HousekeepingNeedsNetwork(HousekeepingAction action) =>
        action.Kind == HousekeepingKind.ForgetDeltaStale;

    /// <summary>
    /// What the CleanFixesOne confirmation says about the cost. One sentence per
    /// state and none folds into another: "nothing committed" is not "safe
    /// because it is already integrated", and "unknown" is not "not integrated".
    /// </summary>
    private static string FixesCostSentence(FixesState? state) => state switch
    {
        Domain.FixesState.Empty => "Nothing was ever committed on it, so no work of yours is lost.",
        Domain.FixesState.Merged => "Its commits are already in the base branch.",
        Domain.FixesState.Unmerged => "It has commits the base branch does not have -- deleting it loses them.",
        _ => "There is no base branch configured, so git cannot tell whether its commits are integrated.",
    };

    public static ConfirmCopy ConfirmCopyFor(HousekeepingAction action)
    {
        var src = action.Source ?? "";
        return action.Kind switch
        {
            HousekeepingKind.CleanOne => new ConfirmCopy(
                $"Delete the leftovers from reviewing {src}?",
                "This removes the review branch and any edits you extracted from it. Anything you already committed elsewhere stays. It cannot be undone.",
                "Delete"),
            // Lo que se CONSERVA va primero, y no es un adorno: este dialogo
            // sale del boton que cierra el ciclo, y la unica duda que frena a
            // alguien ahi es si el clean se lleva sus ediciones. La respuesta es
            // que no, y decirla antes de nombrar lo que si se pierde es la
            // diferencia entre leer el cartel y apretar a ciegas.
            HousekeepingKind.CleanKeepFixes => new ConfirmCopy(
                "Keep your edits & remove Undo?",
                $"Your edits stay on {(action.Onto == true ? src : $"review-fixes/{src}")} — commit and push them from Source Control. What goes away is the option to undo this finish.",
                "Keep edits & remove Undo"),
            HousekeepingKind.CleanFixesOne => new ConfirmCopy(
                $"Delete the edits you extracted from {src}?",
                FixesCostSentence(action.FixesState)
                    // The session is named only when it exists: promising to leave
                    // something that is not there is noise, and the argv is the same.
                    + (action.Session ? " You can still undo the finish afterwards." : "")
                    + " It cannot be undone.",
                "Delete"),
            HousekeepingKind.CleanFixesOneAll => new ConfirmCopy(
                "Delete every branch of extracted edits?",
                "They hold edits you made while reviewing and never committed anywhere else. Nothing you are reviewing right now is touched. It cannot be undone.",
                "Delete all"),
            HousekeepingKind.CleanAll => new ConfirmCopy(
                "Delete all review leftovers?",
                "This removes every review branch and every branch of extracted edits that you are not currently on. Paused reviews and your last review points are left alone. It cannot be undone.",
                "Delete all"),
            HousekeepingKind.ForgetSavedOne => new ConfirmCopy(
                $"Delete the paused review of {src}?",
                "This throws away the edits you had saved with it. It cannot be undone.",
                "Delete"),
            HousekeepingKind.ForgetSavedAll => new ConfirmCopy(
                "Delete every paused review?",
                "This throws away the edits saved with each of them. It cannot be undone.",
                "Delete all"),
            // Los tres de --delta dicen la CONSECUENCIA y no la operacion, y la
            // dicen con la etiqueta que el asistente usa para el rango ("only
            // what is new"): quien vaya a apretar esto lo eligio alguna vez ahi,
            // y es el unico lugar donde ese dato se nota. "Removes the
            // last-reviewed tip" describia un ref que ninguna superficie nombra.
            HousekeepingKind.ForgetDeltaOne => new ConfirmCopy(
                $"Forget where you got to on {src}?",
                "Next time you review this branch, \"only what is new\" will have no starting point, so you will be offered the full range instead.",
                "Forget"),
            HousekeepingKind.ForgetDeltaAll => new ConfirmCopy(
                "Forget where you got to on every branch?",
                "Next time you review any of them, \"only what is new\" will have no starting point, so you will be offered the full range instead.",
                "Forget all"),
            HousekeepingKind.ForgetDeltaStale => new ConfirmCopy(
                "Forget the branches that are gone?",
                "This clears where you got to on branches that no longer exist. It checks the remote first, so it may take a moment.",
                "Forget"),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }
}
