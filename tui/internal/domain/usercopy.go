package domain

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
)

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

// --- start assistant / setBase / setRemote pickers --------------------------

const (
	StartAssistantBranchTitle = "Which branch do you want to review?"
	StartAssistantSourceTitle = "Where should its tip come from?"
	StartAssistantRangeTitle  = "How much of it?"
	StartAssistantLayoutTitle = "How do you want to read it?"

	SourceRemoteLabel  = "Remote"
	SourceLocalLabel   = "Local"
	SourceOfflineLabel = "Offline (local, no fetch)"

	RangeFullLabel  = "The whole PR"
	RangeDeltaLabel = "Only what changed since your last review"

	LayoutWalkLabel  = "Walkthrough order"
	LayoutKeysLabel  = "Walkthrough order, keys only"
	LayoutStepLabel  = "One commit at a time"
	LayoutWholeLabel = "The whole diff at once"

	SetBaseTitle   = "Which branch do pull requests land on?"
	SetRemoteTitle = "Which remote should reviews fetch from?"

	FinishDestinationTitle        = "Where should your edits go?"
	FinishDestinationBranchLabel  = "A separate branch"
	FinishDestinationBranchDetail = "review-fixes/<branch>, staged on top of the PR tip"
	FinishDestinationOntoLabel    = "Onto the PR branch itself"
	FinishDestinationOntoDetail   = "stage the edits directly on the PR branch"
)
