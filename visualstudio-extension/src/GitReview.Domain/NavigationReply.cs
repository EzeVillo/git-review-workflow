namespace GitReview.Domain;

public static class NavigationReply
{
    private static string[] Lines(string output) => output.Split('\n').Select(l => l.TrimEnd('\r')).ToArray();
    public static bool Supported(string output) => Lines(output).Count(l => l == "capability\tnavigation-state") == 1;
    public static bool IsValid(string output)
    {
        var lines = Lines(output);
        if (!Supported(output) || StaleGuard.Parse(output) is null ||
            lines.Count(l => l.StartsWith("state\t", StringComparison.Ordinal)) != 1 ||
            lines.Count(l => l.StartsWith("navigation\t", StringComparison.Ordinal)) != 1 ||
            !lines.Any(l => l is "navigation\tmoved" or "navigation\tunchanged")) return false;
        try
        {
            var parsed = Porcelain.ParsePorcelain(output);
            return parsed.State.Branch.StartsWith("review/", StringComparison.Ordinal) && parsed.Finish is null &&
                parsed.State.Mode is ReviewMode.Walk or ReviewMode.Step;
        }
        catch (Exception) { return false; }
    }
    public static string Notice(string output)
    {
        var notices = Lines(output).Where(l => l.StartsWith("notice\t", StringComparison.Ordinal)).ToArray();
        return notices.Length == 1 ? notices[0].Substring(7) : "";
    }

    public static string? InlineWhy(string output)
    {
        var rows = Lines(output).Select(line => line.Split('\t')).ToArray();
        var headers = rows.Where(row => row[0] == "why").ToArray();
        if (headers.Length != 1 || headers[0].Length != 3) return null;
        var header = headers[0];
        if (!System.Text.RegularExpressions.Regex.IsMatch(header[2], "^(0|[1-9][0-9]*)$") ||
            !int.TryParse(header[2], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var count)) return null;
        var lines = rows.Where(row => row[0] == "why-line").ToArray();
        if (header[1] == "absent") return count == 0 && lines.Length == 0 ? "" : null;
        if (header[1] != "present" || count == 0 || count != lines.Length) return null;
        var result = new System.Text.StringBuilder();
        for (var index = 0; index < lines.Length; index++)
        {
            var row = lines[index];
            if (row.Length != 3 || row[1] != (index+1).ToString(System.Globalization.CultureInfo.InvariantCulture)) return null;
            for (var at = 0; at < row[2].Length; at++)
            {
                var ch = row[2][at];
                if (ch != '\\') result.Append(ch);
                else
                {
                    if (++at == row[2].Length) return null;
                    switch(row[2][at])
                    {
                        case '\\': result.Append('\\'); break;
                        case 't': result.Append('\t'); break;
                        case 'r': result.Append('\r'); break;
                        default: return null;
                    }
                }
            }
            result.Append('\n');
        }
        return result.ToString();
    }
}
