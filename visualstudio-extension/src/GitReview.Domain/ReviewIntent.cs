namespace GitReview.Domain;

public enum ReviewLayout
{
    Walk,
    Keys,
    Step,
    Whole,
}

public static class ReviewLayoutExt
{
    public static string Id(this ReviewLayout l) => l switch
    {
        ReviewLayout.Walk => "walk",
        ReviewLayout.Keys => "keys",
        ReviewLayout.Step => "step",
        ReviewLayout.Whole => "whole",
        _ => throw new ArgumentOutOfRangeException(nameof(l)),
    };
}

public enum ReviewRange
{
    Full,
    Delta,
}

public static class ReviewRangeExt
{
    public static string Id(this ReviewRange r) => r switch
    {
        ReviewRange.Full => "full",
        ReviewRange.Delta => "delta",
        _ => throw new ArgumentOutOfRangeException(nameof(r)),
    };
}

public enum ReviewSource
{
    Remote,
    Local,
    Offline,
}

public static class ReviewSourceExt
{
    public static string Id(this ReviewSource s) => s switch
    {
        ReviewSource.Remote => "remote",
        ReviewSource.Local => "local",
        ReviewSource.Offline => "offline",
        _ => throw new ArgumentOutOfRangeException(nameof(s)),
    };

    public static ReviewSource? Parse(string? raw) => raw switch
    {
        "remote" => ReviewSource.Remote,
        "local" => ReviewSource.Local,
        "offline" => ReviewSource.Offline,
        _ => null,
    };
}

public sealed record ReviewIntent(
    string? Branch,
    ReviewLayout Layout,
    ReviewRange Range,
    ReviewSource Source);

public sealed record IntentValidationContext(DeltaRecord? Delta = null);

public abstract record IntentValidationResult
{
    public sealed record Ok : IntentValidationResult
    {
        public static readonly Ok Instance = new();
    }
    public sealed record Fail(string Reason) : IntentValidationResult;
}

public static class ReviewIntentLogic
{
    public static IntentValidationResult ValidateIntent(ReviewIntent intent, IntentValidationContext context)
    {
        if (intent.Range == ReviewRange.Delta && context.Delta is null)
        {
            return new IntentValidationResult.Fail(
                "range \"delta\" requires a prior review tip (delta record) for the chosen source");
        }
        return IntentValidationResult.Ok.Instance;
    }

    /// <summary>
    /// Translates ReviewIntent to start argv (without the verb).
    /// Order: layout flags → --delta? → --local|--offline? → -- → branch
    /// </summary>
    public static IReadOnlyList<string> IntentToArgs(ReviewIntent intent, string currentBranch)
    {
        var args = new List<string>();
        switch (intent.Layout)
        {
            case ReviewLayout.Step: args.Add("--step"); break;
            case ReviewLayout.Whole: args.Add("--no-walk"); break;
            case ReviewLayout.Keys: args.Add("--keys"); break;
            case ReviewLayout.Walk: break;
        }
        if (intent.Range == ReviewRange.Delta) args.Add("--delta");
        switch (intent.Source)
        {
            case ReviewSource.Local: args.Add("--local"); break;
            case ReviewSource.Offline: args.Add("--offline"); break;
            case ReviewSource.Remote: break;
        }
        args.Add("--");
        args.Add(intent.Branch ?? currentBranch);
        return args;
    }

    /// <summary>
    /// Argv for <c>git review walkthrough draft</c> (011). Verb is walkthrough; draft is first arg.
    /// </summary>
    public static IReadOnlyList<string> DraftArgs(
        string branch,
        ReviewSource source,
        ReviewRange range,
        bool build)
    {
        var args = new List<string> { "draft" };
        if (build) args.Add("--build");
        args.AddRange(OriginAndRangeFlags(source, range));
        args.Add("--");
        args.Add(branch);
        return args;
    }

    /// <summary>
    /// The origin and range flags, in the order the CLI documents. One place,
    /// because the three steps of "Validate and start" — draft --build, the
    /// config --porcelain that follows and the final start — have to carry
    /// exactly the same ones: if they differ, the three speak about different
    /// ranges.
    /// </summary>
    private static List<string> OriginAndRangeFlags(ReviewSource source, ReviewRange range)
    {
        var args = new List<string>();
        switch (source)
        {
            case ReviewSource.Local: args.Add("--local"); break;
            case ReviewSource.Offline: args.Add("--offline"); break;
            case ReviewSource.Remote: break;
        }
        if (range == ReviewRange.Delta) args.Add("--delta");
        return args;
    }

    /// <summary>
    /// <c>git review config --porcelain &lt;flags&gt; -- &lt;branch&gt;</c> for a draft row:
    /// invoked after a green --build from the panel, only to learn whether that draft
    /// carries essential entries (`offer keys`).
    ///
    /// The flags are not the defaults: they come from the source/range fields of the
    /// `draft` record, which are the ones the CLI wrote into the instruction block when
    /// it generated the skeleton.
    /// </summary>
    public static IReadOnlyList<string> DraftConfigArgs(
        string branch,
        ReviewSource source,
        ReviewRange range)
    {
        var args = new List<string> { "--porcelain" };
        args.AddRange(OriginAndRangeFlags(source, range));
        args.Add("--");
        args.Add(branch);
        return args;
    }

    /// <summary>
    /// <c>git review forget --draft -- &lt;branch&gt;</c>: discard the draft of ONE row.
    /// Never --all (it would sweep the other rows, and archived ones nobody is looking
    /// at) nor --saved (that is a paused review's prose), and never without the branch.
    /// </summary>
    public static IReadOnlyList<string> ForgetDraftArgs(string branch) =>
        new List<string> { "--draft", "--", branch };

    /// <summary>
    /// <c>git review walkthrough guide [--team]</c>: create an authoring guide, empty.
    /// The verb is walkthrough; guide is the first argument, like draft. No branch and
    /// no origin or range flags: a guide covers no range. Never --force — the CLI
    /// refuses it anyway, because overwriting hand-written prose with an empty file is
    /// not something a flag should be able to do.
    /// </summary>
    public static IReadOnlyList<string> CreateGuideArgs(bool team) =>
        team ? new List<string> { "guide", "--team" } : new List<string> { "guide" };

    /// <summary>
    /// <c>git review walkthrough guide --delete</c>: remove YOUR guide. Never with
    /// --team: the shared one is a tracked file, so taking it out is `git rm` plus a
    /// commit, and the CLI refuses the combination.
    /// </summary>
    public static IReadOnlyList<string> DeleteGuideArgs() =>
        new List<string> { "guide", "--delete" };
}
