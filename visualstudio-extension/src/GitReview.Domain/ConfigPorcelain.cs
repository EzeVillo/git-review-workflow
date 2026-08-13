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

public sealed record ConfigPorcelainResult(
    EffectiveConfig Config,
    IReadOnlyList<CandidateBranch> Candidates,
    IReadOnlyList<CandidateRemote> Remotes,
    IReadOnlyList<DeltaRecord>? Deltas = null,
    IReadOnlyList<ReadingOffer>? Offers = null);

public static class ConfigPorcelain
{
    private static bool ToBool(string? field) => field == "1";

    public static ConfigPorcelainResult ParseConfigPorcelain(string stdout)
    {
        string? bas = null;
        string? remote = null;
        var candidates = new List<CandidateBranch>();
        var remotes = new List<CandidateRemote>();
        var deltas = new List<DeltaRecord>();
        var offers = new List<ReadingOffer>();

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
            offers.Count > 0 ? offers : null);
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
