namespace GitReview.Domain;

/// <summary>
/// In-memory aggregate after a refresh. Host populates this; domain only holds the shape.
/// </summary>
public sealed record ReviewState(
    Situation Situation,
    StateRecord? State = null,
    IReadOnlyList<EntryRecord>? Entries = null,
    /// <summary>Step: files of the current commit (file porcelain). Empty otherwise.</summary>
    IReadOnlyList<EntryRecord>? Files = null,
    IReadOnlyList<BranchRecord>? Branches = null,
    EffectiveConfig? Config = null,
    IReadOnlyList<CandidateBranch>? Candidates = null,
    IReadOnlyList<CandidateRemote>? Remotes = null,
    IReadOnlyDictionary<int, string>? Subjects = null,
    IReadOnlyDictionary<int, string>? Authors = null,
    string? Base = null,
    StatusFinishRecord? Finish = null,
    bool? Readonly = null,
    bool? KeysOnly = null,
    bool? Draft = null,
    string? Stderr = null)
{
    public IReadOnlyList<EntryRecord> EntriesList => Entries ?? Array.Empty<EntryRecord>();
    public IReadOnlyList<EntryRecord> FilesList => Files ?? Array.Empty<EntryRecord>();
    public IReadOnlyList<BranchRecord> BranchesList => Branches ?? Array.Empty<BranchRecord>();
}
