namespace GitReview.Domain;

public enum ReviewMode
{
    Whole,
    Step,
    Walk,
}

public static class ReviewModeExt
{
    public static string Id(this ReviewMode m) => m switch
    {
        ReviewMode.Whole => "whole",
        ReviewMode.Step => "step",
        ReviewMode.Walk => "walk",
        _ => throw new ArgumentOutOfRangeException(nameof(m)),
    };

    public static ReviewMode? Parse(string? field) => field switch
    {
        "whole" => ReviewMode.Whole,
        "step" => ReviewMode.Step,
        "walk" => ReviewMode.Walk,
        _ => null,
    };
}

public enum WalkthroughStatus
{
    None,
    Applied,
    Degraded,
}

public static class WalkthroughStatusExt
{
    public static string Id(this WalkthroughStatus s) => s switch
    {
        WalkthroughStatus.None => "none",
        WalkthroughStatus.Applied => "applied",
        WalkthroughStatus.Degraded => "degraded",
        _ => throw new ArgumentOutOfRangeException(nameof(s)),
    };

    public static WalkthroughStatus? Parse(string? field) => field switch
    {
        "none" => WalkthroughStatus.None,
        "applied" => WalkthroughStatus.Applied,
        "degraded" => WalkthroughStatus.Degraded,
        _ => null,
    };
}

public sealed record StateRecord(
    string Branch,
    string Source,
    string Tip,
    ReviewMode Mode,
    WalkthroughStatus Walkthrough,
    int? Position = null,
    int? Total = null,
    int? Recorded = null,
    /// <summary>Short SHA (step) or PathRef (walk).</summary>
    object? Current = null,
    bool? Essential = null);

public sealed record EntryRecord(
    int Position,
    /// <summary>Short SHA (step) or PathRef (walk/whole).</summary>
    object Id,
    bool? Essential = null,
    bool? Annotated = null,
    bool? Banked = null);

public sealed record StatusFinishRecord(
    string State = "conflict",
    bool Onto = false);

public sealed record PorcelainResult(
    StateRecord State,
    IReadOnlyList<EntryRecord> Entries,
    IReadOnlyList<EntryRecord>? Files = null,
    StatusFinishRecord? Finish = null,
    bool? Readonly = null,
    bool? KeysOnly = null,
    bool? Draft = null,
    /// <summary>
    /// 012: the absolute path of that draft, as the CLI reported it in the
    /// record's field. Separate from the flag: presence is presence, and a
    /// record without the field (an older CLI) does not turn the mark off.
    /// </summary>
    string? DraftPath = null,
    IReadOnlyDictionary<int, string>? Subjects = null,
    IReadOnlyDictionary<int, string>? Authors = null,
    string? Base = null)
{
    public IReadOnlyList<EntryRecord> FilesList => Files ?? Array.Empty<EntryRecord>();
}

public sealed record BranchFinish(string State, bool Onto);

public sealed record BranchRecord(
    string Name,
    bool Saved,
    bool Current,
    bool Orphan,
    ReviewMode? Mode = null,
    int? Position = null,
    int? Total = null,
    BranchFinish? Finish = null);

public static class Porcelain
{
    private static bool ToBool(string? field) => field == "1";

    private static int ToInt(string? field) =>
        int.TryParse(field, out var n) ? n : 0;

    private static int? ToOptionalInt(string? field)
    {
        if (string.IsNullOrEmpty(field)) return null;
        return int.TryParse(field, out var n) ? n : null;
    }

    /// <summary>
    /// Free-text field: everything after the skip-th tab (subject/author may contain literal tabs).
    /// </summary>
    private static string? RestAfterTab(string line, int skip)
    {
        var index = -1;
        for (var k = 0; k < skip; k++)
        {
            index = line.IndexOf('\t', index + 1);
            if (index == -1) return null;
        }
        return line[(index + 1)..];
    }

    /// <summary>
    /// Tokenizes <c>git review status --porcelain</c>. Mode on the state record is read
    /// first and decides arity of following lines.
    /// </summary>
    public static PorcelainResult ParsePorcelain(string stdout)
    {
        var lines = stdout.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None)
            .Where(l => l.Length > 0)
            .ToList();
        if (lines.Count == 0)
            throw new ArgumentException("porcelain output has no state record");

        StateRecord? state = null;
        var entries = new List<EntryRecord>();
        var files = new List<EntryRecord>();
        Dictionary<int, string>? subjects = null;
        Dictionary<int, string>? authors = null;
        string? bas = null;
        StatusFinishRecord? finish = null;
        bool? isReadonly = null;
        bool? isKeysOnly = null;
        bool? isDraft = null;
        string? draftPath = null;

        foreach (var line in lines)
        {
            var fields = line.Split('\t');
            switch (fields[0])
            {
                case "state":
                {
                    var mode = ReviewModeExt.Parse(Get(fields, 4))
                        ?? throw new ArgumentException(
                            $"porcelain state has invalid mode: {(Get(fields, 4) is { } m ? $"\"{m}\"" : "(missing)")}");
                    var walkthrough = WalkthroughStatusExt.Parse(Get(fields, 5))
                                      ?? WalkthroughStatus.None;
                    StateRecord record;
                    if (mode is ReviewMode.Step or ReviewMode.Walk)
                    {
                        object? current = mode == ReviewMode.Walk
                            ? Unquote.ToPathRef(Get(fields, 9) ?? "")
                            : Get(fields, 9);
                        record = new StateRecord(
                            Branch: Get(fields, 1) ?? "",
                            Source: Get(fields, 2) ?? "",
                            Tip: Get(fields, 3) ?? "",
                            Mode: mode,
                            Walkthrough: walkthrough,
                            Position: ToInt(Get(fields, 6)),
                            Total: ToInt(Get(fields, 7)),
                            Recorded: ToInt(Get(fields, 8)),
                            Current: current,
                            Essential: mode == ReviewMode.Walk ? ToBool(Get(fields, 10)) : null);
                    }
                    else
                    {
                        record = new StateRecord(
                            Branch: Get(fields, 1) ?? "",
                            Source: Get(fields, 2) ?? "",
                            Tip: Get(fields, 3) ?? "",
                            Mode: mode,
                            Walkthrough: walkthrough);
                    }
                    state = record;
                    break;
                }
                case "entry":
                {
                    var st = state ?? throw new ArgumentException("entry record before state record");
                    var position = ToInt(Get(fields, 1));
                    var rawId = Get(fields, 2) ?? "";
                    object id = st.Mode == ReviewMode.Step ? rawId : Unquote.ToPathRef(rawId);
                    EntryRecord entry = st.Mode switch
                    {
                        ReviewMode.Walk => new EntryRecord(
                            position, id,
                            Essential: ToBool(Get(fields, 3)),
                            Annotated: ToBool(Get(fields, 4))),
                        ReviewMode.Step => new EntryRecord(
                            position, id,
                            Banked: ToBool(Get(fields, 3))),
                        _ => new EntryRecord(position, id),
                    };
                    entries.Add(entry);
                    break;
                }
                case "file":
                {
                    if (state is null) throw new ArgumentException("file record before state record");
                    var position = ToInt(Get(fields, 1));
                    var rawPath = Get(fields, 2);
                    if (string.IsNullOrEmpty(rawPath)) continue;
                    files.Add(new EntryRecord(position, Unquote.ToPathRef(rawPath)));
                    break;
                }
                case "subject":
                case "author":
                {
                    var position = ToOptionalInt(Get(fields, 1));
                    var text = RestAfterTab(line, 2);
                    if (position is null || text is null) continue;
                    if (fields[0] == "subject")
                    {
                        subjects ??= new Dictionary<int, string>();
                        subjects[position.Value] = text;
                    }
                    else
                    {
                        authors ??= new Dictionary<int, string>();
                        authors[position.Value] = text;
                    }
                    break;
                }
                case "base":
                {
                    var text = RestAfterTab(line, 1);
                    if (text is not null) bas = text;
                    break;
                }
                case "finish":
                {
                    if (Get(fields, 1) == "conflict")
                        finish = new StatusFinishRecord(Onto: ToBool(Get(fields, 2)));
                    break;
                }
                case "readonly":
                    isReadonly = true;
                    break;
                case "keys":
                    isKeysOnly = true;
                    break;
                case "draft":
                    isDraft = true;
                    if (!string.IsNullOrEmpty(Get(fields, 1))) draftPath = Get(fields, 1);
                    break;
                // unknown tag: ignore (FR-003)
            }
        }

        var stFinal = state ?? throw new ArgumentException("porcelain output has no state record");
        return new PorcelainResult(
            State: stFinal,
            Entries: entries,
            Files: files,
            Finish: finish,
            Readonly: isReadonly,
            KeysOnly: isKeysOnly,
            Draft: isDraft,
            DraftPath: draftPath,
            Subjects: subjects,
            Authors: authors,
            Base: bas);
    }

    /// <summary>Source name of a review branch: strips review-saved/ or review/ prefix.</summary>
    public static string SourceOf(BranchRecord branch)
    {
        foreach (var prefix in new[] { "review-saved/", "review/" })
        {
            if (branch.Name.StartsWith(prefix, StringComparison.Ordinal))
                return branch.Name[prefix.Length..];
        }
        return branch.Name;
    }

    /// <summary>Tokenizes <c>git review list --porcelain</c>. Empty output is valid.</summary>
    public static IReadOnlyList<BranchRecord> ParseListPorcelain(string stdout)
    {
        var branches = new List<BranchRecord>();
        var finishByBranch = new Dictionary<string, BranchFinish>();

        foreach (var line in stdout.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
        {
            if (line.Length == 0) continue;
            var fields = line.Split('\t');
            switch (fields[0])
            {
                case "finish":
                {
                    var branchName = Get(fields, 1);
                    var state = Get(fields, 2);
                    if (branchName is not null && (state == "pending" || state == "conflict"))
                        finishByBranch[branchName] = new BranchFinish(state, ToBool(Get(fields, 3)));
                    break;
                }
                case "branch":
                {
                    var orphan = ToBool(Get(fields, 4));
                    int? pos = null;
                    int? tot = null;
                    ReviewMode? mode = null;
                    if (!orphan)
                    {
                        mode = ReviewModeExt.Parse(Get(fields, 5) ?? "whole");
                        var p = ToOptionalInt(Get(fields, 6));
                        var t = ToOptionalInt(Get(fields, 7));
                        if (p is not null && t is not null)
                        {
                            pos = p;
                            tot = t;
                        }
                    }
                    branches.Add(new BranchRecord(
                        Name: Get(fields, 1) ?? "",
                        Saved: ToBool(Get(fields, 2)),
                        Current: ToBool(Get(fields, 3)),
                        Orphan: orphan,
                        Mode: mode,
                        Position: pos,
                        Total: tot));
                    break;
                }
            }
        }

        return branches.Select(b =>
            finishByBranch.TryGetValue(b.Name, out var f) ? b with { Finish = f } : b
        ).ToList();
    }

    private static string? Get(string[] fields, int i) =>
        i < fields.Length ? fields[i] : null;
}
