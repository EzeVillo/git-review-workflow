namespace GitReview.Domain;

public static class EntryArg
{
    public static EntryRecord? ResolveEntryArg(
        object? arg,
        IReadOnlyList<EntryRecord> entries,
        int? position)
    {
        if (arg is null)
            return entries.FirstOrDefault(e => e.Position == position);
        if (arg is EntryRecord er)
            return er;
        return null;
    }
}
