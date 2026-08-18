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
public sealed class CliInvoker
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

    public async Task<InvokeResult> InvokeAsync(
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

    public async Task<InvokeResult> InvokeResolvedAsync(
        ResolvedCommand resolved,
        string cwd,
        bool network,
        long timeoutMs,
        CancellationToken cancellationToken = default)
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
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is not null) stdout.AppendLine(e.Data);
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is not null) stderr.AppendLine(e.Data);
            };

            if (!process.Start())
            {
                var fail = new InvokeResult("", "failed to start process", null, "StartFailed");
                LogEnd(fail, clock.ElapsedMilliseconds);
                return fail;
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(TimeSpan.FromMilliseconds(timeoutMs));

            try
            {
                await ProcessCompat.WaitForExitAsync(process, timeoutCts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    if (!process.HasExited) ProcessCompat.KillTree(process);
                }
                catch { /* best-effort */ }
                var timed = new InvokeResult(stdout.ToString(), stderr.ToString(), null, TimedOut: true);
                LogEnd(timed, clock.ElapsedMilliseconds);
                return timed;
            }

            // Drain async readers
            await Task.Delay(20, CancellationToken.None).ConfigureAwait(false);

            var result = new InvokeResult(stdout.ToString(), stderr.ToString(), process.ExitCode);
            LogEnd(result, clock.ElapsedMilliseconds);
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
