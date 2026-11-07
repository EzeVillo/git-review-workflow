using GitReview.Domain;

namespace GitReview.Host;

public static class GuardedInvocation
{
    public static Task<InvokeResult> InvokeWithStateGuardAsync(this CliInvoker cli,
        string verb, IReadOnlyList<string> args, string cwd, string? guard,
        bool network = false, CancellationToken cancellationToken = default) =>
        guard is null
            ? cli.InvokeAsync(verb, args, cwd, network, cancellationToken: cancellationToken)
            : cli.InvokeAsync("--expect-state", new[] {guard, verb}.Concat(args).ToArray(), cwd,
                network, TimeoutClass.TimeoutForClass(verb, args), cancellationToken);
}
