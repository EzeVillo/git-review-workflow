namespace GitReview.Domain;

/// <summary>Outcome of an invocation (data-model § Situation). Pure logic, no IDE.</summary>
public enum Situation
{
    Review,
    NoReview,
    OutOfRange,
    Error,
    CliMissing,
    CliOutdated,
    FinishConflict,
    FinishPending,
}

public static class SituationIds
{
    public static string Id(this Situation s) => s switch
    {
        Situation.Review => "review",
        Situation.NoReview => "no-review",
        Situation.OutOfRange => "out-of-range",
        Situation.Error => "error",
        Situation.CliMissing => "cli-missing",
        Situation.CliOutdated => "cli-outdated",
        Situation.FinishConflict => "finish-conflict",
        Situation.FinishPending => "finish-pending",
        _ => throw new ArgumentOutOfRangeException(nameof(s)),
    };

    public static Situation? FromId(string id) => id switch
    {
        "review" => Situation.Review,
        "no-review" => Situation.NoReview,
        "out-of-range" => Situation.OutOfRange,
        "error" => Situation.Error,
        "cli-missing" => Situation.CliMissing,
        "cli-outdated" => Situation.CliOutdated,
        "finish-conflict" => Situation.FinishConflict,
        "finish-pending" => Situation.FinishPending,
        _ => null,
    };

    /// <summary>
    /// Maps <c>status --porcelain</c> exit code to Situation.
    /// Unknown codes (including 1) are always Error, never Review.
    /// </summary>
    public static Situation ForExitCode(int? exitCode) => exitCode switch
    {
        0 => Situation.Review,
        2 => Situation.NoReview,
        3 => Situation.OutOfRange,
        _ => Situation.Error,
    };

    /// <summary>
    /// Extends <see cref="ForExitCode"/> with finish records:
    /// finish-conflict over review, finish-pending over no-review.
    /// </summary>
    public static Situation For(
        int? exitCode,
        bool hasFinishConflict,
        bool hasFinishPending)
    {
        var bas = ForExitCode(exitCode);
        if (bas == Situation.Review && hasFinishConflict) return Situation.FinishConflict;
        if (bas == Situation.NoReview && hasFinishPending) return Situation.FinishPending;
        return bas;
    }

    public static bool IsReviewReadable(Situation situation) =>
        situation is Situation.Review or Situation.FinishConflict;
}
