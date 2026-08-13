using System.Text.RegularExpressions;

namespace GitReview.Domain;

public enum StartFailureCategory
{
    Network,
    Repository,
}

public static class StartFailure
{
    private static readonly string[] NetworkMarkers =
    {
        "could not resolve host",
        "could not read from remote repository",
        "connection timed out",
        "connection refused",
        "unable to access",
        "could not read username",
        "could not read password",
        "authentication failed",
        "permission denied (publickey)",
        "terminal prompts disabled",
    };

    public static StartFailureCategory ClassifyStartFailure(string stderr)
    {
        var text = stderr.ToLowerInvariant();
        return NetworkMarkers.Any(m => text.Contains(m, StringComparison.Ordinal))
            ? StartFailureCategory.Network
            : StartFailureCategory.Repository;
    }

    /// <summary>
    /// Quote an argument for pasting into an integrated terminal.
    /// platform "win32" for PowerShell-style, anything else POSIX.
    /// </summary>
    public static string QuoteForTerminal(string value, string platform = "linux")
    {
        if (platform == "win32")
        {
            if (Regex.IsMatch(value, @"^[\w./\\-]+$") && !value.StartsWith('-'))
                return value;
            return "'" + value.Replace("'", "''") + "'";
        }
        return Regex.IsMatch(value, @"^[\w./][\w./-]*$")
            ? value
            : "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}
