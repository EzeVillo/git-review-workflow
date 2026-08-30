namespace GitReview.Domain;

/// <summary>
/// What one `git review --version` run found, which is three things and not two:
/// between "it is there and answers" and "it is not there" lives "could not tell".
/// Startup is where the third one shows up — the shell is still coming up, the disk
/// is busy, the process is slow or dies without saying why — and reading it as
/// absence is what put the install-the-CLI screen on top of a CLI that was installed.
/// </summary>
public enum CliVerdict
{
    Ok,
    Missing,
    Unknown,
}

public static class CliProbe
{
    public const long CliProbeIntervalMs = 10_000;

    /// <summary>
    /// Retries of the probe on an <see cref="CliVerdict.Unknown"/> verdict, before
    /// publishing anything. The panel stays on its waiting surface meanwhile: a slower
    /// startup costs less than a screen that has to be taken back ten seconds later.
    /// Bounded on purpose — an answer that never comes still has to end up as something.
    /// </summary>
    public const int CliProbeRetries = 2;

    public const int CliProbeRetryDelayMs = 400;

    /// <summary>
    /// What a shell or the CLR says when the executable really is not there. Matched
    /// lowercased and as a substring: the point is the evidence, not each host's exact
    /// wording.
    /// </summary>
    private static readonly string[] AbsenceMarkers =
    {
        "is not a git command",
        "not found",
        "no such file",
        "cannot find",
        "enoent",
        "error=2",
        "win32exception",
        "filenotfoundexception",
    };

    public static bool ShouldProbeCli(Situation situation, bool panelVisible) =>
        panelVisible && situation is Situation.CliMissing or Situation.CliOutdated;

    /// <summary>
    /// Classifies one version probe. The only evidence of absence is a failure that
    /// NAMES it; a timeout is the opposite of a missing CLI (a process that does not
    /// exist does not take long not to exist), and any other exit code without that
    /// text says nothing on its own. Ok means the CLI answered, not that it said its
    /// version — stdout is not part of this at all: a build that prints the version
    /// somewhere else carries on to the status.
    /// </summary>
    public static CliVerdict VersionVerdict(
        string stderr,
        int? exitCode,
        string? errorCode = null,
        bool timedOut = false)
    {
        if (timedOut) return CliVerdict.Unknown;
        if (errorCode is not null || exitCode is not 0)
        {
            // The spawn's error code and stderr are the same fact read by different
            // hosts (Node says ENOENT where the CLR says Win32Exception), so the
            // evidence is looked for in both.
            return NamesAbsence($"{errorCode} {stderr}") ? CliVerdict.Missing : CliVerdict.Unknown;
        }

        return CliVerdict.Ok;
    }

    private static bool NamesAbsence(string text)
    {
        var lower = text.ToLowerInvariant();
        foreach (var marker in AbsenceMarkers)
        {
            if (lower.Contains(marker)) return true;
        }

        return false;
    }
}
