namespace GitReview.Domain;

/// <summary>
/// Minimum CLI version that ships the porcelain contract used by this client.
/// Keep in sync with contracts/client-product-surface.yaml (anti-drift CI).
/// </summary>
public static class CliVersion
{
    public const string MinCliVersion = "0.6.0";

    private static (int, int, int)? ParseVersion(string version)
    {
        var parts = version.Trim().Split('.');
        if (parts.Length != 3) return null;
        if (!int.TryParse(parts[0], out var a) || a < 0) return null;
        if (!int.TryParse(parts[1], out var b) || b < 0) return null;
        if (!int.TryParse(parts[2], out var c) || c < 0) return null;
        return (a, b, c);
    }

    /// <summary>
    /// Compares two X.Y.Z versions. Negative if a &lt; b, positive if a &gt; b,
    /// zero if equal. null if either is not X.Y.Z with non-negative integers.
    /// </summary>
    public static int? CompareVersions(string a, string b)
    {
        var va = ParseVersion(a);
        var vb = ParseVersion(b);
        if (va is null || vb is null) return null;
        if (va.Value.Item1 != vb.Value.Item1) return va.Value.Item1 - vb.Value.Item1;
        if (va.Value.Item2 != vb.Value.Item2) return va.Value.Item2 - vb.Value.Item2;
        return va.Value.Item3 - vb.Value.Item3;
    }

    /// <summary>true if version is older than minVersion or has an invalid format.</summary>
    public static bool IsOutdated(string version, string minVersion = MinCliVersion)
    {
        var cmp = CompareVersions(version, minVersion);
        return cmp is null or < 0;
    }
}
