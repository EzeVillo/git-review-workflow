namespace GitReview.Domain;

public sealed record StateToken(
    string? Branch,
    string? Tip,
    Situation Situation,
    string? Guard = null,
    string? ContinueGuard = null);

public static class StaleGuard
{
    public static StateToken CaptureToken(ReviewState state) => new(
        state.State?.Branch,
        state.State?.Tip,
        state.Situation, state.Guard, state.ContinueGuard);

    public static bool TokenStillValid(StateToken token, ReviewState state) =>
        token.Situation == state.Situation
        && token.Branch == state.State?.Branch
        && token.Tip == state.State?.Tip
        && token.Guard == state.Guard && token.ContinueGuard == state.ContinueGuard;

    public static string? Parse(string output)
    {
        var guards = output.Split('\n').Select(line => line.TrimEnd('\r'))
            .Where(line => line.StartsWith("guard\t", StringComparison.Ordinal))
            .Select(line => line.Substring(6)).ToArray();
        if (guards.Length != 1) return null;
        var value = guards[0];
        return (value.Length is 40 or 64) && value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') ? value : null;
    }
}
