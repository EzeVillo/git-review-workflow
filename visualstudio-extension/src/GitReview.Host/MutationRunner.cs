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
    public Func<string,ActionParams?,Task<bool>>? BeforeMutation {get;set;}
    public Func<StateToken?>? ExpectedState {get;set;}

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
        CancellationToken ct = default,
        StateToken? expected = null)
    {
        var token = expected ?? ExpectedState?.Invoke() ?? StaleGuard.CaptureToken(_state.Current);
        var cwd = _cwd();
        if (cwd is null)
            return new InvokeResult("", UserCopy.NoSoleRoot, 1);

        return await _lock.RunAsync(async () =>
        {
            var argv = ActionArgvMap.ActionToArgv(action, params_);
            if (string.IsNullOrEmpty(argv.Verb))
                return new InvokeResult("", "", 0);
            _state.InvalidatePendingReads();
            if (BeforeMutation is not null && !await BeforeMutation(action,params_).ConfigureAwait(true))
            {
                await _state.RefreshPrimaryAsync(ct).ConfigureAwait(false);
                return new InvokeResult("",CommentsCopy.saveFailed,1);
            }

            var navigation = action is "next" or "prev" && _state.Current.NavigationState && token.Guard is not null;
            var saved = action == "saveReview" && _state.Current.SaveState && token.Guard is not null;
            var result = await _cli.InvokeWithStateGuardAsync(
                argv.Verb,
                (navigation || saved) ? argv.Args.Concat(new[]{"--porcelain"}).ToArray() : argv.Args,
                cwd,
                token.Guard,
                network: network || argv.Network,
                cancellationToken: ct).ConfigureAwait(false);

            await _state.RefreshPrimaryAsync(ct, (navigation || saved) && result.ExitCode == 0 && !result.TimedOut && result.ErrorCode is null ? result.Stdout : null).ConfigureAwait(false);
            if (navigation && result.ExitCode == 0) result = result with { Stdout = NavigationReply.Notice(result.Stdout) };
            if (result.ExitCode == 4) result = result with { Stderr = UserCopy.Stale };
            return result;
        }).ConfigureAwait(false);
    }

    public async Task<InvokeResult?> RunArgvAsync(
        string verb,
        IReadOnlyList<string> args,
        bool network = false,
        CancellationToken ct = default,
        StateToken? expected = null)
    {
        var token = expected ?? ExpectedState?.Invoke() ?? StaleGuard.CaptureToken(_state.Current);
        var cwd = _cwd();
        if (cwd is null)
            return new InvokeResult("", UserCopy.NoSoleRoot, 1);

        return await _lock.RunAsync(async () =>
        {
            _state.InvalidatePendingReads();
            var result = await _cli.InvokeWithStateGuardAsync(verb, args, cwd, token.Guard, network, ct)
                .ConfigureAwait(false);
            await _state.RefreshPrimaryAsync(ct).ConfigureAwait(false);
            if (result.ExitCode == 4) result = result with { Stderr = UserCopy.Stale };
            return result;
        }).ConfigureAwait(false);
    }
}
