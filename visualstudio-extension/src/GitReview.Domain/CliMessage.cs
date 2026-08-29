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
}
