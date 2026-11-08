namespace GitReview.Domain;

public sealed record SaveReply(string List, string Config)
{
    public static bool Supported(string output) => output.Replace("\r\n", "\n").Split('\n').Count(x => x == "capability\tsave-state") == 1;
    public static SaveReply? Parse(string output)
    {
        var lines = output.Replace("\r\n", "\n").Split('\n').ToList();
        if (lines.Count > 0 && lines[lines.Count - 1] == "") lines.RemoveAt(lines.Count - 1);
        if (lines.Count < 5 || lines[0] != "save-state\t1" || lines[1] != "status\t2" ||
            lines[lines.Count - 1] != "save-state\tcomplete") return null;
        var list = new List<string>();
        var config = new List<string>();
        foreach (var line in lines.Skip(2).Take(lines.Count - 3))
        {
            if (line.StartsWith("list\t", StringComparison.Ordinal) && config.Count == 0) list.Add(line.Substring(5));
            else if (line.StartsWith("config\t", StringComparison.Ordinal)) config.Add(line.Substring(7));
            else return null;
        }
        if (!list.Any(x => System.Text.RegularExpressions.Regex.IsMatch(x, "^branch\t[^\t]+\t1\t")) ||
            config.Count(x => x.StartsWith("config\tremote\t", StringComparison.Ordinal)) != 1) return null;
        return new SaveReply(string.Join("\n", list) + "\n", string.Join("\n", config) + "\n");
    }
}
