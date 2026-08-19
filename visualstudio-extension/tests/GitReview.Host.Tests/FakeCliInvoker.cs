using GitReview.Domain;

namespace GitReview.Host.Tests;

/// <summary>
/// A scripted CLI: answers by verb, records what it was asked. Everything the
/// refresh pipeline decides comes out of these four or five answers, so this is
/// where its branches can actually be exercised — a real process per case would be
/// slow and, for a timeout or a missing CLI, would be testing the machine.
/// </summary>
internal sealed class FakeCliInvoker : CliInvoker
{
    private readonly Dictionary<string, Func<IReadOnlyList<string>, InvokeResult>> _answers = new(StringComparer.Ordinal);

    public List<(string Verb, IReadOnlyList<string> Args, string Cwd, bool Network)> Calls { get; } = new();

    public InvokeResult Fallback { get; set; } = new("", "", 0);

    public FakeCliInvoker()
    {
        // A CLI that is present and current, unless a test says otherwise.
        // The minimum itself, not a literal: a bump of MinCliVersion would
        // otherwise turn every state test into a cli-outdated panel.
        Answer("--version", CliVersion.MinCliVersion + "\n");
    }

    public FakeCliInvoker Answer(string verb, InvokeResult result)
    {
        _answers[verb] = _ => result;
        return this;
    }

    public FakeCliInvoker Answer(string verb, string stdout, int exitCode = 0)
        => Answer(verb, new InvokeResult(stdout, "", exitCode));

    public FakeCliInvoker Fails(string verb, string stderr, int exitCode = 1)
        => Answer(verb, new InvokeResult("", stderr, exitCode));

    public override Task<InvokeResult> InvokeAsync(
        string verb,
        IReadOnlyList<string> args,
        string cwd,
        bool network = false,
        long? timeoutMs = null,
        CancellationToken cancellationToken = default)
    {
        Calls.Add((verb, args, cwd, network));
        var result = _answers.TryGetValue(verb, out var answer) ? answer(args) : Fallback;
        return Task.FromResult(result);
    }

    public override Task<InvokeResult> InvokeResolvedAsync(
        ResolvedCommand resolved,
        string cwd,
        bool network,
        long timeoutMs,
        CancellationToken cancellationToken = default)
    {
        Calls.Add((resolved.Command, resolved.Args, cwd, network));
        return Task.FromResult(Fallback);
    }

    public IReadOnlyList<string> Verbs => Calls.Select(c => c.Verb).ToList();
}
