package domain

import (
	"sort"
	"strconv"
	"strings"
)

// ReviewMode is the mode a review runs in.
type ReviewMode string

const (
	ModeWhole ReviewMode = "whole"
	ModeStep  ReviewMode = "step"
	ModeWalk  ReviewMode = "walk"
)

// WalkthroughStatus is how the reading order applied to the review being
// walked (as opposed to WalkthroughState, which is the AUTHOR's own
// walkthrough for the branch currently checked out).
type WalkthroughStatus string

const (
	WalkthroughNone     WalkthroughStatus = "none"
	WalkthroughApplied  WalkthroughStatus = "applied"
	WalkthroughDegraded WalkthroughStatus = "degraded"
)

// StateRecord is the `state` record of `status --porcelain`.
type StateRecord struct {
	Branch      string
	Source      string
	Tip         string
	Mode        ReviewMode
	Walkthrough WalkthroughStatus
	// Position, Total, Recorded: only in step/walk.
	Position, Total, Recorded int
	// Current: short SHA (step, as CurrentSHA) or a path (walk, as
	// CurrentPath). Only one of the two is meaningful, decided by Mode.
	CurrentSHA  string
	CurrentPath PathRef
	// Essential: only in walk.
	Essential bool
}

// EntryRecord is an `entry` (or `file`) record: position 1-based within its
// sequence, and an id that is a short SHA in step mode or a path otherwise.
type EntryRecord struct {
	Position int
	// ID: short SHA (step, as SHA) or a path (whole/walk, as Path).
	SHA  string
	Path PathRef
	// Essential, Annotated: only in walk.
	Essential, Annotated bool
	// Banked: only in step.
	Banked bool
}

// StatusFinishRecord is the `finish` record of `status --porcelain`. State
// is always "conflict": a completed finish already moved HEAD out of
// review/*, so `status` never sees it — that is what `list` reports instead.
type StatusFinishRecord struct {
	State string // always "conflict"
	Onto  bool
}

// PorcelainResult is the parsed output of `status --porcelain`.
type PorcelainResult struct {
	State   StateRecord
	Entries []EntryRecord
	// Files: the CURRENT commit's file inventory in step mode (`file`
	// records), position 1-based within that commit. Always a non-nil slice,
	// empty when there are no `file` lines.
	Files []EntryRecord

	Finish   *StatusFinishRecord
	Readonly bool
	KeysOnly bool
	Draft    bool
	// DraftPath: the absolute path of the draft in force, from the `draft`
	// record's field. Kept apart from Draft on purpose: presence is
	// presence, and a missing field (an older CLI, a truncated record)
	// cannot turn off the mark.
	DraftPath string
	Base      string // only in whole mode, and only if one is configured
	// Subjects, Authors: by Position, step mode only. Nil map means the CLI
	// did not emit the record at all — distinct from an empty map, which
	// would mean "this review has none".
	Subjects map[int]string
	Authors  map[int]string
}

// field returns fields[i], or "" if the record has fewer fields than
// expected. FR-015's "do not assume a field count": a record with FEWER
// fields than a newer client expects is not corrupt, it is an older CLI.
func field(fields []string, i int) string {
	if i < 0 || i >= len(fields) {
		return ""
	}
	return fields[i]
}

func toBool(s string) bool { return s == "1" }

func toInt(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return n
}

// toOptionalInt is like toInt, but a missing or non-numeric field is
// "absent", never a silently-invented 0.
func toOptionalInt(s string) (int, bool) {
	if s == "" {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0, false
	}
	return n, true
}

func parseReviewMode(s string) (ReviewMode, bool) {
	switch ReviewMode(s) {
	case ModeWhole, ModeStep, ModeWalk:
		return ReviewMode(s), true
	default:
		return "", false
	}
}

// restAfterTab returns the free-text field of a record: everything after the
// skip-th tab of line. It is deliberately not a split on tabs: a commit
// subject or an author name is written by a person, not by git, so it can
// contain a literal tab — unlike a path, which git quotes unconditionally.
// The contract puts free text last in its record so there is nothing after
// it to shift.
//
// The second return value is false when the line does not have skip tabs at
// all: that is a record this parser does not understand, not an empty field.
// A legitimately empty field returns ("", true).
func restAfterTab(line string, skip int) (string, bool) {
	index := -1
	for i := 0; i < skip; i++ {
		next := strings.IndexByte(line[index+1:], '\t')
		if next == -1 {
			return "", false
		}
		index = index + 1 + next
	}
	return line[index+1:], true
}

// ParsePorcelain tokenizes `git review status --porcelain`. The `state`
// record's mode field is read FIRST and decides the arity expected of the
// lines that follow — never the other way around (research.md Decision 2).
// Unknown tags and extra trailing fields on a known record are ignored
// (FR-015).
func ParsePorcelain(stdout string) (PorcelainResult, bool) {
	lines := splitLines(stdout)

	var (
		result    PorcelainResult
		haveState bool
	)

	for _, line := range lines {
		fields := strings.Split(line, "\t")
		switch fields[0] {
		case "state":
			mode, ok := parseReviewMode(field(fields, 4))
			if !ok {
				return PorcelainResult{}, false
			}
			state := StateRecord{
				Branch:      field(fields, 1),
				Source:      field(fields, 2),
				Tip:         field(fields, 3),
				Mode:        mode,
				Walkthrough: WalkthroughStatus(field(fields, 5)),
			}
			if mode == ModeStep || mode == ModeWalk {
				state.Position = toInt(field(fields, 6))
				state.Total = toInt(field(fields, 7))
				state.Recorded = toInt(field(fields, 8))
				if mode == ModeWalk {
					state.CurrentPath = NewPathRef(field(fields, 9))
				} else {
					state.CurrentSHA = field(fields, 9)
				}
			}
			if mode == ModeWalk {
				state.Essential = toBool(field(fields, 10))
			}
			result.State = state
			haveState = true

		case "entry":
			if !haveState {
				return PorcelainResult{}, false
			}
			entry := EntryRecord{Position: toInt(field(fields, 1))}
			raw := field(fields, 2)
			if result.State.Mode == ModeStep {
				entry.SHA = raw
			} else {
				entry.Path = NewPathRef(raw)
			}
			switch result.State.Mode {
			case ModeWalk:
				entry.Essential = toBool(field(fields, 3))
				entry.Annotated = toBool(field(fields, 4))
			case ModeStep:
				entry.Banked = toBool(field(fields, 3))
			}
			result.Entries = append(result.Entries, entry)

		case "file":
			if !haveState {
				return PorcelainResult{}, false
			}
			raw := field(fields, 2)
			if raw == "" {
				continue
			}
			result.Files = append(result.Files, EntryRecord{
				Position: toInt(field(fields, 1)),
				Path:     NewPathRef(raw),
			})

		case "subject", "author":
			pos, ok := toOptionalInt(field(fields, 1))
			text, ok2 := restAfterTab(line, 2)
			if !ok || !ok2 {
				continue
			}
			if fields[0] == "subject" {
				if result.Subjects == nil {
					result.Subjects = map[int]string{}
				}
				result.Subjects[pos] = text
			} else {
				if result.Authors == nil {
					result.Authors = map[int]string{}
				}
				result.Authors[pos] = text
			}

		case "base":
			if text, ok := restAfterTab(line, 1); ok {
				result.Base = text
			}

		case "finish":
			if field(fields, 1) == "conflict" {
				result.Finish = &StatusFinishRecord{State: "conflict", Onto: toBool(field(fields, 2))}
			}

		case "readonly":
			result.Readonly = true

		case "keys":
			result.KeysOnly = true

		case "draft":
			result.Draft = true
			if p := field(fields, 1); p != "" {
				result.DraftPath = p
			}

		default:
			// Unknown tag: ignored (FR-015).
		}
	}

	if !haveState {
		return PorcelainResult{}, false
	}
	if result.Entries == nil {
		result.Entries = []EntryRecord{}
	}
	if result.Files == nil {
		result.Files = []EntryRecord{}
	}
	return result, true
}

// splitLines splits porcelain stdout on lines, stripping a trailing CR so a
// CRLF wrapper does not poison the last field of a record, and dropping
// empty lines.
func splitLines(stdout string) []string {
	raw := strings.Split(stdout, "\n")
	out := make([]string, 0, len(raw))
	for _, l := range raw {
		l = strings.TrimSuffix(l, "\r")
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

// BranchRecord is a `branch` record of `git review list --porcelain`.
type BranchRecord struct {
	Name    string // "review/<x>" or "review-saved/<x>"
	Saved   bool
	Current bool
	Orphan  bool // no reviewsource metadata: mode/position/total absent
	Mode    ReviewMode
	// Position, Total: present only in step/walk, and only if the CLI
	// emitted both.
	Position, Total  int
	HasPositionTotal bool
	Finish           *ListFinish
}

// ListFinish is the unresolved finish of a branch as `list` reports it —
// unlike StatusFinishRecord, State can be "pending" here: list sees the
// whole repository, not just the branch the user is standing on.
type ListFinish struct {
	State string // "pending" | "conflict"
	Onto  bool
}

// FixesState is how much it costs to discard a review-fixes/* branch.
type FixesState string

const (
	FixesEmpty    FixesState = "empty"
	FixesMerged   FixesState = "merged"
	FixesUnmerged FixesState = "unmerged"
	FixesUnknown  FixesState = "unknown"
)

func parseFixesState(s string) FixesState {
	switch FixesState(s) {
	case FixesEmpty, FixesMerged, FixesUnmerged:
		return FixesState(s)
	default:
		// An unrecognized value reads as "cannot tell", never as one of the
		// three concrete ones: this row's badge is the only thing keeping a
		// discard of an empty branch apart from a discard of unpushed work.
		return FixesUnknown
	}
}

// FixesRecord is a `fixes` record of `git review list --porcelain`: a
// review-fixes/<x> branch a finish left behind.
type FixesRecord struct {
	Name    string
	Current bool
	Session bool // review/<x> still exists: the review is still open
	State   FixesState
}

// sourceOf strips the "review-saved/" or "review/" prefix from a branch
// name — the argument `git review continue` expects. An unrecognized prefix
// returns the name as-is: inventing a cut would be worse than passing
// something the CLI will reject with its own message.
func sourceOf(name string) string {
	for _, prefix := range []string{"review-saved/", "review/"} {
		if strings.HasPrefix(name, prefix) {
			return name[len(prefix):]
		}
	}
	return name
}

// SourceOf is sourceOf exported for consumers outside this package.
func SourceOf(b BranchRecord) string { return sourceOf(b.Name) }

// ParseListPorcelain tokenizes `git review list --porcelain` (`branch` and
// `finish` records). Same porcelain v1 rules as ParsePorcelain: unknown tags
// and trailing fields are ignored. Unlike status, no records at all is a
// valid result — a repository with no reviews — not a format error.
func ParseListPorcelain(stdout string) []BranchRecord {
	var branches []BranchRecord
	finishByBranch := map[string]ListFinish{}

	for _, line := range splitLines(stdout) {
		fields := strings.Split(line, "\t")
		switch fields[0] {
		case "finish":
			name := field(fields, 1)
			state := field(fields, 2)
			if name != "" && (state == "pending" || state == "conflict") {
				finishByBranch[name] = ListFinish{State: state, Onto: toBool(field(fields, 3))}
			}
		case "branch":
			b := BranchRecord{
				Name:    field(fields, 1),
				Saved:   toBool(field(fields, 2)),
				Current: toBool(field(fields, 3)),
				Orphan:  toBool(field(fields, 4)),
			}
			if !b.Orphan {
				modeField := field(fields, 5)
				if modeField == "" {
					modeField = "whole"
				}
				if mode, ok := parseReviewMode(modeField); ok {
					b.Mode = mode
				}
				pos, okP := toOptionalInt(field(fields, 6))
				total, okT := toOptionalInt(field(fields, 7))
				if okP && okT {
					b.Position, b.Total = pos, total
					b.HasPositionTotal = true
				}
			}
			branches = append(branches, b)
		default:
			// Unknown tag: ignored.
		}
	}

	for i := range branches {
		if f, ok := finishByBranch[branches[i].Name]; ok {
			f := f
			branches[i].Finish = &f
		}
	}
	if branches == nil {
		branches = []BranchRecord{}
	}
	return branches
}

// ParseListFixes reads the `fixes` records out of `list --porcelain`,
// separately from ParseListPorcelain: these are branches of EXTRACTED
// EDITS, not reviews — there is nothing to resume or abort on them.
func ParseListFixes(stdout string) []FixesRecord {
	var fixes []FixesRecord
	for _, line := range splitLines(stdout) {
		fields := strings.Split(line, "\t")
		if fields[0] != "fixes" {
			continue
		}
		name := field(fields, 1)
		if name == "" {
			continue
		}
		fixes = append(fixes, FixesRecord{
			Name:    name,
			Current: toBool(field(fields, 2)),
			Session: toBool(field(fields, 3)),
			State:   parseFixesState(field(fields, 4)),
		})
	}
	if fixes == nil {
		fixes = []FixesRecord{}
	}
	return fixes
}

// --- config --porcelain -----------------------------------------------

// EffectiveConfig is the `config` record: how a review would be set up.
type EffectiveConfig struct {
	Base    string // absent = not configured, a normal state
	HasBase bool
	Remote  string // always present: "origin" when nothing is configured
}

// CandidateBranch is a `candidate` record: a branch offered to the start
// assistant's branch picker.
type CandidateBranch struct {
	Name    string
	Origin  string // "remote" | "local"
	Current bool
}

// CandidateRemote is a `remote-candidate` record.
type CandidateRemote struct {
	Name    string
	Current bool
}

// DeltaRecord is a `delta` record: the `--delta` marker's axis.
type DeltaRecord struct {
	Name   string
	Tip    string
	Origin string // "remote" | "local"
}

// OfferID is a reading form the CLI reports as viable.
type OfferID string

const (
	OfferWalk        OfferID = "walk"
	OfferKeys        OfferID = "keys"
	OfferDraft       OfferID = "draft"
	OfferDraftResume OfferID = "draft-resume"
	OfferDraftUpdate OfferID = "draft-update"
	OfferStep        OfferID = "step"
	OfferWhole       OfferID = "whole"
)

// ReadingOffer is an `offer` record.
type ReadingOffer struct {
	ID   OfferID
	Rank string // "recommended" | "available"
}

type MergedRecord struct {
	Kept, Added, Dropped int
}

// ParseMergedRecord reads the one machine record emitted by walkthrough
// draft --porcelain after reconciling an existing order.
func ParseMergedRecord(stdout string) (MergedRecord, bool) {
	for _, line := range strings.Split(stdout, "\n") {
		fields := strings.Split(strings.TrimSpace(line), "\t")
		if len(fields) < 4 || fields[0] != "merged" {
			continue
		}
		values := make([]int, 3)
		for i, field := range fields[1:4] {
			value, err := strconv.Atoi(field)
			if err != nil || value < 0 {
				return MergedRecord{}, false
			}
			values[i] = value
		}
		return MergedRecord{Kept: values[0], Added: values[1], Dropped: values[2]}, true
	}
	return MergedRecord{}, false
}

// DraftSource / DraftRange / DraftState mirror the CLI's own vocabulary for
// a loose draft record; "unknown" is legal in the first two (the
// instructions block was deleted by hand) and decides which controls a
// client may offer, not something derived here.
type (
	DraftSource string
	DraftRange  string
	DraftState  string
)

const (
	DraftSourceRemote  DraftSource = "remote"
	DraftSourceLocal   DraftSource = "local"
	DraftSourceOffline DraftSource = "offline"
	DraftSourceUnknown DraftSource = "unknown"

	DraftRangeFull    DraftRange = "full"
	DraftRangeDelta   DraftRange = "delta"
	DraftRangeUnknown DraftRange = "unknown"

	DraftFresh    DraftState = "fresh"
	DraftReviewed DraftState = "reviewed"
)

// DraftRecord is a loose draft walkthrough: it exists in the active
// namespace of the gitdir, meaning the reviewer started it and never
// paused the review (`draft` record of `config --porcelain`). Path comes
// verbatim from the CLI and is only ever opened, never assembled.
type DraftRecord struct {
	Src       string
	Path      string
	Annotated int
	Total     int
	Source    DraftSource
	Range     DraftRange
	State     DraftState
}

// GuideKind / GuideState mirror the two authoring guides and their three
// possible states. `empty` and `absent` are not synonyms: with the file
// present what is offered is opening it, not creating it, and only an
// existing one can be discarded.
type (
	GuideKind  string
	GuideState string
)

const (
	GuideTeam GuideKind = "team"
	GuideOwn  GuideKind = "own"

	GuideInForce GuideState = "in-force"
	GuideEmpty   GuideState = "empty"
	GuideAbsent  GuideState = "absent"
)

// GuideRecord is a `guide` record — prose about the walkthrough's CONTENT.
// This client never reads a byte of it: it opens the reported Path, never
// one it assembled itself.
type GuideRecord struct {
	Kind  GuideKind
	Path  string
	State GuideState
}

func parseGuideKind(s string) (GuideKind, bool) {
	switch GuideKind(s) {
	case GuideTeam, GuideOwn:
		return GuideKind(s), true
	default:
		return "", false
	}
}

func parseGuideState(s string) (GuideState, bool) {
	switch GuideState(s) {
	case GuideInForce, GuideEmpty, GuideAbsent:
		return GuideState(s), true
	default:
		return "", false
	}
}

// ParseGuideRecord reads one `guide` record from its fields, or ok=false if
// malformed. Exported because the record arrives via TWO verbs (`config
// --porcelain` outside a review, `status --porcelain` inside one): one
// parser for one tokenizer, so a new field is learned once.
func ParseGuideRecord(fields []string) (GuideRecord, bool) {
	kind, ok := parseGuideKind(field(fields, 1))
	path := field(fields, 2)
	state, ok2 := parseGuideState(field(fields, 3))
	if !ok || path == "" || !ok2 {
		return GuideRecord{}, false
	}
	return GuideRecord{Kind: kind, Path: path, State: state}, true
}

// WalkthroughState is the author's own walkthrough's freshness against the
// branch checked out today. "unknown" is not "stale": without the
// instructions block (legal to delete by hand) the question has no answer,
// and answering the worse of the two would send the author to redo a
// reading order that might be fine. "superseded" is not "stale" either: the
// file belongs to an already-merged PR, so what is offered is starting
// over, not reconciling.
type WalkthroughState string

const (
	WalkthroughInSync       WalkthroughState = "in-sync"
	WalkthroughStale        WalkthroughState = "stale"
	WalkthroughSuperseded   WalkthroughState = "superseded"
	WalkthroughUnknownState WalkthroughState = "unknown"
	WalkthroughAbsent       WalkthroughState = "absent"
)

func parseWalkthroughState(s string) (WalkthroughState, bool) {
	switch WalkthroughState(s) {
	case WalkthroughInSync, WalkthroughStale, WalkthroughSuperseded, WalkthroughUnknownState, WalkthroughAbsent:
		return WalkthroughState(s), true
	default:
		return "", false
	}
}

// WalkthroughRecord is the `walkthrough` record: the committed reading
// order of the branch checked out today, and whether it still matches. Path
// is verbatim from the CLI, like the draft's and the guides': opened, never
// assembled.
type WalkthroughRecord struct {
	Path      string
	State     WalkthroughState
	Annotated int
	Total     int
	// Branch: the branch this walkthrough annotates. Absent with a detached
	// HEAD, the only case where the CLI omits the field.
	Branch    string
	HasBranch bool
}

func toCount(s string) int {
	if s == "" {
		return 0
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 {
		return 0
	}
	return n
}

func parseCount(s string) (int, bool) {
	if s == "" {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 {
		return 0, false
	}
	return n, true
}

func parseWalkthroughRecord(fields []string) (WalkthroughRecord, bool) {
	state, ok := parseWalkthroughState(field(fields, 1))
	path := field(fields, 2)
	if !ok || path == "" {
		return WalkthroughRecord{}, false
	}
	rec := WalkthroughRecord{
		Path:      path,
		State:     state,
		Annotated: toCount(field(fields, 3)),
		Total:     toCount(field(fields, 4)),
	}
	if b := field(fields, 5); b != "" {
		rec.Branch = b
		rec.HasBranch = true
	}
	return rec, true
}

func parseOfferID(s string) (OfferID, bool) {
	switch OfferID(s) {
	case OfferWalk, OfferKeys, OfferDraft, OfferDraftResume, OfferDraftUpdate, OfferStep, OfferWhole:
		return OfferID(s), true
	default:
		return "", false
	}
}

func parseOfferRank(s string) (string, bool) {
	if s == "recommended" || s == "available" {
		return s, true
	}
	return "", false
}

func parseDraftSource(s string) DraftSource {
	switch s {
	case "remote":
		return DraftSourceRemote
	case "local":
		return DraftSourceLocal
	case "offline":
		return DraftSourceOffline
	default:
		return DraftSourceUnknown
	}
}

func parseDraftRange(s string) DraftRange {
	switch s {
	case "full":
		return DraftRangeFull
	case "delta":
		return DraftRangeDelta
	default:
		return DraftRangeUnknown
	}
}

// parseDraftState: anything other than exactly "reviewed" is "fresh",
// including a missing field — an older CLI does not emit it, and there the
// panel must behave as it always did: the draft in its usual block, with
// its four controls, not hidden for a datum nobody gave it.
func parseDraftState(s string) DraftState {
	if s == "reviewed" {
		return DraftReviewed
	}
	return DraftFresh
}

// ConfigPorcelainResult is the parsed output of `config --porcelain`.
type ConfigPorcelainResult struct {
	Config      EffectiveConfig
	Candidates  []CandidateBranch
	Remotes     []CandidateRemote
	Deltas      []DeltaRecord
	Offers      []ReadingOffer
	Drafts      []DraftRecord
	Guides      []GuideRecord
	Walkthrough *WalkthroughRecord
}

// ParseConfigPorcelain parses `config`, `candidate`, `remote-candidate`,
// `delta`, `draft`, `guide`, `walkthrough` and `offer` records. `remote`
// falls back to "origin" only as a last defensive resort — the contract
// always emits it.
func ParseConfigPorcelain(stdout string) ConfigPorcelainResult {
	var (
		base, remote string
		haveBase     bool
		result       ConfigPorcelainResult
	)

	for _, line := range splitLines(stdout) {
		fields := strings.Split(line, "\t")
		switch fields[0] {
		case "config":
			key, value := field(fields, 1), field(fields, 2)
			if value == "" && len(fields) < 3 {
				continue
			}
			switch key {
			case "base":
				base, haveBase = value, true
			case "remote":
				remote = value
			}
		case "remote-candidate":
			if name := field(fields, 1); name != "" {
				result.Remotes = append(result.Remotes, CandidateRemote{Name: name, Current: toBool(field(fields, 2))})
			}
		case "candidate":
			name, origin := field(fields, 1), field(fields, 2)
			if name != "" && (origin == "remote" || origin == "local") {
				result.Candidates = append(result.Candidates, CandidateBranch{Name: name, Origin: origin, Current: toBool(field(fields, 3))})
			}
		case "delta":
			name, tip, origin := field(fields, 1), field(fields, 2), field(fields, 3)
			if name != "" && tip != "" && (origin == "remote" || origin == "local") {
				result.Deltas = append(result.Deltas, DeltaRecord{Name: name, Tip: tip, Origin: origin})
			}
		case "draft":
			src, path := field(fields, 1), field(fields, 2)
			annotated, okA := parseCount(field(fields, 3))
			total, okT := parseCount(field(fields, 4))
			if src == "" || path == "" || !okA || !okT {
				continue
			}
			result.Drafts = append(result.Drafts, DraftRecord{
				Src: src, Path: path, Annotated: annotated, Total: total,
				Source: parseDraftSource(field(fields, 5)),
				Range:  parseDraftRange(field(fields, 6)),
				State:  parseDraftState(field(fields, 7)),
			})
		case "guide":
			if g, ok := ParseGuideRecord(fields); ok {
				result.Guides = append(result.Guides, g)
			}
		case "walkthrough":
			// One row per invocation; if two arrived, the first wins — a
			// second would be the CLI contradicting itself, and picking the
			// last would make the panel depend on emission order.
			if result.Walkthrough == nil {
				if rec, ok := parseWalkthroughRecord(fields); ok {
					result.Walkthrough = &rec
				}
			}
		case "offer":
			id, okID := parseOfferID(field(fields, 1))
			rank, okRank := parseOfferRank(field(fields, 2))
			if okID && okRank {
				result.Offers = append(result.Offers, ReadingOffer{ID: id, Rank: rank})
			}
		default:
			// Unknown tag: ignored.
		}
	}

	if remote == "" {
		remote = "origin"
	}
	result.Config = EffectiveConfig{Base: base, HasBase: haveBase, Remote: remote}
	if result.Candidates == nil {
		result.Candidates = []CandidateBranch{}
	}
	if result.Remotes == nil {
		result.Remotes = []CandidateRemote{}
	}
	if result.Drafts == nil {
		result.Drafts = []DraftRecord{}
	}
	if result.Guides == nil {
		result.Guides = []GuideRecord{}
	}
	return result
}

// DeltaForSource picks the `--delta` marker usable for a start source:
// remote maps to the remote row, local and offline both map to the local
// row (same marker on the CLI side).
func DeltaForSource(deltas []DeltaRecord, source string) (DeltaRecord, bool) {
	origin := "local"
	if source == "remote" {
		origin = "remote"
	}
	for _, d := range deltas {
		if d.Origin == origin {
			return d, true
		}
	}
	return DeltaRecord{}, false
}

// BranchPickerItems collapses candidates to one entry per name, preferring
// the row marked current, for the start assistant's branch picker. The
// porcelain can carry a `remote` and a `local` row for the same name (that
// is the datum that makes asking for the origin meaningful) — but the
// origin is asked afterwards, as the assistant's own step, and the branch
// step only needs Name.
func BranchPickerItems(candidates []CandidateBranch) []CandidateBranch {
	order := make([]string, 0, len(candidates))
	byName := map[string]CandidateBranch{}
	for _, c := range candidates {
		prev, seen := byName[c.Name]
		if !seen {
			order = append(order, c.Name)
		}
		if !seen || (c.Current && !prev.Current) {
			byName[c.Name] = c
		}
	}
	out := make([]CandidateBranch, 0, len(order))
	for _, name := range order {
		out = append(out, byName[name])
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Current != out[j].Current {
			return out[i].Current
		}
		return out[i].Name < out[j].Name
	})
	return out
}
