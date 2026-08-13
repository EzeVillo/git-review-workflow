namespace GitReview.Domain;

public static class SoleTarget
{
    /// <summary>Single usable root, like CLI cwd: 0 → none; 1 → that; 2+ → none (no guessing).</summary>
    public static T? PickSoleTarget<T>(IReadOnlyList<T> targets) =>
        targets.Count == 1 ? targets[0] : default;
}
