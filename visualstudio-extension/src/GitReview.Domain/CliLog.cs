using System.Text.RegularExpressions;

namespace GitReview.Domain;

public static class CliLog
{
    public const int StderrMax = 2000;

    public static string ShellQuoteArg(string arg)
    {
        if (arg.Length == 0) return "\"\"";
        if (Regex.IsMatch(arg, @"[\s""\\]"))
            return "\"" + arg.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        return arg;
    }

    public static string FormatCommandLine(string command, IReadOnlyList<string> args) =>
        string.Join(" ", new[] { command }.Concat(args.Select(ShellQuoteArg)));

    public sealed record CliLogEnd(
        int? ExitCode,
        string? ErrorCode,
        long DurationMs,
        string Stderr,
        bool TimedOut = false);

    public static IReadOnlyList<string> FormatCliEnd(CliLogEnd result)
    {
        var ms = $"{result.DurationMs}ms";
        if (result.TimedOut)
            return new[] { $"← timed out after {ms} (killed)" };
        if (result.ErrorCode is not null)
            return new[] { $"← spawn failed {result.ErrorCode}  {ms}" };
        var line = $"← exit {result.ExitCode?.ToString() ?? "null"}  {ms}";
        if (result.ExitCode == 0)
            return new[] { line };
        var lines = new List<string> { line };
        var err = result.Stderr.TrimEnd();
        if (err.Length == 0) return lines;
        var body = err.Length > StderrMax
            ? err[..StderrMax] + "\n… (truncated)"
            : err;
        foreach (var part in body.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
            lines.Add($"  {part}");
        return lines;
    }
}
