namespace GitReview.Domain;

public sealed record EffectiveConfig(string? Base = null, string Remote = "origin");

public sealed record CandidateBranch(string Name, string Origin, bool Current);

public sealed record CandidateRemote(string Name, bool Current);

public enum DeltaOrigin
{
    Remote,
    Local,
}

public static class DeltaOriginExt
{
    public static string Id(this DeltaOrigin o) => o switch
    {
        DeltaOrigin.Remote => "remote",
        DeltaOrigin.Local => "local",
        _ => throw new ArgumentOutOfRangeException(nameof(o)),
    };

    public static DeltaOrigin? Parse(string? raw) => raw switch
    {
        "remote" => DeltaOrigin.Remote,
        "local" => DeltaOrigin.Local,
        _ => null,
    };
}

public sealed record DeltaRecord(string Name, string Tip, DeltaOrigin Origin);

/// <summary>
/// 011: DRAFT / DRAFT_RESUME are not reading forms but the path to obtain one.
/// </summary>
public enum OfferId
{
    Walk,
    Keys,
    Draft,
    DraftResume,
    Step,
    Whole,
}

public static class OfferIdExt
{
    public static string Id(this OfferId o) => o switch
    {
        OfferId.Walk => "walk",
        OfferId.Keys => "keys",
        OfferId.Draft => "draft",
        OfferId.DraftResume => "draft-resume",
        OfferId.Step => "step",
        OfferId.Whole => "whole",
        _ => throw new ArgumentOutOfRangeException(nameof(o)),
    };

    public static OfferId? Parse(string? raw) => raw switch
    {
        "walk" => OfferId.Walk,
        "keys" => OfferId.Keys,
        "draft" => OfferId.Draft,
        "draft-resume" => OfferId.DraftResume,
        "step" => OfferId.Step,
        "whole" => OfferId.Whole,
        _ => null,
    };
}

public enum OfferRank
{
    Recommended,
    Available,
}

public static class OfferRankExt
{
    public static string Id(this OfferRank r) => r switch
    {
        OfferRank.Recommended => "recommended",
        OfferRank.Available => "available",
        _ => throw new ArgumentOutOfRangeException(nameof(r)),
    };

    public static OfferRank? Parse(string? raw) => raw switch
    {
        "recommended" => OfferRank.Recommended,
        "available" => OfferRank.Available,
        _ => null,
    };
}

public sealed record ReadingOffer(OfferId Id, OfferRank Rank);

/// <summary>
/// With which origin and range a draft was generated, read back out of the
/// instruction block inside the file itself. <c>Unknown</c> when that block was
/// deleted by hand, which is allowed: the flags cannot be replicated then, so
/// the row does not offer "Validate and start" rather than guessing them.
/// </summary>
public enum DraftSource { Remote, Local, Offline, Unknown }

public enum DraftRange { Full, Delta, Unknown }

/// <summary>
/// Whether the review a draft was written for is over (<c>Reviewed</c>) or
/// still ahead of it (<c>Fresh</c>). The CLI decides it by comparing the tip the
/// draft itself was generated against with the marker of the last completed
/// review of that branch; nothing is derived here.
///
/// The file outlives the review either way — clean does not touch prose — so
/// this is not "does it exist": it is where it is drawn and what is offered.
/// </summary>
public enum DraftState { Fresh, Reviewed }

public static class DraftStateExt
{
    /// <summary>
    /// Anything that is not exactly <c>reviewed</c> is Fresh, the missing field
    /// included: a CLI older than this record does not emit it, and there the
    /// panel has to behave as it behaved rather than hide rows over a datum
    /// nobody gave it.
    /// </summary>
    public static DraftState Parse(string? raw) => raw == "reviewed" ? DraftState.Reviewed : DraftState.Fresh;
}

public static class DraftSourceExt
{
    public static DraftSource Parse(string? raw) => raw switch
    {
        "remote" => DraftSource.Remote,
        "local" => DraftSource.Local,
        "offline" => DraftSource.Offline,
        _ => DraftSource.Unknown,
    };
}

public static class DraftRangeExt
{
    public static DraftRange Parse(string? raw) => raw switch
    {
        "full" => DraftRange.Full,
        "delta" => DraftRange.Delta,
        _ => DraftRange.Unknown,
    };
}

/// <summary>
/// A loose walkthrough draft: it exists in the gitdir's ACTIVE namespace, which
/// is to say the reviewer started it and has not paused its review.
///
/// Nothing here is derived: every field comes straight from the CLI. Path in
/// particular — the client opens it and never builds one.
/// </summary>
public sealed record DraftRecord(
    string Src,
    string Path,
    int Annotated,
    int Total,
    DraftSource Source,
    DraftRange Range,
    DraftState State);

/// <summary>Which of the two authoring guides a <c>guide</c> record is about.</summary>
public enum GuideKind
{
    Team,
    Own,
}

/// <summary>
/// What state a guide is in. All three are decided by the CLI and none is
/// inferred here: Empty is not Absent even though both mean "no conventions are
/// being applied" — with the file there what is offered is opening it, not
/// creating it, and discarding it is possible where discarding a missing file is
/// not.
/// </summary>
public enum GuideState
{
    InForce,
    Empty,
    Absent,
}

public static class GuideKindExt
{
    public static GuideKind? Parse(string? raw) => raw switch
    {
        "team" => GuideKind.Team,
        "own" => GuideKind.Own,
        _ => null,
    };
}

public static class GuideStateExt
{
    public static GuideState? Parse(string? raw) => raw switch
    {
        "in-force" => GuideState.InForce,
        "empty" => GuideState.Empty,
        "absent" => GuideState.Absent,
        _ => null,
    };
}

/// <summary>
/// An authoring guide: prose about the CONTENT of a walkthrough (which entries
/// deserve <c>&gt; key</c>, how to write a why, what belongs in the heads-up).
///
/// The client never reads a byte of it — it opens it and nothing else, exactly
/// as with the reviewer's draft. Path comes straight from the CLI: it is opened,
/// never rebuilt.
/// </summary>
public sealed record GuideRecord(
    GuideKind Kind,
    string Path,
    GuideState State);

/// <summary>
/// What state the author's own walkthrough is in against the branch they have
/// checked out. All four are decided by the CLI and none is inferred here — in
/// particular Unknown, which is NOT Stale: with no instruction block (deleting it
/// by hand is legal) the question has no answer, and giving the worse of the two
/// would send someone to redo a reading order that may be perfectly fine.
///
/// Superseded is not Stale either: the file is the walkthrough of a PR already
/// merged into the base, which travelled in with the merge, so nothing about it
/// fell behind — it belongs to another range. What is offered there is starting
/// over, not reconciling.
/// </summary>
public enum WalkthroughState
{
    InSync,
    Stale,
    Superseded,
    Unknown,
    Absent,
}

public static class WalkthroughStateExt
{
    public static WalkthroughState? Parse(string? raw) => raw switch
    {
        "in-sync" => WalkthroughState.InSync,
        "stale" => WalkthroughState.Stale,
        "superseded" => WalkthroughState.Superseded,
        "unknown" => WalkthroughState.Unknown,
        "absent" => WalkthroughState.Absent,
        _ => null,
    };
}

/// <summary>
/// The committed walkthrough of the branch you are standing on, and whether it
/// still describes what the PR changes today.
///
/// It exists because a walkthrough is written when the PR is finished and then
/// the PR keeps moving: review comments come back, three files change, and that
/// is exactly the moment nobody is thinking about the walkthrough. Stale is a
/// "worth looking at", never a verdict — the verdict is build's, which is what
/// the row's control runs.
///
/// Path comes straight from the CLI, like the draft's and the guides': it is
/// opened, never rebuilt.
/// </summary>
public sealed record WalkthroughRecord(
    string Path,
    WalkthroughState State,
    int Annotated,
    int Total);

public sealed record ConfigPorcelainResult(
    EffectiveConfig Config,
    IReadOnlyList<CandidateBranch> Candidates,
    IReadOnlyList<CandidateRemote> Remotes,
    IReadOnlyList<DeltaRecord>? Deltas = null,
    IReadOnlyList<ReadingOffer>? Offers = null,
    IReadOnlyList<DraftRecord>? Drafts = null,
    /// <summary>
    /// Both authoring guides, ALWAYS both and in the CLI's order (team, own),
    /// whether or not either file exists. Absence is reported rather than implied
    /// by silence: without the row the panel could not offer to create the
    /// missing one without rebuilding its path, which is what the reported-path
    /// rule exists to prevent.
    /// </summary>
    IReadOnlyList<GuideRecord>? Guides = null,
    /// <summary>
    /// The author's walkthrough for the branch that is checked out. The CLI emits
    /// the row present or absent — same rule as the guides — so null here means
    /// one thing only: a CLI older than the record.
    /// </summary>
    WalkthroughRecord? Walkthrough = null);

public static class ConfigPorcelain
{
    private static bool ToBool(string? field) => field == "1";

    /// <summary>
    /// A non-negative count, or null: a malformed field invalidates the record.
    /// </summary>
    /// <remarks>
    /// Not a bare int.TryParse. That one is NumberStyles.Integer, which allows a
    /// leading sign and surrounding whitespace, so "-3", "+3" and " 3 " all became
    /// progress pairs -- and the CLI emits none of those, so anything of that shape
    /// is a record this client did not understand. The three clients have to agree
    /// on that or the same porcelain line draws a row in two of them and is dropped
    /// by the third.
    /// </remarks>
    private static int? ParseCount(string? raw)
    {
        if (string.IsNullOrEmpty(raw)) return null;
        foreach (var c in raw!)
        {
            if (c < '0' || c > '9') return null;
        }
        // Digits only by now, so no culture and no NumberStyles can change the
        // reading; TryParse is still what rejects a count too large for an int.
        return int.TryParse(raw, out var n) ? n : (int?)null;
    }

    public static ConfigPorcelainResult ParseConfigPorcelain(string stdout)
    {
        string? bas = null;
        string? remote = null;
        var candidates = new List<CandidateBranch>();
        var remotes = new List<CandidateRemote>();
        var deltas = new List<DeltaRecord>();
        var offers = new List<ReadingOffer>();
        var drafts = new List<DraftRecord>();
        var guides = new List<GuideRecord>();
        WalkthroughRecord? walkthrough = null;

        foreach (var line in stdout.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
        {
            if (line.Length == 0) continue;
            var fields = line.Split('\t');
            switch (fields[0])
            {
                case "config":
                {
                    var key = Get(fields, 1);
                    var value = Get(fields, 2);
                    if (value is null) continue;
                    if (key == "base") bas = value;
                    else if (key == "remote") remote = value;
                    break;
                }
                case "remote-candidate":
                {
                    var name = Get(fields, 1);
                    if (string.IsNullOrEmpty(name)) continue;
                    remotes.Add(new CandidateRemote(name, ToBool(Get(fields, 2))));
                    break;
                }
                case "candidate":
                {
                    var name = Get(fields, 1);
                    var origin = Get(fields, 2);
                    if (name is null || (origin != "remote" && origin != "local")) continue;
                    candidates.Add(new CandidateBranch(name, origin!, ToBool(Get(fields, 3))));
                    break;
                }
                case "delta":
                {
                    var name = Get(fields, 1);
                    var tip = Get(fields, 2);
                    var origin = DeltaOriginExt.Parse(Get(fields, 3));
                    if (name is not null && tip is not null && origin is not null)
                        deltas.Add(new DeltaRecord(name, tip, origin.Value));
                    break;
                }
                case "draft":
                {
                    var src = Get(fields, 1);
                    var path = Get(fields, 2);
                    // A malformed record is ignored whole, like any unknown one:
                    // half a progress pair would be worse than none.
                    if (string.IsNullOrEmpty(src) || string.IsNullOrEmpty(path)) continue;
                    var annotated = ParseCount(Get(fields, 3));
                    var total = ParseCount(Get(fields, 4));
                    if (annotated is null || total is null) continue;
                    drafts.Add(new DraftRecord(
                        src!,
                        path!,
                        annotated.Value,
                        total.Value,
                        DraftSourceExt.Parse(Get(fields, 5)),
                        DraftRangeExt.Parse(Get(fields, 6)),
                        DraftStateExt.Parse(Get(fields, 7))));
                    break;
                }
                case "guide":
                {
                    var guide = ParseGuideRecord(fields);
                    if (guide is not null) guides.Add(guide);
                    break;
                }
                case "walkthrough":
                {
                    // One row per invocation. If two arrived the first wins: a
                    // second would be the CLI contradicting itself, and taking
                    // the last would make the panel depend on emission order.
                    if (walkthrough is null) walkthrough = ParseWalkthroughRecord(fields);
                    break;
                }
                case "offer":
                {
                    var id = OfferIdExt.Parse(Get(fields, 1));
                    var rank = OfferRankExt.Parse(Get(fields, 2));
                    if (id is not null && rank is not null)
                        offers.Add(new ReadingOffer(id.Value, rank.Value));
                    break;
                }
            }
        }

        var config = new EffectiveConfig(bas, remote ?? "origin");
        return new ConfigPorcelainResult(
            config,
            candidates,
            remotes,
            deltas.Count > 0 ? deltas : null,
            offers.Count > 0 ? offers : null,
            drafts,
            guides,
            walkthrough);
    }

    /// <summary>
    /// A <c>guide</c> record from its fields, or null when it is malformed — ignored
    /// whole, like any record: half a guide row would offer to create one that is
    /// already there, or open one that is not.
    ///
    /// Shared because the record arrives by TWO verbs: <c>config --porcelain</c>
    /// outside a review and <c>status --porcelain</c> inside one. One parser per
    /// tokenizer would be the same rule written twice, and the second copy would learn
    /// about any new field late.
    /// </summary>
    /// <summary>
    /// A walkthrough record from its fields, or null when it is malformed.
    ///
    /// The annotated/total pair falls back to 0/0 rather than dropping the whole
    /// row: the state is what decides what the block offers, and losing it to an
    /// unreadable counter would leave the author without the one surface that
    /// tells them their reading order fell behind. An unrecognised state does
    /// drop the row — drawing an invented badge is worse than drawing no block.
    /// </summary>
    public static WalkthroughRecord? ParseWalkthroughRecord(string[] fields)
    {
        var state = WalkthroughStateExt.Parse(Get(fields, 1));
        var path = Get(fields, 2);
        if (state is null || string.IsNullOrEmpty(path)) return null;
        return new WalkthroughRecord(
            path!,
            state.Value,
            ParseCount(Get(fields, 3)) ?? 0,
            ParseCount(Get(fields, 4)) ?? 0);
    }

    public static GuideRecord? ParseGuideRecord(string[] fields)
    {
        var kind = GuideKindExt.Parse(Get(fields, 1));
        var path = Get(fields, 2);
        var state = GuideStateExt.Parse(Get(fields, 3));
        if (kind is null || string.IsNullOrEmpty(path) || state is null) return null;
        return new GuideRecord(kind.Value, path!, state.Value);
    }

    /// <summary>
    /// Branches for the start-review picker. Collapse remote+local same name;
    /// prefer current; current sorts first.
    /// </summary>
    public static IReadOnlyList<CandidateBranch> BranchPickerItems(IReadOnlyList<CandidateBranch> candidates)
    {
        var byName = new Dictionary<string, CandidateBranch>();
        foreach (var c in candidates)
        {
            if (!byName.TryGetValue(c.Name, out var prev) || (c.Current && !prev.Current))
                byName[c.Name] = c;
        }
        return byName.Values
            .OrderByDescending(c => c.Current)
            .ThenBy(c => c.Name, StringComparer.Ordinal)
            .ToList();
    }

    public static string BranchPickerLabel(CandidateBranch candidate) =>
        candidate.Current ? $"{candidate.Name}  (current)" : candidate.Name;

    public static DeltaRecord? DeltaForSource(IReadOnlyList<DeltaRecord>? deltas, string source)
    {
        if (deltas is null || deltas.Count == 0) return null;
        var origin = source == "remote" ? DeltaOrigin.Remote : DeltaOrigin.Local;
        return deltas.FirstOrDefault(d => d.Origin == origin);
    }

    private static string? Get(string[] fields, int i) =>
        i < fields.Length ? fields[i] : null;
}
