namespace GitReview.Domain;

public enum FinishOutcome
{
    NoEdits,
    Pending,
}

public static class FinishOutcomeLogic
{
    /// <summary>
    /// Decide toast after successful finish from refreshed state only — never parse finish human stdout.
    /// </summary>
    public static FinishOutcome FinishOutcome(ReviewState refreshed, string branch)
    {
        var pending = refreshed.BranchesList.Any(b => b.Name == branch && b.Finish?.State == "pending");
        return pending ? Domain.FinishOutcome.Pending : Domain.FinishOutcome.NoEdits;
    }
}
