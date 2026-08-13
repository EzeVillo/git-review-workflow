namespace GitReview.Domain;

public static class CliProbe
{
    public const long CliProbeIntervalMs = 10_000;

    public static bool ShouldProbeCli(Situation situation, bool panelVisible) =>
        panelVisible && situation is Situation.CliMissing or Situation.CliOutdated;
}
