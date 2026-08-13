namespace GitReview.Domain;

public enum InvocationClass
{
    Read,
    LocalMutation,
    Network,
    SupportGit,
}

public static class TimeoutClass
{
    public const long ReadTimeoutMs = 15_000;
    public const long LocalMutationTimeoutMs = 120_000;
    public const long NetworkMutationTimeoutMs = 300_000;
    public const long SupportGitTimeoutMs = 30_000;

    private static readonly HashSet<string> LocalMutationVerbs = new(StringComparer.Ordinal)
    {
        "finish", "save", "abort", "continue", "next", "prev",
        "clean", "forget", "compare", "walkthrough", "preview",
    };

    private static readonly HashSet<string> NetworkMutationVerbs = new(StringComparer.Ordinal)
    {
        "start",
    };

    public static long TimeoutForClass(string verb, IReadOnlyList<string> args)
    {
        if (NetworkMutationVerbs.Contains(verb)) return NetworkMutationTimeoutMs;
        if (verb == "forget" && args.Contains("--stale")) return NetworkMutationTimeoutMs;
        if (LocalMutationVerbs.Contains(verb)) return LocalMutationTimeoutMs;
        return ReadTimeoutMs;
    }

    public static long TimeoutMs(InvocationClass invocationClass) => invocationClass switch
    {
        InvocationClass.Read => ReadTimeoutMs,
        InvocationClass.LocalMutation => LocalMutationTimeoutMs,
        InvocationClass.Network => NetworkMutationTimeoutMs,
        InvocationClass.SupportGit => SupportGitTimeoutMs,
        _ => ReadTimeoutMs,
    };
}
