namespace GitReview.Domain;

public sealed record CommentRow(string Tag, IReadOnlyList<string> Fields);
public sealed record CommentDocument(string Path, string Context, string Kind, string Presence, string Revision, int? Count = null);
public sealed record CommentsReport(IReadOnlyList<CommentRow> Rows, bool Loading = false)
{
    public IEnumerable<IReadOnlyList<string>> Records(string tag) => Rows.Where(r => r.Tag == tag).Select(r => r.Fields);
    public IReadOnlyList<string> Destinations(string operation = "add") => Records("comments-capability").Where(r => r[0] == operation && (r[1] == "local" || r[1] == "shared")).Select(r => r[1]).Distinct().ToArray();
    public string? Guard => Records("comments-guard").FirstOrDefault()?.FirstOrDefault();
    public bool SupportsAddReply => Records("comments-add-reply").Any(r => r[0] == "1");
    public IReadOnlyList<CommentDocument> Documents => Records("comments-document").Where(f => f.Count >= 5).Select(f => {
        var count = Records("comments-count").FirstOrDefault(c => c.Count >= 2 && c[0] == f[0]);
        return new CommentDocument(f[0], f[1], f[2], f[3], f[4], count is not null && int.TryParse(count[1], out var n) && n >= 0 ? n : null);
    }).ToArray();
}
public sealed record CommentsAddReply(string Before, string After, CommentsReport Report);

public static class Comments
{
    public static CommentsAddReply? ParseAddReply(string text, string document)
    {
        var lines = text.TrimEnd('\r', '\n').Split('\n').Select(line => line.TrimEnd('\r')).ToArray();
        var header = lines[0].Split('\t');
        bool Token(string? value) => value is not null && (value.Length == 40 || value.Length == 64) &&
            value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
        if (header.Length != 4 || header[0] != "comments-add-result" || header[1] != "1" ||
            !Token(header[2]) || !Token(header[3]) || lines[lines.Length - 1] != "comments-add-result-end\t1") return null;
        var report = Parse(string.Join("\n", lines.Skip(1).Take(lines.Length - 2)));
        var active = report.Records("comments-context").Where(row => row[2] == "active").ToArray();
        if (!Token(report.Guard) || active.Length != 1 || active[0][3] != report.Guard ||
            report.Records("comments-identity").FirstOrDefault()?[0] != "resolved" ||
            !report.Documents.Any(d => d.Kind == document && d.Context == active[0][0] && d.Presence == "present" && Token(d.Revision) && d.Count > 0)) return null;
        return new CommentsAddReply(header[2], header[3], report);
    }

    public static IReadOnlyList<CommentDocument> OwnedBy(CommentsReport report, IReadOnlyCollection<string> owners)
    {
        var contexts=new HashSet<string>(report.Records("comments-owner").Where(r=>r.Count>=3 && owners.Contains(r[2])).Select(r=>r[0]));
        return report.Documents.Where(d=>contexts.Contains(d.Context)).ToArray();
    }
    public static (int First, int Last) SelectionLines(int anchorLine, int anchorColumn, int caretLine, int caretColumn)
    {
        var forward = anchorLine < caretLine || anchorLine == caretLine && anchorColumn <= caretColumn;
        var first = forward ? anchorLine : caretLine;
        var last = forward ? caretLine : anchorLine;
        var column = forward ? caretColumn : anchorColumn;
        return (first+1, Math.Max(first+1, last + (last>first && column==0 ? 0 : 1)));
    }
    // 1-based UTF-16 endpoints. The end is exclusive when columns are present.
    public static (int First, int Last, int StartColumn, int EndColumn) SelectionCoordinates(int anchorLine, int anchorColumn, int caretLine, int caretColumn)
    {
        var forward = anchorLine < caretLine || anchorLine == caretLine && anchorColumn <= caretColumn;
        return forward ? (anchorLine+1, caretLine+1, anchorColumn+1, caretColumn+1) : (caretLine+1, anchorLine+1, caretColumn+1, anchorColumn+1);
    }
    public static (int Start, int End) TextOffsets(string text, int first, int last, int? startColumn = null, int? endColumn = null)
    {
        var lines = text.Split('\n');
        if (first < 1 || last < first || last > lines.Length) throw new InvalidOperationException(CommentsCopy.rangeUnavailable);
        var precise = startColumn.HasValue || endColumn.HasValue;
        var start = precise ? (startColumn ?? 0)-1 : 0;
        var end = precise ? (endColumn ?? 0)-1 : lines[last-1].TrimEnd('\r').Length;
        if (start < 0 || end < 0 || start > lines[first-1].TrimEnd('\r').Length || end > lines[last-1].TrimEnd('\r').Length || (precise && first == last && start >= end)) throw new InvalidOperationException(CommentsCopy.rangeUnavailable);
        return (lines.Take(first-1).Sum(l=>l.Length+1)+start, lines.Take(last-1).Sum(l=>l.Length+1)+end);
    }
    private static readonly IReadOnlyDictionary<string, int> Fields = new Dictionary<string, int> {
        ["comments-capability"]=2, ["comments-add-reply"]=1, ["comments-owner"]=2, ["comments-context"]=5, ["comments-guard"]=1, ["comments-document"]=5, ["comments-count"]=2,
        ["comments-diagnostic"]=3, ["comments-identity"]=2, ["comments-candidate"]=2, ["comments-delivery"]=3,
        ["comments-capture"]=3, ["comment-body"]=2, ["comment-scope"]=3, ["comment-entry"]=4, ["comment-version"]=3, ["comment-path"]=3,
        ["comment-location"]=4, ["comment-columns"]=4, ["comment-unversioned"]=1, ["comment-diagnostic"]=3, ["comment-diff"]=3,
        ["comment-blob"]=3, ["comments-delivery-file"]=4,
    };
    public static CommentsReport Parse(string text) => new(text.Split('\n').Select(line => line.TrimEnd('\r').Split('\t'))
        .Where(f => Fields.TryGetValue(f[0], out var min) && f.Length > min)
        .Select(f => new CommentRow(f[0], f.Skip(1).ToArray())).ToArray());

    public static IReadOnlyList<string> Argv(CommentsReport report, string operation, string? document = null, string? context = null, int? ordinal = null)
    {
        var args = new List<string> { operation };
        if (document is not null && operation != "prepare") args.AddRange(new[]{"--document", document});
        if (context is not null) args.AddRange(new[]{"--context", context});
        if (operation == "entries") {args.Add("--porcelain"); return args;}
        var guard = (context is null ? null : report.Records("comments-context").FirstOrDefault(c => c[0] == context)?[3]) ?? report.Guard;
        if (string.IsNullOrEmpty(guard)) throw new InvalidOperationException(UserCopy.Stale);
        args.AddRange(new[]{"--expect-context", guard!});
        foreach (var kind in operation == "save" ? new[]{"local", "shared"} : new[]{document ?? "shared"})
        {
            var row = report.Documents.FirstOrDefault(d => d.Kind == kind && (context is null || d.Context == context));
            if (row?.Revision == "unreadable") throw new InvalidOperationException(CommentsCopy.unreadable);
            args.AddRange(new[]{operation == "save" ? "--expect-" + kind : "--expect-document", row?.Revision ?? "absent"});
        }
        if (ordinal.HasValue) args.AddRange(new[]{"--entry", ordinal.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)});
        return args;
    }
}
public sealed record CommentCapture(string Path, string Side, int First, int Last, bool Unversioned, string? Base = null, string? Head = null, string? BasePath = null, string? HeadPath = null, bool HasSelection = false, string Snippet = "", bool IncludeLines = true, int? StartColumn = null, int? EndColumn = null)
{
    public string RangeLabel => StartColumn.HasValue && EndColumn.HasValue ? $"{First}:{StartColumn}–{Last}:{EndColumn}" : $"{First}–{Last}";
}
