namespace GitReview.Domain;

public enum HousekeepingKind
{
    CleanOne,
    CleanKeepFixes,
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
    bool? Onto = null);

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

    public static ConfirmCopy ConfirmCopyFor(HousekeepingAction action)
    {
        var src = action.Source ?? "";
        return action.Kind switch
        {
            HousekeepingKind.CleanOne => new ConfirmCopy(
                $"Clean leftover review branches for {src}?",
                $"Deletes review/{src} and review-fixes/{src} (and banked edit refs) if they exist and are not checked out. Does not touch delta markers.",
                "Clean"),
            HousekeepingKind.CleanKeepFixes => new ConfirmCopy(
                $"Drop the finish undo for {src}?",
                $"Runs git review clean --keep-fixes {src}: deletes review/{src} and the finish undo point so the pending finish goes away. Your staged edits stay on {(action.Onto == true ? src : $"review-fixes/{src}")}; delta markers are left alone. Remember to commit and push them from Source Control.",
                "Clean"),
            HousekeepingKind.CleanAll => new ConfirmCopy(
                "Clean all leftover review branches?",
                "Deletes every review/* and review-fixes/* branch that is not currently checked out, plus orphaned edit/undo refs. Does not touch delta markers or saved reviews.",
                "Clean All"),
            HousekeepingKind.ForgetSavedOne => new ConfirmCopy(
                $"Discard the saved review of {src}?",
                $"Deletes review-saved/{src}, its banked edits and metadata, and rolls back the delta marker it left.",
                "Discard"),
            HousekeepingKind.ForgetSavedAll => new ConfirmCopy(
                "Discard every saved review?",
                "Deletes all review-saved/* branches, their banked edits and metadata, and rolls back their delta markers.",
                "Discard All Saved"),
            HousekeepingKind.ForgetDeltaOne => new ConfirmCopy(
                $"Forget the delta marker for {src}?",
                "Removes the last-reviewed tip used by git review start --delta for this branch (remote and local markers).",
                "Forget Marker"),
            HousekeepingKind.ForgetDeltaAll => new ConfirmCopy(
                "Forget every delta marker?",
                "Removes all last-reviewed tips used by git review start --delta.",
                "Forget All Markers"),
            HousekeepingKind.ForgetDeltaStale => new ConfirmCopy(
                "Forget stale delta markers?",
                "Fetches from the remote (when needed) and removes markers whose branch no longer exists.",
                "Forget Stale"),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }
}
