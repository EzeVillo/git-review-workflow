namespace GitReview.Domain;

/// <summary>
/// Which rows a filtered picker shows, and which one ends up selected — the part of the
/// dialog that can be asked without standing up WPF.
///
/// A row is never <em>its</em> visible position: what comes back is the index into the
/// caller's list, so filtering cannot change what a selection means. The free-text row is
/// the only one with no index there, which is why it carries <see cref="Typed"/>.
/// </summary>
public static class PickerRows
{
    /// <summary>The free-text row, which is in no list.</summary>
    public const int Typed = -2;

    /// <summary>No row selected.</summary>
    public const int None = -1;

    /// <summary>
    /// The indices of <paramref name="options"/> that survive <paramref name="needle"/>, in
    /// order. With <paramref name="freeText"/> and a needle that is not already an option,
    /// the free-text row goes first.
    /// </summary>
    public static IReadOnlyList<int> Rows(
        IReadOnlyList<string> options,
        string needle,
        bool freeText)
    {
        var trimmed = (needle ?? string.Empty).Trim();
        var result = new List<int>();
        if (freeText && trimmed.Length > 0 && !options.Contains(trimmed, StringComparer.Ordinal))
        {
            result.Add(Typed);
        }

        for (var i = 0; i < options.Count; i++)
        {
            if (trimmed.Length == 0
                || options[i].IndexOf(trimmed, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                result.Add(i);
            }
        }

        return result;
    }

    /// <summary>
    /// Which visible row ends up selected, given <paramref name="keep"/> (the index into
    /// the options that was selected before filtering, or <see cref="None"/>).
    ///
    /// With a free-text row in front it is the one that wins: keeping the previous
    /// selection left the reviewer typing a SHA with a branch selected, and accepting sent
    /// the branch. Picking from the list is one arrow key away, and visible; Enter sending
    /// something else is not.
    /// </summary>
    public static int Selection(IReadOnlyList<int> rows, int keep)
    {
        if (rows.Count == 0) return None;
        if (rows[0] == Typed) return 0;
        if (keep != None && keep != Typed)
        {
            for (var i = 0; i < rows.Count; i++)
            {
                if (rows[i] == keep) return i;
            }
        }

        return 0;
    }
}
