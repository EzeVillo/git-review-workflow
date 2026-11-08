namespace GitReview.Host;

/// <summary>Coalesces observations around mutations without caching CLI state.</summary>
public sealed class RefreshGate
{
    private readonly object _gate = new();
    private bool _busy, _pending, _reading;
    public void Request() { lock (_gate) _pending = true; }
    public void MutationChanged(bool busy) { lock (_gate) _busy = busy; }
    public void PrimaryStarting() { lock (_gate) _pending = false; }
    public bool TryStart()
    {
        lock (_gate)
        {
            if (_busy || _reading || !_pending) return false;
            _pending = false;
            _reading = true;
            return true;
        }
    }
    public void Finished() { lock (_gate) _reading = false; }
}
