namespace GitReview.Domain;

public sealed record StateToken(
    string? Branch,
    string? Tip,
    Situation Situation);

public static class StaleGuard
{
    public static StateToken CaptureToken(ReviewState state) => new(
        state.State?.Branch,
        state.State?.Tip,
        state.Situation);

    public static bool TokenStillValid(StateToken token, ReviewState state) =>
        token.Situation == state.Situation
        && token.Branch == state.State?.Branch
        && token.Tip == state.State?.Tip;
}
