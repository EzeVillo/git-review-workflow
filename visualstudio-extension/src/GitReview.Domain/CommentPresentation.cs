namespace GitReview.Domain;

public sealed record CommentPresentation(int Ordinal, string Label, string Body, string Location, string Version, string Preview, string Warning = "", bool CanOpenDiff = false);
public static class CommentPresentations
{
    public static string Decode(string value) => System.Text.RegularExpressions.Regex.Replace(value, "%(25|09|0D|0A|3E)", m => m.Groups[1].Value switch { "25" => "%", "09" => "\t", "0D" => "\r", "0A" => "\n", _ => ">" });
    public static CommentPresentation Present(CommentsReport report, IReadOnlyList<string> entry)
    {
        IEnumerable<IReadOnlyList<string>> Rows(string tag) => report.Records(tag).Where(r => r[0] == entry[0]);
        var body = string.Join("\n", Rows("comment-body").Select(r => Decode(r[1])).SkipWhile(string.IsNullOrWhiteSpace).Reverse().SkipWhile(string.IsNullOrWhiteSpace).Reverse());
        var scope = Rows("comment-scope").FirstOrDefault();
        var line = Rows("comment-location").FirstOrDefault();
        var columns = Rows("comment-columns").FirstOrDefault();
        var side = scope?[2] ?? line?[1];
        var path = Rows("comment-path").FirstOrDefault(r => r[1] == side)?[2];
        var location = scope?[1] == "general" ? CommentsCopy.general : path is null ? CommentsCopy.locationUnavailable :
            Decode(path) +
            (line is null ? "" : ":" + line[2] + (columns is null ? "" : ":" + columns[2]) + "–" + line[3] + (columns is null ? "" : ":" + columns[3])) + " · " + (side == "base" ? CommentsCopy.baseSide : CommentsCopy.headSide);
        var version = Rows("comment-version").FirstOrDefault();
        string Short(string value) => value.Substring(0, Math.Min(8, value.Length));
        var title = entry[3] == (path is null ? location : Decode(path)) ? location : entry[3] + " · " + location;
        return new CommentPresentation(int.Parse(entry[0]), entry[1] + ". " + title, body.Length == 0 ? CommentsCopy.noBody : body, location,
            (version is null ? "" : CommentsCopy.originalChanges + " · " + Short(version[1]) + " → " + Short(version[2])),
            ShortPreview(body), Rows("comment-unversioned").Any() ? CommentsCopy.originalUnversioned : "", scope?[1] != "general" && path is not null);
    }
    private static string ShortPreview(string body) {
        var text = System.Text.RegularExpressions.Regex.Replace(body, "\\s+", " ").Trim();
        var count = 0;
        var end = 0;
        for (var i = 0; i < text.Length; i++, count++) {
            if (count == 159) end = i;
            if (char.IsHighSurrogate(text[i]) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1])) i++;
        }
        return count > 160 ? text.Substring(0, end) + "…" : text;
    }
}
