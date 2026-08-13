namespace GitReview.Domain;

public sealed record SourcePreferenceLevels(
    string? WorkspaceValue = null,
    string? GlobalValue = null);

public static class SourcePreference
{
    private static readonly HashSet<string> Valid = new(StringComparer.Ordinal)
    {
        "remote", "local", "offline",
    };

    private static ReviewSource? AsSource(string? value) =>
        value is not null && Valid.Contains(value) ? ReviewSourceExt.Parse(value) : null;

    /// <summary>Workspace wins over user; default remote.</summary>
    public static ReviewSource ResolveDefaultSource(SourcePreferenceLevels levels) =>
        AsSource(levels.WorkspaceValue) ?? AsSource(levels.GlobalValue) ?? ReviewSource.Remote;
}
