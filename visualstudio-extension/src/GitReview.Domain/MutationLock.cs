namespace GitReview.Domain;

/// <summary>Depth-1 lock for mutations: a second call while busy is discarded, not queued.</summary>
public sealed class MutationLock
{
    public const string DiscardReason = "Another operation is already in progress";

    private readonly object _gate = new();
    private bool _busy;
    private readonly List<Action<bool>> _busyListeners = new();
    private readonly List<Action<string>> _discardListeners = new();

    public bool IsBusy
    {
        get { lock (_gate) return _busy; }
    }

    public IDisposable OnDidChangeBusy(Action<bool> listener)
    {
        lock (_gate) _busyListeners.Add(listener);
        return new Unsub(() => { lock (_gate) _busyListeners.Remove(listener); });
    }

    public IDisposable OnDidDiscard(Action<string> listener)
    {
        lock (_gate) _discardListeners.Add(listener);
        return new Unsub(() => { lock (_gate) _discardListeners.Remove(listener); });
    }

    public T? Run<T>(Func<T> fn)
    {
        lock (_gate)
        {
            if (_busy)
            {
                foreach (var l in _discardListeners.ToArray()) l(DiscardReason);
                return default;
            }
            SetBusy(true);
        }
        try
        {
            return fn();
        }
        finally
        {
            lock (_gate) SetBusy(false);
        }
    }

    public async Task<T?> RunAsync<T>(Func<Task<T>> fn)
    {
        lock (_gate)
        {
            if (_busy)
            {
                foreach (var l in _discardListeners.ToArray()) l(DiscardReason);
                return default;
            }
            SetBusy(true);
        }
        try
        {
            return await fn().ConfigureAwait(false);
        }
        finally
        {
            lock (_gate) SetBusy(false);
        }
    }

    private void SetBusy(bool value)
    {
        _busy = value;
        foreach (var l in _busyListeners.ToArray()) l(value);
    }

    private sealed class Unsub(Action action) : IDisposable
    {
        public void Dispose() => action();
    }
}
