package domain

// WhyState is showWhy's own state (T094): the four values
// vscode-extension/src/views/panelModel.ts's WhyState already declares, for
// the same reason. "loading" is the zero value on purpose — a hand-built or
// not-yet-read PanelModel defaults to "asked, no answer yet" rather than
// silently reading as "there is nothing to say" (WhyAbsent) or worse "we
// asked and it failed" (WhyFailed): those are two DIFFERENT true things,
// and collapsing either of them into "we have not asked" would be a lie in
// the other direction. WhyAbsent and WhyFailed are themselves genuinely
// distinct: an entry the walkthrough never annotates versus a `status
// --why` invocation that could not answer at all (a timeout, a spawn
// failure, a nonzero exit) — the old bool HasWhy could not tell them apart,
// so no existing golden fixture exercises WhyFailed and none of them can
// regress from this type replacing it.
type WhyState string

const (
	WhyLoading WhyState = "loading"
	WhyPresent WhyState = "present"
	WhyAbsent  WhyState = "absent"
	WhyFailed  WhyState = "failed"
)

// PanelModel is the flat projection of what gets drawn — nothing about how
// it is drawn (data-model.md § PanelModel). It is COMPARABLE BY VALUE: no
// maps, no slices, no pointers. That property is what SC-004 rests on — an
// unchanged model produces no frame, so "exactly one repaint" is provable by
// comparing two PanelModel values with `==`, never by timing anything.
//
// Whatever is naturally a variable-length list — the footer's rows, the
// current commit's files — travels pre-rendered as a single already-joined
// string plus its count, never as a slice. panelmodel_test.go fails to
// compile the moment a field stops being comparable, which is the point:
// the property is enforced by the compiler, not by a reviewer noticing a
// slice in a diff.
type PanelModel struct {
	Situation Situation
	Busy      bool
	RepoLabel string

	// Inventory (no-review): the review/saved rows, one line per row,
	// newline-joined, plus how many. HasReviews distinguishes zero rows
	// from "no fresh drafts either", both of which are legal empty states
	// with different footers. Every review/review-saved branch gets a row
	// here (not only the ones with a control — a row with neither Continue
	// nor Delete still has to be listed), tab fields
	// `name \t saved(0/1) \t orphan(0/1) \t current(0/1) \t resumable(0/1) \t status`,
	// read back with FooterRows (rowdata.go).
	InventoryRows  string
	InventoryCount int
	HasReviews     bool

	PendingFinish     bool
	FinishDestination string // where the edits landed (finish-pending banner)
	FinishConflict    bool

	NoBaseConfigured bool
	ConfiguredBase   string
	ConfiguredRemote string

	Mode      ReviewMode
	Branch    string
	Source    string
	Tip       string
	Base      string
	HasBase   bool
	Position  int
	Total     int
	BaseMoved bool
	AtFirst   bool
	AtLast    bool

	NavigationLocked bool
	Degraded         bool
	Readonly         bool
	KeysOnly         bool

	HasCurrent  bool
	CurrentSHA  string
	CurrentPath PathRef
	EntryCount  int
	// Files: the current commit's (step) or the whole review's (whole)
	// inventory, one line per file, newline-joined.
	Files string

	// WhyState / Why: showWhy's own state and text (T094). Why only carries
	// text when WhyState == WhyPresent — see WhyState's own doc for why the
	// other three states stay distinct instead of collapsing to a bool.
	WhyState WhyState
	Why      string

	// EntryPickerRows: goToEntry's own list (T086), a picker SEPARATE from
	// the action list overlay — it enumerates ENTRIES, not actions. One row
	// per `entry` record `status --porcelain` reports for the review's
	// current mode, in the CLI's own reading order, never re-sorted: tab
	// fields `position \t raw \t display`. raw is what open.go's delegated
	// commands need (a short SHA in step mode, PathRef.Raw otherwise) and
	// display is what the picker draws — CLAUDE.md's rule that Raw never
	// reaches the screen applies here exactly as everywhere else PathRef
	// travels.
	EntryPickerRows string

	// Footer rows (no-review only; a review never projects these —
	// FR-023, enforced by the projector never filling them in rather than
	// by render.go skipping them). The three list-shaped fields
	// (FreshDraftRows/SpentDraftRows/FixesRows/InventoryRows) stay flat
	// strings for PanelModel's own comparability (no slices, no maps): each
	// is a newline-joined list of TAB-separated rows, built by
	// FooterField/read back by FooterRows (rowdata.go) — the same
	// porcelain-flavored packing the CLI itself uses, adapted here for a
	// list that must survive an `==` comparison rather than be printed.
	WalkthroughRow       string // the branch this walkthrough annotates, or "" (detached, or no record at all)
	HasWalkthroughRow    bool
	WalkthroughState     WalkthroughState
	WalkthroughAnnotated int
	WalkthroughTotal     int

	// HasGuideRows: false only when config could not be read at all, or an
	// older CLI omitted the `guide` records — the two rows themselves are
	// otherwise ALWAYS both present (CLAUDE.md: absence is reported, not
	// implied by silence), never conditioned on one guide existing and not
	// the other.
	HasGuideRows   bool
	TeamGuideRow   string // the team guide's reported path (never assembled client-side)
	TeamGuideState GuideState
	OwnGuideRow    string // the reviewer's own guide's reported path
	OwnGuideState  GuideState

	// FreshDraftRows / SpentDraftRows: one row per draft, tab fields
	// `src \t path \t source \t range \t annotated \t total` — everything
	// draft_controls' four controls and the row's own progress pair need,
	// with Src doubling as each control's Variant (ControlsFor/mutation.go
	// resolve the target row by matching it, never by position).
	FreshDraftRows  string
	FreshDraftCount int
	SpentDraftRows  string
	SpentDraftCount int

	// FixesRows: one row per `review-fixes/*` branch, tab fields
	// `name \t state \t session(0/1) \t current(0/1)`.
	FixesRows  string
	FixesCount int

	// Note: a single derived, presentation-only line (STALE, a moved base,
	// a branch that diverged locally). Empty when there is nothing to say.
	Note string

	// MouseEnabled is the one field that does not come from porcelain at
	// all: it is terminal state, not repository state (FR-067).
	MouseEnabled bool

	// Stderr: raw CLI stderr, present only in the failure situations
	// (cli-missing, cli-outdated, out-of-range, error).
	Stderr string

	// StatusLine is what a toast would say in the other three clients
	// (contracts/tui-surface.md § copy: "en un pane no hay toasts: el panel
	// ES la superficie"): the last mutation's outcome, when the rest of the
	// panel would not otherwise say it. Chosen by WHAT WAS ASKED, never by
	// parsing a verb's stdout (FR-013) — internal/ui decides the text and
	// merely carries it here for render.go to draw. Empty means nothing to
	// say.
	StatusLine string
}
