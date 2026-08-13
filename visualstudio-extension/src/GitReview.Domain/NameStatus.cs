namespace GitReview.Domain;

/// <summary>
/// A file touched by a commit, with resolved before/after paths.
/// null means the file does not exist on that side.
/// </summary>
public sealed record CommitChange(string Path, string? Before, string? After);

public static class NameStatus
{
    /// <summary>
    /// Parses <c>git diff-tree -z --name-status</c> / <c>git diff --name-status -z</c> output.
    /// With -z, git never quotes paths.
    /// </summary>
    public static IReadOnlyList<CommitChange> ParseNameStatus(string output)
    {
        var fields = output.Split('\0').Where(f => f.Length > 0).ToList();
        var changes = new List<CommitChange>();
        var i = 0;
        while (i < fields.Count)
        {
            var code = fields[i].Length > 0 ? fields[i][0] : '\0';
            if (code is 'R' or 'C')
            {
                if (i + 2 >= fields.Count) break;
                var from = fields[i + 1];
                var to = fields[i + 2];
                changes.Add(new CommitChange(to, from, to));
                i += 3;
                continue;
            }
            if (i + 1 >= fields.Count) break;
            var path = fields[i + 1];
            changes.Add(new CommitChange(
                path,
                Before: code == 'A' ? null : path,
                After: code == 'D' ? null : path));
            i += 2;
        }
        return changes;
    }
}
