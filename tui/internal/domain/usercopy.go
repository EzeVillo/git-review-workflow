package domain

import "fmt"

// This file carries EVERY string this client shows a person: the copy
// shared with the other three clients (contracts/client-product-
// surface.yaml `strings:`), this client's own two situational strings
// (`per_client_strings:`), the tooltip on every control that has one, and
// the two support URLs (FR-030). Nothing here is embedded in a command —
// this is the fourth `UserCopy`, after userCopy.ts / UserCopy.kt /
// UserCopy.cs.
//
// scripts/check-client-product-surface.mjs sweeps this file for every
// tooltip*: and per_client_strings.tui value the canonical declares (T025);
// bare control-id tokens (openGuide, openWalkthrough, ...) are checked
// against layout.go instead, since that is where this client actually
// declares them as map keys — repeating the identifier here would be the
// same string checked twice against two different reasons to have it.

// --- strings: (shared byte-for-byte with vscode/intellij/visualstudio) ----

const (
	// CliMissingTitle / CliOutdatedTitle carry a literal "{min}" — every
	// client interpolates it itself; the canonical's floor is
	// version.MinCLIVersion.
	CliMissingTitle     = "The git-review CLI ({min} or newer) was not found."
	CliOutdatedTitle    = "The installed git-review CLI is older than {min}."
	NoBaseCandidates    = "No branches to pick a base from were found."
	OtherInstallOptions = "Other install options"
	WaitingText         = "Reading the review state…"
)

// DraftAgentPromptBefore / DraftAgentPromptAfter are the two halves of
// `draft_agent_prompt`, split around the canonical's "{path}" placeholder —
// what copyDraftPrompt puts on the clipboard. It is a POINTER, not the
// instructions themselves: those live inside the draft file, in the
// comment at its top.
const (
	DraftAgentPromptBefore = "Fill in the reading order at "
	DraftAgentPromptAfter  = ". The instructions are inside the file, in the comment at the top. Do not change the file list or the numbering rules."

	// WalkthroughAgentPromptBefore / WalkthroughAgentPromptAfter are the
	// corresponding pointer for the author's walkthrough. It tells an agent
	// to update unfinished entries in place, never to replace the completed
	// reading order the CLI reported at this path.
	WalkthroughAgentPromptBefore = "Update the reading order at "
	WalkthroughAgentPromptAfter  = ". The instructions are inside the file, in the comment at the top. Entries that already have a number and a why are finished: leave them as they are, and fill in only the ones marked \"## ?.\"."
)

// NpmInstallHint / NpmUpdateHint are the paragraph shown right before the
// copyable command in cli-missing / cli-outdated (panel_layout: keys
// npm_install_hint / npm_update_hint) — not part of `strings:` itself, but
// verified byte-for-byte against vscode-extension/src/views/panelHtml.ts
// cliInstallHint(), the fourth copy of the same two lines.
const (
	NpmInstallHint = "Install with npm (recommended):"
	NpmUpdateHint  = "Update with npm (recommended):"
)

// --- per_client_strings: this client's own two rows -----------------------

// NoSingleRoot answers the same question `state.ts` / `ReviewStateManager`
// answer for the other three: what to do when the process is not standing
// inside a git repository. A terminal has no multi-root to open — there is
// no workspace to reconfigure, only a place to `cd` into.
const NoSingleRoot = "Run git review ui from inside a git repository. A terminal has no multi-root to open — cd into one and try again."

// AfterInstall replaces `reload_or_wait` for this client: that string
// promises the panel "checks again every few seconds", which is a poll
// (FR-032 forbids doing it, FR-069 forbids saying it), and there is no
// window to reload in a terminal. This names the next step that actually
// exists in a pane instead.
const AfterInstall = "Press r to refresh, or focus this pane again — the panel does not poll."

const ReadOptionsProgress = "Reading the available review options…"

func GuideCreated(path string) string { return fmt.Sprintf("Created %s.", path) }

func DelegatedLaunchFailed(completion, detail string) string {
	if completion != "" {
		return fmt.Sprintf("%s Could not launch the external tool: %s", completion, detail)
	}
	return fmt.Sprintf("Could not launch the external tool: %s", detail)
}

func ProgressText(action string, p ActionParams) string {
	switch action {
	case "startReview", "startFromDraft":
		return fmt.Sprintf("Starting the review of %s…", p.Intent.Branch)
	case "continueReview":
		return fmt.Sprintf("Continuing the review of %s…", p.Source)
	case "abortReview":
		return fmt.Sprintf("Cancelling the review of %s…", p.Source)
	case "saveReview":
		return fmt.Sprintf("Saving the review of %s for later…", p.Source)
	case "finishReview":
		return fmt.Sprintf("Finishing the review of %s…", p.Source)
	case "undoFinish":
		if p.Force {
			return "Force-undoing the finish…"
		}
		return "Undoing the finish…"
	case "resumeFinish":
		return "Resuming the finish…"
	case "createGuide":
		return "Creating the authoring guide…"
	case "discardGuide":
		return "Discarding your authoring guide…"
	case "discardDraft":
		return fmt.Sprintf("Discarding the reading order for %s…", p.Source)
	case "compareReview":
		return fmt.Sprintf("Comparing %s..%s…", p.CompareLower, p.CompareUpper)
	case "walkthroughInit":
		if p.WalkthroughForce {
			return "Overwriting walkthrough…"
		}
		return "Initializing walkthrough…"
	case "walkthroughBuild":
		return "Building walkthrough…"
	case "next":
		return "Moving to the next entry…"
	case "prev":
		return "Moving to the previous entry…"
	case "setBase":
		return "Changing the base branch…"
	case "setRemote":
		return "Changing the remote…"
	case "cleanReview", "discardInventory", "discardFixes", "discardAllFixes":
		return "Cleaning review leftovers…"
	default:
		return "Working…"
	}
}

func DraftValidationProgress(branch string) string {
	return fmt.Sprintf("Validating your draft for %s…", branch)
}

func StartLayoutTitle(branch string) string {
	return fmt.Sprintf("Start reviewing %s — how do you want to read it?", branch)
}

func DraftWritingProgress(branch string) string {
	return fmt.Sprintf("Preparing the reading order for %s…", branch)
}

func DraftUpdated(kept, added, dropped int) string {
	if added == 0 && dropped == 0 {
		return fmt.Sprintf("Reading order updated: nothing moved, %d kept.", kept)
	}
	text := fmt.Sprintf("Reading order updated: %d kept", kept)
	if added > 0 {
		text += fmt.Sprintf(", %d added", added)
	}
	if dropped > 0 {
		text += fmt.Sprintf(", %d no longer in the PR", dropped)
	}
	return text + "."
}

// --- support ----------------------------------------------------------------

const (
	SupportStarURL = "https://github.com/EzeVillo/git-review-workflow"
	SupportBugURL  = "https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml"
)

// --- section titles ---------------------------------------------------------

const (
	WalkthroughSectionTitle = "Walkthrough"
	CompareSectionTitle     = "Compare"
	SettingsSectionTitle    = "Settings"
	SupportSectionTitle     = "Support"
)

// --- labels: the no-review setup step ---------------------------------------

const (
	SetupQuestion      = "Which branch do pull requests land on in this repo?"
	ChooseBranchLabel  = "Choose the branch"
	ChangeBaseLabel    = "Change the base branch"
	ChangeRemoteLabel  = "Change remote"
	NoActiveReviewNote = "No active review on this branch."
	StartReviewLabel   = "Start a review"

	// ReviewsCompareAgainstNote / BaseLine / RemoteLine / RemoteOptionalLine
	// carry the canonical's own placeholder spelling ("{base}", "{remote}")
	// rather than a Go verb, matching CliMissingTitle/CliOutdatedTitle's
	// "{min}" — render.go interpolates with strings.ReplaceAll, never fmt.
	ReviewsCompareAgainstNote = "Reviews compare the branch you are reading against it. Usually main or develop."
	BaseLine                  = "Base: {base}."
	RemoteLine                = "Remote: {remote}."
	RemoteOptionalLine        = "Remote: {remote} (optional)."
)

// --- copy: finish-pending, finish-conflict, out-of-range, error -------------

const (
	FinishPendingLine1 = "Your edits are on {destination}, staged and ready to commit."
	FinishPendingLine2 = "Commit and push them from Source Control. Until you clean up, this is still undoable."

	FinishConflictBanner = "This finish stopped at a conflict. Resolve the markers, then continue — or undo it to go back to editing."

	OutOfRangeMessage = "The cursor is out of range: the base moved."
	ErrorMessage      = "Something went wrong reading the review state."

	// FilesInCommitHeading / FilesInReviewHeading keep the canonical's "{n}"
	// spelling too, for the same reason.
	FilesInCommitHeading = "{n} file(s) in this commit"
	FilesInReviewHeading = "{n} file(s) in this review"
)

// --- labels: the walkthrough row and the two guides -------------------------

const (
	// WalkthroughInitLabel / WalkthroughUpdateLabel / WalkthroughStartOverLabel
	// mirror `walkthrough_row.action_labels:` — the single action's label
	// depends on the file's state, because the same verb creates and
	// updates.
	WalkthroughInitLabel      = "Init"
	WalkthroughUpdateLabel    = "Update"
	WalkthroughStartOverLabel = "Start over"
	WalkthroughBuildLabel     = "Build"

	CopyForAgentLabel   = "Copy for agent"
	OpenWalkthroughName = "Open the walkthrough"
	OpenGuideName       = "Open the guide"
	DiscardGuideName    = "Discard the guide"
	CreateGuideLabel    = "Create"

	// WalkthroughInitChoiceTitle / the two buttons: the reconcile-or-start-
	// over question asked BEFORE invoking init on a branch that already has
	// a walkthrough (walkthrough_row.init_choice). Reuses the same two verb
	// labels as the row's own action button.
	WalkthroughInitChoiceTitle = "This branch already has a walkthrough."

	// WalkthroughUpdateDetail / WalkthroughStartOverDetail: the picker's two
	// items each carry one half of what used to be a single dialog body —
	// the SelectOverlay shape draws a Detail line per item rather than one
	// shared paragraph, so the choice and its consequence sit next to each
	// other instead of above both options.
	WalkthroughUpdateDetail    = "Update keeps everything you already wrote for files that are still in the PR, and adds the ones that are new."
	WalkthroughStartOverDetail = "Start over replaces it with a blank list. The file is committed to the PR, so git checkout -- .review/walkthrough.md brings the old one back."

	RepositoryGuideLabel = "Repository guide"
	YourGuideLabel       = "Your guide"

	ReviewsInThisRepositoryHeading = "Reviews in this repository"
	ReadingOrdersFinishedHeading   = "Reading orders you finished with"
	ReadingOrdersFinishedNote      = "Their review is over; the files are still here"
	EditsExtractedHeading          = "Edits you extracted"
	EditsExtractedNote             = "One branch per finish; commit and push them from Source Control, or drop them here"
)

// --- showWhy states / walkthrough-degraded note (T094) ----------------------
//
// Neither string is declared in the canonical: showWhy's own failed-state
// text and the degraded-to-whole note are per-client UI copy, the same way
// vscode-extension/src/views/panelHtml.ts's renderWhy() and renderNotes()
// literals are — nothing here needs to be byte-for-byte with the other
// three, only true.

const (
	// WhyFailedNote is shown ONLY when showWhy's own `status --why` call
	// itself could not answer (a timeout, a spawn failure, a nonzero exit)
	// — never for a genuinely empty answer, which is WhyAbsent and draws
	// nothing at all (the same silence render.go always drew before this
	// state existed).
	WhyFailedNote = "Could not read the why for this entry."

	// WalkthroughDegradedToWholeNote: a walkthrough that could not be
	// applied (broken or stale) never fails a review — it degrades to
	// whole, with this note, and the review stays usable (CLAUDE.md § Walk
	// y walkthrough).
	WalkthroughDegradedToWholeNote = "The walkthrough does not cover the review's current range; showing the full range diff."
)

// --- labels: review body -----------------------------------------------------

const (
	OpenInEditorLabel = "open in editor"
	FileLabel         = "File"
	DiffLabel         = "Diff"
	PreviousEntryName = "Previous entry"
	NextEntryName     = "Next entry"
)

// --- labels: draft rows -------------------------------------------------------

const (
	ValidateAndStartLabel   = "Validate and start"
	OpenReadingOrderName    = "Open the reading order"
	DiscardReadingOrderName = "Discard the reading order"
)

// --- labels: inventory, fixes, finish ----------------------------------------

const (
	ContinueLabel         = "Continue"
	DiscardLabel          = "Delete"
	DiscardLeftoverLabel  = "Delete leftover"
	DiscardExtractedName  = "Discard the extracted edits"
	DiscardAllFixesLabel  = "Discard all"
	CompareRevisionsLabel = "Compare revisions"
	DoneCleanUpLabel      = "Done, clean up"
	UndoLabel             = "Undo"
	HowToFixItLabel       = "How to fix it"
	StarOnGitHubLabel     = "Star on GitHub"
	ReportABugLabel       = "Report a bug"
	CopyInstallLabel      = "Copy"
	CurrentBranchTooltip  = "You are on this branch; switch away first"
)

// --- tooltips (contracts/client-product-surface.yaml `tooltip*:`) -----------
//
// openAllChanges' tooltip ("Open every change in this review at once") is
// deliberately NOT here: the action is not_in: [tui] (T006), so this client
// never draws the control it would belong to.

const (
	OpenGuideDisabledTooltip      = "There is no guide yet"
	DiscardGuideTooltip           = "Delete your guide"
	DiscardDraftTooltip           = "Delete this reading order"
	StartFromDraftTooltip         = "Check the order, then start reading"
	StartFromDraftDisabledTooltip = "This file lost its header, so it cannot be checked. Delete it and write a new one."
	StartFromDraftUnfilledTooltip = "Every file still needs a number and a line saying why it matters"
	DiscardFixesTooltip           = "Delete this branch of edits"

	// ContinueReviewDisabledOrphanTooltip / ContinueReviewDisabledActiveTooltip:
	// the two reasons startFromDraft's sibling, continueReview, can be
	// disabled on a saved row — a broken (orphan) saved review has nothing
	// left to resume, and a review already active elsewhere for the same
	// source is what `git review continue` itself refuses with "is already
	// active".
	ContinueReviewDisabledOrphanTooltip = "This review cannot be resumed — its details are gone"
	ContinueReviewDisabledActiveTooltip = "You are already reviewing this branch"

	DiscardSavedReviewTooltip    = "Delete this paused review and its edits"
	DiscardLeftoverBranchTooltip = "Delete this leftover branch"
)

// --- badges: guide state, walkthrough state, fixes state --------------------
//
// Three small maps, one per `states:`/`badges:` block the canonical
// declares next to guide_rows/walkthrough_row/fixes_rows. Kept as data
// instead of a switch in render.go so the wording lives in exactly one
// place, like every other string in this file.

// GuideBadge mirrors `guide_rows.states:`. `absent` reads "none" rather than
// "empty" on purpose (guide_rows.controls' own comment): the two are not
// synonyms — "empty" is a file with nothing in it, "absent" is no file at
// all, and that distinction is what decides whether the row's button opens
// or creates.
var GuideBadge = map[GuideState]string{
	GuideInForce: "in force",
	GuideEmpty:   "empty",
	GuideAbsent:  "none",
}

// WalkthroughBadge mirrors `walkthrough_row.badges:`.
var WalkthroughBadge = map[WalkthroughState]string{
	WalkthroughInSync:       "up to date",
	WalkthroughStale:        "may be out of date",
	WalkthroughSuperseded:   "from a merged PR",
	WalkthroughUnknownState: "state unknown",
	WalkthroughAbsent:       "none",
}

// WalkthroughInitButtonLabel mirrors `walkthrough_row.action_labels:`: the
// SAME verb creates and updates, so the button's own label is the only
// thing that tells the reviewer which of the two is about to happen.
func WalkthroughInitButtonLabel(state WalkthroughState) string {
	switch state {
	case WalkthroughSuperseded:
		return WalkthroughStartOverLabel
	case WalkthroughAbsent:
		return WalkthroughInitLabel
	default:
		return WalkthroughUpdateLabel
	}
}

// FixesBadge mirrors `fixes_rows.badges:`.
var FixesBadge = map[FixesState]string{
	FixesEmpty:    "empty",
	FixesMerged:   "merged",
	FixesUnmerged: "unmerged",
	FixesUnknown:  "unknown",
}

// FixesCostSentence is the first half of discardFixes' confirmation detail:
// what deleting THIS branch of extracted edits actually costs, per the
// CLI's own report of it — never re-derived client-side, since only the CLI
// can ask git whether those commits are integrated.
func FixesCostSentence(state FixesState) string {
	switch state {
	case FixesEmpty:
		return "Nothing was ever committed on it, so no work of yours is lost."
	case FixesMerged:
		return "Its commits are already in the base branch."
	case FixesUnmerged:
		return "It has commits the base branch does not have — deleting it loses them."
	default:
		return "There is no base branch configured, so git cannot tell whether its commits are integrated."
	}
}

// DiscardFixesSessionSuffix is appended to FixesCostSentence when the
// review-fixes/* branch's own review/* session is still open (FixesRecord.
// Session): discarding the edits does not also give up the finish's undo,
// and saying so is the difference between reading the warning and clicking
// through it.
const DiscardFixesSessionSuffix = " You can still undo the finish afterwards."

// cannotBeUndoneSuffix closes discardFixes' confirmation the same way every
// other destructive dialog in this file does.
const cannotBeUndoneSuffix = " It cannot be undone."

// DiscardFixesConfirmDetail assembles discardFixes' confirmation detail from
// the CLI's own report of the branch (never re-derived): what it costs, plus
// whether the finish it came from can still be undone.
func DiscardFixesConfirmDetail(state FixesState, session bool) string {
	detail := FixesCostSentence(state)
	if session {
		detail += DiscardFixesSessionSuffix
	}
	return detail + cannotBeUndoneSuffix
}

// --- mutation cycle (Phase 6): confirmations, discard/stale notices --------
//
// StaleNotice / MutationDiscardedNotice are NOT declared in the canonical's
// strings: — neither is JetBrains' UserCopy.DISCARD_BUSY or Visual Studio's
// MutationLock.DiscardReason. They are implementation-detail messages the
// three IDE clients already share byte for byte purely by convention
// (JetBrains' UserCopy.STALE / DISCARD_BUSY, Visual Studio's UserCopy.Stale /
// MutationLock.DiscardReason); this is the fourth copy of the same two
// lines.
const (
	StaleNotice             = "The repository changed while you were deciding, so nothing happened."
	MutationDiscardedNotice = "Another operation is already in progress"
)

// --- confirmation copy: abort / save / undo-force --------------------------
//
// Titles carry the canonical's own "{source}" placeholder spelling, like
// BaseLine/RemoteLine above — render.go's confirm overlay interpolates with
// strings.ReplaceAll, never fmt.
const (
	AbortReviewConfirmTitle  = "Cancel the review of {source}?"
	AbortReviewConfirmDetail = "This returns to the branch you started the review from; your uncommitted edits will be discarded."
	CancelReviewLabel        = "Cancel Review"

	SaveReviewConfirmTitle  = "Save the review of {source} for later?"
	SaveReviewConfirmDetail = "This pauses the review and returns to the branch you started from; your edits are kept and you can resume later."
	SaveForLaterLabel       = "Save for Later"

	ContinueReviewConfirmTitle  = "Continue the saved review of {source}?"
	ContinueReviewConfirmDetail = "This switches to review/{source} and restores your edits in the working tree."

	UndoFinishConfirmTitleFinishPending  = "Undo this finish?"
	UndoFinishConfirmDetailFinishPending = "This returns you to the review branch with your edits restored."
	UndoFinishConfirmDetailConflict      = "This discards any in-progress resolution and returns you to editing the review."
	UndoFinishLabel                      = "Undo Finish"

	// DiscardWorkAndUndoDetail/Label: the SECOND, stronger confirmation
	// undoFinish's own `--force` retry shows — never the first choice
	// (contracts/cli-invocation.md prohibition 8) and only after the CLI's
	// own stderr from a plain `--abort` names `--force` as the way out.
	DiscardWorkAndUndoDetail = "This permanently discards the work made since the finish. It cannot be undone."
	DiscardWorkAndUndoLabel  = "Discard Work and Undo"

	FinishReadySuffix = " is ready."
)

// --- confirmation copy: the row/footer mutations Phase 7 wires ------------
//
// Verbatim (translated to Go's "{placeholder}" + interpolate() convention)
// from vscode-extension/src/review/housekeeping.ts's confirmCopyFor and the
// three commands/*.ts files that build a discardDraft/discardGuide dialog
// by hand — the fourth copy of the same text, same reasoning: name the real
// verb, say what it costs, never a generic "are you sure?".
const (
	DiscardDraftConfirmTitle  = "Discard the reading order you wrote for {source}?"
	DiscardDraftConfirmDetail = "This deletes {path}. It cannot be undone."
	// DiscardConfirmLabel: the accept button on the discardDraft/discardGuide
	// dialogs — "Discard", not "Delete" (DiscardLabel above): that one is
	// discardInventory's ROW label, which VS Code's own confirmCopyFor keeps
	// as "Delete" even in its confirmation, a different word for a different
	// button.
	DiscardConfirmLabel = "Discard"

	DiscardGuideConfirmTitle  = "Discard the authoring guide you wrote?"
	DiscardGuideConfirmDetail = "This deletes {path}. It cannot be undone."

	// DiscardOneReview* / DiscardSavedReview*: discardInventory's two
	// confirmation shapes, chosen by the row's own Saved bit — a leftover,
	// orphaned review/<x> branch (clean) versus a paused review-saved/<x>
	// one (forget --saved).
	DiscardOneReviewConfirmTitle  = "Delete the leftovers from reviewing {source}?"
	DiscardOneReviewConfirmDetail = "This removes the review branch and any edits you extracted from it. Anything you already committed elsewhere stays. It cannot be undone."

	DiscardSavedReviewConfirmTitle  = "Delete the paused review of {source}?"
	DiscardSavedReviewConfirmDetail = "This throws away the edits you had saved with it. It cannot be undone."

	// CleanReviewConfirmTitle/Detail: the finish-pending banner's "Done,
	// clean up" (`clean --keep-fixes <source>`). What is KEPT goes first —
	// this dialog fires from the button that closes the whole cycle, and
	// the one thing that stops a reviewer there is whether clean takes
	// their edits with it. It does not, and saying so before naming what
	// IS lost is the difference between reading the banner and clicking
	// through it.
	CleanReviewConfirmTitle  = "Done with the review of {source}?"
	CleanReviewConfirmDetail = "Your edits stay on {destination} — commit and push them from Source Control. What goes away is being able to undo this finish."
	DoneLabel                = "Done"

	DiscardFixesConfirmTitle = "Delete the edits you extracted from {source}?"

	DiscardAllFixesConfirmTitle  = "Delete every branch of extracted edits?"
	DiscardAllFixesConfirmDetail = "They hold edits you made while reviewing and never committed anywhere else. Nothing you are reviewing right now is touched. It cannot be undone."
	// DeleteAllLabel: the confirm dialog's accept button — "Delete all",
	// distinct from DiscardAllFixesLabel ("Discard all"), the ROW button
	// that opens it. Same split as DiscardConfirmLabel/DiscardLabel above.
	DeleteAllLabel = "Delete all"

	WalkthroughBuildConfirmTitle  = "Check and renumber the walkthrough?"
	WalkthroughBuildConfirmDetail = "This puts the files in the order you wrote and numbers them 1 to N. If something is missing, nothing changes and you will see what to fix."
)

// --- start assistant / setBase / setRemote pickers --------------------------

const (
	StartAssistantBranchTitle = "Which branch do you want to review?"
	StartAssistantSourceTitle = "Where should its tip come from?"
	StartAssistantRangeTitle  = "How much of it?"
	StartAssistantLayoutTitle = "How do you want to read it?"
	NoBranchesForReview       = "No branches to pick a review from were found."

	SourceRemoteLabel  = "Remote"
	SourceLocalLabel   = "Local"
	SourceOfflineLabel = "Offline (local, no fetch)"

	RangeFullLabel  = "The whole PR"
	RangeDeltaLabel = "Only what changed since your last review"

	LayoutWalkLabel  = "Walkthrough order"
	LayoutKeysLabel  = "Walkthrough order, keys only"
	LayoutStepLabel  = "One commit at a time"
	LayoutWholeLabel = "The whole diff at once"

	LayoutDraftLabel        = "Build a reading order first"
	LayoutDraftDetail       = "nobody wrote one for this PR; otherwise you read the whole diff"
	LayoutDraftResumeLabel  = "Finish the reading order you started"
	LayoutDraftResumeDetail = "pick up the one you left half-written"
	LayoutDraftUpdateLabel  = "Update the reading order you wrote"
	LayoutDraftUpdateDetail = "the PR moved on; keeps the whys whose files are still in range"

	SetBaseTitle   = "Which branch do pull requests land on?"
	SetRemoteTitle = "Which remote should reviews fetch from?"

	// CompareLowerTitle / CompareUpperTitle: compareReview's own two free-text
	// questions (T089/T093) — compare has no `offer` record to pick from
	// (unlike start's branch step), so the CLI's own rejection of a bad name
	// is the validation, exactly as compareReview.ts's own comment notes.
	CompareLowerTitle   = "Compare against which revision?"
	CompareUpperTitle   = "Compare to which revision?"
	RevisionPlaceholder = "branch, tag or commit"

	CompareReviewConfirmTitle  = "Compare {lower}..{upper}?"
	CompareReviewConfirmDetail = "This checks out a new branch to show the comparison, read-only. If you have unsaved edits elsewhere, save or finish first."

	FinishDestinationTitle        = "Where should your edits go?"
	FinishDestinationBranchLabel  = "A separate branch"
	FinishDestinationBranchDetail = "review-fixes/<branch>, staged on top of the PR tip"
	FinishDestinationOntoLabel    = "Onto the PR branch itself"
	FinishDestinationOntoDetail   = "stage the edits directly on the PR branch"
)
