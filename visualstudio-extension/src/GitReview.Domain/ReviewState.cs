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
    /// <summary>
    /// 012: loose walkthrough drafts of the working tree, from the same
    /// `config --porcelain` report that brings Config — no extra invocation.
    /// Null when that report did not arrive; empty if it did with none.
    /// </summary>
    IReadOnlyList<DraftRecord>? Drafts = null,
    /// <summary>
    /// Both authoring guides (`guide` record of `config --porcelain`), in the
    /// CLI's order and always both. Null when that report did not arrive; empty
    /// against a CLI that does not know the record.
    /// </summary>
    IReadOnlyList<GuideRecord>? Guides = null,
    /// <summary>
    /// The author's walkthrough for the branch that is checked out (`walkthrough`
    /// record of `config --porcelain`), from the same report. Null when that
    /// report did not arrive, and against a CLI older than the record — which is
    /// the same thing to the panel: no row, no block.
    /// </summary>
    WalkthroughRecord? Walkthrough = null,
    IReadOnlyDictionary<int, string>? Subjects = null,
    IReadOnlyDictionary<int, string>? Authors = null,
    string? Base = null,
    StatusFinishRecord? Finish = null,
    bool? Readonly = null,
    bool? KeysOnly = null,
    bool? Draft = null,
    /// <summary>012: absolute path of the draft in force, reported by the CLI.</summary>
    string? DraftPath = null,
    string? Stderr = null)
{
    public IReadOnlyList<EntryRecord> EntriesList => Entries ?? Array.Empty<EntryRecord>();
    public IReadOnlyList<EntryRecord> FilesList => Files ?? Array.Empty<EntryRecord>();
    public IReadOnlyList<BranchRecord> BranchesList => Branches ?? Array.Empty<BranchRecord>();
    public IReadOnlyList<DraftRecord> DraftsList => Drafts ?? Array.Empty<DraftRecord>();
    public IReadOnlyList<GuideRecord> GuidesList => Guides ?? Array.Empty<GuideRecord>();
}
