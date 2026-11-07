using GitReview.Domain;

namespace GitReview.Host;

/// <summary>Preserves the gesture's context across confirmations and async work.</summary>
public sealed class MutationExpectation
{
    private readonly AsyncLocal<StateToken?> _current = new();
    public StateToken? Current => _current.Value;

    public IDisposable Capture(ReviewState state)
    {
        var previous = _current.Value;
        _current.Value = StaleGuard.CaptureToken(state);
        return new Restore(() => _current.Value = previous);
    }

    private sealed class Restore(Action restore) : IDisposable
    {
        public void Dispose() => restore();
    }
}
