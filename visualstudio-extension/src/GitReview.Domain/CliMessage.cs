namespace GitReview.Domain;

public static class CliMessage
{
    public static string FlattenCliMessage(string text) =>
        string.Join(" ",
            text.Split('\n')
                .Select(l => l.Trim())
                .Where(l => l.Length > 0));

    public static string FirstCliLine(string text) =>
        text.Split('\n')
            .Select(l => l.Trim())
            .FirstOrDefault(l => l.Length > 0) ?? "";

    public static string CliErrorText(string stderr, string stdout, string fallback)
    {
        var err = FlattenCliMessage(stderr);
        if (err.Length > 0) return err;
        var output = FlattenCliMessage(stdout);
        if (output.Length > 0) return output;
        return fallback;
    }

    /// <summary>
    /// What a draft verb has to say once it succeeded, in one message: first what
    /// it did, then its notes.
    ///
    /// The outcome comes on <b>stdout</b>, which is where this project puts the
    /// result of every verb (start, finish, forget…), leaving stderr for errors and
    /// notes. Reading stderr alone — which this path used to do — dropped the only
    /// sentence that answers what happened: an update says "N kept, M added, K
    /// dropped", and without it pressing the offer produced no signal at all. On a
    /// branch with no note nothing appeared; on one with a note (the authoring-guide
    /// hint) what appeared had nothing to do with what had just been pressed.
    /// </summary>
    public static string DraftOutcomeText(string stdout, string stderr) =>
        string.Join(" — ",
            new[] { FlattenCliMessage(stdout), FlattenCliMessage(stderr) }
                .Where(p => p.Length > 0));
}
