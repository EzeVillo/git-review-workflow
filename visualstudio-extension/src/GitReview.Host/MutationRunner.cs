using GitReview.Domain;

namespace GitReview.Host;

/// <summary>
/// Serializes mutations through MutationLock and refreshes state after each.
/// </summary>
public sealed class MutationRunner
{
    private readonly CliInvoker _cli;
    private readonly ReviewStateManager _state;
    private readonly MutationLock _lock = new();
    private readonly Func<string?> _cwd;

    public MutationLock Lock => _lock;
    public bool IsBusy => _lock.IsBusy;

    public MutationRunner(CliInvoker cli, ReviewStateManager state, Func<string?> cwd)
    {
        _cli = cli;
        _state = state;
        _cwd = cwd;
    }

    public async Task<InvokeResult?> RunActionAsync(
        string action,
        ActionParams? params_ = null,
        bool network = false,
        CancellationToken ct = default)
    {
        var cwd = _cwd();
        if (cwd is null)
            return new InvokeResult("", UserCopy.NoSoleRoot, 1);

        return await _lock.RunAsync(async () =>
        {
            var argv = ActionArgvMap.ActionToArgv(action, params_);
            if (string.IsNullOrEmpty(argv.Verb))
                return new InvokeResult("", "", 0);

            var result = await _cli.InvokeAsync(
                argv.Verb,
                argv.Args,
                cwd,
                network: network || argv.Network,
                cancellationToken: ct).ConfigureAwait(false);

            await _state.RefreshAsync(ct).ConfigureAwait(false);
            return result;
        }).ConfigureAwait(false);
    }

    public async Task<InvokeResult?> RunArgvAsync(
        string verb,
        IReadOnlyList<string> args,
        bool network = false,
        CancellationToken ct = default)
    {
        var cwd = _cwd();
        if (cwd is null)
            return new InvokeResult("", UserCopy.NoSoleRoot, 1);

        return await _lock.RunAsync(async () =>
        {
            var result = await _cli.InvokeAsync(verb, args, cwd, network, cancellationToken: ct)
                .ConfigureAwait(false);
            await _state.RefreshAsync(ct).ConfigureAwait(false);
            return result;
        }).ConfigureAwait(false);
    }
}
