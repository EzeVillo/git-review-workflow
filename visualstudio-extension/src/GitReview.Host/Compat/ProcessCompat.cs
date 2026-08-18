using System.Diagnostics;
using System.Text;
using GitReview.Domain;

namespace GitReview.Host;

/// <summary>
/// The three process APIs this client needs that .NET Framework does not have.
/// Every caller goes through here, so <see cref="CliInvoker"/> and the callers in
/// GitReview.VS read the same on both target frameworks and the `#if` lives in
/// exactly one file.
/// </summary>
public static class ProcessCompat
{
    /// <summary>
    /// Passes arguments without a shell. net8.0 has <c>ArgumentList</c>; net472 only
    /// takes one command line, so it is built with the quoting rules
    /// <c>CommandLineToArgvW</c> reverses — the same algorithm .NET Core uses to fill
    /// <c>Arguments</c> from <c>ArgumentList</c>. Nothing is interpreted by a shell
    /// either way: spaces, quotes and backslashes in a path survive verbatim.
    /// </summary>
    public static void AddArgs(ProcessStartInfo psi, params string[] args) =>
        AddArgs(psi, (IReadOnlyList<string>)args);

    public static void AddArgs(ProcessStartInfo psi, IReadOnlyList<string> args)
    {
#if NET472
        var sb = new StringBuilder(psi.Arguments ?? "");
        foreach (var arg in args) AppendArgument(sb, arg);
        psi.Arguments = sb.ToString();
#else
        foreach (var arg in args) psi.ArgumentList.Add(arg);
#endif
    }

    /// <summary>Waits for exit, honouring cancellation. <c>WaitForExitAsync</c> is .NET 5+.</summary>
    public static Task WaitForExitAsync(Process process, CancellationToken cancellationToken)
    {
#if NET472
        var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        process.EnableRaisingEvents = true;
        process.Exited += (_, _) => tcs.TrySetResult(true);
        // Exited only fires for events armed before the process ended.
        if (process.HasExited) tcs.TrySetResult(true);
        if (!cancellationToken.CanBeCanceled) return tcs.Task;

        var registration = cancellationToken.Register(() => tcs.TrySetCanceled(cancellationToken));
        return tcs.Task.ContinueWith(
            t =>
            {
                registration.Dispose();
                return t;
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default).Unwrap();
#else
        return process.WaitForExitAsync(cancellationToken);
#endif
    }

    /// <summary>
    /// Kills the process and its children. <c>Kill(entireProcessTree: true)</c> is
    /// .NET Core 3.0+; on net472 the tree is walked with WMI through taskkill, because
    /// killing `git review` alone would leave the `git` it spawned running.
    /// </summary>
    public static void KillTree(Process process)
    {
#if NET472
        try
        {
            using var killer = Process.Start(new ProcessStartInfo
            {
                FileName = "taskkill",
                Arguments = $"/T /F /PID {process.Id}",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            });
            killer?.WaitForExit(5_000);
        }
        catch
        {
            // taskkill missing or already gone: fall back to the process itself.
        }

        if (!process.HasExited) process.Kill();
#else
        process.Kill(entireProcessTree: true);
#endif
    }

    /// <summary>
    /// Marks a file executable on POSIX. <c>File.SetUnixFileMode</c> is .NET 7+, and
    /// net472 never runs anywhere it would matter.
    /// </summary>
    public static void MakeExecutable(string path)
    {
#if !NET472
        // OperatingSystem.IsWindows() rather than RuntimeInfo: the platform analyzer
        // only reads the BCL guard, and File.SetUnixFileMode is Unix-only.
        if (OperatingSystem.IsWindows()) return;
        try
        {
            File.SetUnixFileMode(
                path,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
        catch
        {
            // best-effort
        }
#endif
    }

#if NET472
    /// <summary>
    /// Quotes one argument the way <c>CommandLineToArgvW</c> parses it back
    /// (dotnet/runtime's PasteArguments): backslashes are only special in front of a
    /// quote, so they are doubled there and left alone everywhere else.
    /// </summary>
    private static void AppendArgument(StringBuilder sb, string argument)
    {
        if (sb.Length != 0) sb.Append(' ');

        if (argument.Length != 0 && argument.IndexOfAny(new[] { ' ', '\t', '"' }) < 0)
        {
            sb.Append(argument);
            return;
        }

        sb.Append('"');
        for (var i = 0; i < argument.Length; i++)
        {
            var backslashes = 0;
            while (i < argument.Length && argument[i] == '\\')
            {
                backslashes++;
                i++;
            }

            if (i == argument.Length)
            {
                // Trailing backslashes precede the closing quote: double them.
                sb.Append('\\', backslashes * 2);
                break;
            }

            if (argument[i] == '"')
            {
                sb.Append('\\', backslashes * 2 + 1);
                sb.Append('"');
            }
            else
            {
                sb.Append('\\', backslashes);
                sb.Append(argument[i]);
            }
        }

        sb.Append('"');
    }
#endif
}
