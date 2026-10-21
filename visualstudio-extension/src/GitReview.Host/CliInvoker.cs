using System.Diagnostics;
using System.Text;
using GitReview.Domain;

namespace GitReview.Host;

public sealed record InvokeResult(
    string Stdout,
    string Stderr,
    int? ExitCode,
    string? ErrorCode = null,
    bool TimedOut = false);

/// <summary>
/// Spawns git-review with forced UTF-8 capture, shell:false, cwd = repo root.
/// Domain-facing: no UI. Windows: PATH search for git; optional dispatcher via sh.
/// </summary>
/// <remarks>
/// The two entry points are virtual so the refresh pipeline can be tested against a
/// scripted CLI instead of a real one. Spawning a process per case would make the
/// suite slow and, on the interesting cases (a timeout, a CLI that is not there), it
/// would be testing the machine rather than <see cref="ReviewStateManager"/>.
/// </remarks>
public class CliInvoker
{
    private readonly Func<string?> _gitReviewPath;
    private readonly Func<string> _askpassCommand;
    private readonly Action<string>? _log;

    public CliInvoker(
        Func<string?>? gitReviewPath = null,
        Func<string>? askpassCommand = null,
        Action<string>? log = null)
    {
        _gitReviewPath = gitReviewPath ?? (() => null);
        _askpassCommand = askpassCommand ?? ResolveAskpassCommand;
        _log = log;
    }

    /// <summary>
    /// The dispatcher path this invoker resolves against, as the options page has it.
    /// Read for the command line offered when a network start fails: that has to be the
    /// same invocation this would have made, not a guess at it.
    /// </summary>
    public string? GitReviewPath => _gitReviewPath();

    public virtual Task<InvokeResult> InvokeWithInputAsync(string verb, IReadOnlyList<string> args, string cwd, string input, CancellationToken cancellationToken = default) =>
        InvokeResolvedWithInputAsync(ResolveCommand.Resolve(verb, args, _gitReviewPath()), cwd, false, TimeoutClass.TimeoutForClass(verb, args), cancellationToken, input);

    public virtual async Task<InvokeResult> InvokeAsync(
        string verb,
        IReadOnlyList<string> args,
        string cwd,
        bool network = false,
        long? timeoutMs = null,
        CancellationToken cancellationToken = default)
    {
        var resolved = ResolveCommand.Resolve(verb, args, _gitReviewPath());
        var ms = timeoutMs ?? TimeoutClass.TimeoutForClass(verb, args);
        return await InvokeResolvedAsync(resolved, cwd, network, ms, cancellationToken)
            .ConfigureAwait(false);
    }

    public virtual Task<InvokeResult> InvokeResolvedAsync(ResolvedCommand resolved, string cwd, bool network, long timeoutMs, CancellationToken cancellationToken = default) =>
        InvokeResolvedWithInputAsync(resolved, cwd, network, timeoutMs, cancellationToken, null);

    private async Task<InvokeResult> InvokeResolvedWithInputAsync(
        ResolvedCommand resolved,
        string cwd,
        bool network,
        long timeoutMs,
        CancellationToken cancellationToken,
        string? input)
    {
        var clock = Stopwatch.StartNew();
        var line = CliLog.FormatCommandLine(resolved.Command, resolved.Args);
        Log($"→ {line}  (cwd={cwd})");
        CliLogSink.Append($"→ {line}  (cwd={cwd})");

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = resolved.Command,
                WorkingDirectory = cwd,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
            };
            ProcessCompat.AddArgs(psi, resolved.Args);

            // La unica variable que esta extension le impone a la CLI, y va en
            // TODA invocacion. Apaga las notas que un panel no necesita: las
            // que ofrecen un comando --aca es un boton-- y las que describen
            // algo que ya viaja como registro porcelain --aca es una fila--.
            // Un solo lugar, porque del otro lado no hay filtro posible:
            // distinguir una nota de otra seria leer salida humana, que el
            // contrato de invocacion prohibe. Lo que NO es advice sigue
            // llegando entero (una entrada que el PR ya no cambia, un cursor
            // que se movio). Ver advice_enabled en bin/git-review-lib.sh; una
            // CLI vieja la ignora y solo imprime de mas.
            psi.Environment["GIT_REVIEW_ADVICE"] = "0";
            if (resolved.Args.Contains("cat-file")) psi.Environment["GIT_NO_LAZY_FETCH"] = "1";

            if (network)
            {
                var askpass = _askpassCommand();
                psi.Environment["GIT_TERMINAL_PROMPT"] = "0";
                psi.Environment["GIT_ASKPASS"] = askpass;
                psi.Environment["SSH_ASKPASS"] = askpass;
            }

            using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
            var stdout = new StringBuilder();
            var stderr = new StringBuilder();

            if (!process.Start())
            {
                var fail = new InvokeResult("", "failed to start process", null, "StartFailed");
                LogEnd(fail, clock.ElapsedMilliseconds);
                return fail;
            }

            var stdoutTask = CaptureOutputAsync(process.StandardOutput, stdout);
            var stderrTask = CaptureOutputAsync(process.StandardError, stderr);

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(TimeSpan.FromMilliseconds(timeoutMs));
            var inputTask = WriteInputAsync(process, input ?? "", timeoutCts.Token);

            try
            {
                await ProcessCompat.WaitForExitAsync(process, timeoutCts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                try
                {
                    if (!process.HasExited) ProcessCompat.KillTree(process);
                }
                catch { /* best-effort */ }
                var timed = new InvokeResult(stdout.ToString(), stderr.ToString(), null, ErrorCode: cancellationToken.IsCancellationRequested ? "Canceled" : null, TimedOut: !cancellationToken.IsCancellationRequested);
                LogEnd(input is null ? timed : timed with { Stderr = "" }, clock.ElapsedMilliseconds);
                return timed;
            }

            // Drain async readers
            await inputTask.ConfigureAwait(false);
            await Task.WhenAll(stdoutTask, stderrTask).ConfigureAwait(false);

            var result = new InvokeResult(stdout.ToString(), stderr.ToString(), process.ExitCode);
            LogEnd(input is null ? result : result with { Stderr = "" }, clock.ElapsedMilliseconds);
            return result;
        }
        catch (Exception e)
        {
            var result = new InvokeResult(
                "",
                e.Message,
                null,
                ErrorCode: e.GetType().Name);
            LogEnd(result, clock.ElapsedMilliseconds);
            return result;
        }
    }

    private static async Task WriteInputAsync(Process process, string input, CancellationToken cancellationToken)
    {
        try
        {
            var bytes = new UTF8Encoding(false).GetBytes(input);
            await process.StandardInput.BaseStream.WriteAsync(bytes, 0, bytes.Length, cancellationToken).ConfigureAwait(false);
            process.StandardInput.Close();
        }
        catch (IOException) { /* The process result supplies the diagnostic. */ }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
    }

    private static async Task CaptureOutputAsync(StreamReader reader, StringBuilder target)
    {
        var buffer = new char[4096];
        int count;
        while ((count = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) > 0)
            lock (target) target.Append(buffer, 0, count);
    }

    private void LogEnd(InvokeResult result, long durationMs)
    {
        var end = new CliLog.CliLogEnd(
            result.ExitCode,
            result.ErrorCode,
            durationMs,
            result.Stderr,
            result.TimedOut);
        foreach (var line in CliLog.FormatCliEnd(end))
        {
            Log(line);
            CliLogSink.Append(line);
        }
    }

    private void Log(string message) => _log?.Invoke(message);

    /// <summary>In-memory ring buffer for "Show CLI Log".</summary>
    public static class CliLogSink
    {
        private const int Max = 500;
        private static readonly object Gate = new();
        private static readonly LinkedList<string> Lines = new();

        public static void Append(string line)
        {
            lock (Gate)
            {
                Lines.AddLast(line);
                while (Lines.Count > Max) Lines.RemoveFirst();
            }
        }

        public static IReadOnlyList<string> Snapshot()
        {
            lock (Gate) return Lines.ToList();
        }

        public static void Clear()
        {
            lock (Gate) Lines.Clear();
        }
    }

    public static string ResolveAskpassCommand()
    {
        var isWin = RuntimeInfo.IsWindows;
        var dir = Path.Combine(Path.GetTempPath(), "git-review-askpass");
        Directory.CreateDirectory(dir);
        if (isWin)
        {
            var file = Path.Combine(dir, "askpass-noop.cmd");
            if (!File.Exists(file))
                File.WriteAllText(file, "@echo off\r\nexit /b 0\r\n", Encoding.UTF8);
            return file;
        }
        else
        {
            var file = Path.Combine(dir, "askpass-noop.sh");
            if (!File.Exists(file))
            {
                File.WriteAllText(file, "#!/bin/sh\nexit 0\n", Encoding.UTF8);
                ProcessCompat.MakeExecutable(file);
            }
            return file;
        }
    }
}
