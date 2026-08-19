using System.Diagnostics;
using System.IO;
using GitReview.Domain;
using GitReview.Host;
using GitReview.VS.Diff;
using GitReview.VS.Wizards;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// The full action matrix: the 27 product actions plus the panel-only controls, each
/// with the confirmation, picker and staleness re-check its counterpart has in VS Code
/// and IntelliJ. Confirmation and error copy come from <see cref="UserCopy"/> and
/// <see cref="HousekeepingLogic"/>, so all three clients say the same words.
///
/// Every action is answered here whether it was clicked in the panel or picked from
/// Tools → git review: the menu routes through the panel's own action path, so there is
/// one implementation per action rather than one per surface.
/// </summary>
public sealed class ActionDispatcher
{
    private readonly GitReviewPanelController _panel;
    private readonly PanelHost _host;

    /// <summary>The walkthrough the author commits, relative to the repository root.</summary>
    private const string WalkthroughPath = ".review/walkthrough.md";

    /// <summary>
    /// Cap on the files a single commit's Diff opens at once, same as the JetBrains
    /// client: Visual Studio gives each one its own comparison window, and a commit that
    /// touches two hundred files should not open two hundred of them.
    /// </summary>
    private const int CommitDiffFileCap = 20;

    public ActionDispatcher(GitReviewPanelController panel, PanelHost? host = null)
    {
        _panel = panel;
        _host = host ?? new PanelHost();
        panel.HostAction += HandleAsync;
    }

    private ReviewState State => _panel.State.Current;
    private string? Cwd => _host.Cwd?.Invoke();

    public async Task HandleAsync(string wire, int? index, string? supportLinkId)
    {
        switch (wire)
        {
            case "refresh":
                await _panel.RefreshAsync().ConfigureAwait(true);
                return;

            case "next":
            case "prev":
                await NavigateAsync(wire).ConfigureAwait(true);
                return;

            case "copyCliInstall":
            {
                var cmd = State.Situation == Situation.CliOutdated
                    ? InstallHint.NpmUpdateCmd
                    : InstallHint.NpmInstallCmd;
                System.Windows.Clipboard.SetText(cmd);
                return;
            }

            case "installCli":
                OpenUrl(UserCopy.InstallDocsUrl);
                return;

            case "openSupport":
            {
                var url = SupportLinks.UrlFor(supportLinkId) ?? SupportLinks.StarUrl;
                OpenUrl(url);
                return;
            }

            case "outOfRangeHelp":
            {
                var stderr = State.Stderr?.Trim() ?? "";
                GitReviewDialogs.Warning(
                    stderr.Length > 0 ? stderr : UserCopy.OutOfRangeFallback,
                    "How to fix it");
                return;
            }

            case "showCliLog":
            {
                var log = string.Join("\n", CliInvoker.CliLogSink.Snapshot());
                var text = string.IsNullOrEmpty(log) ? "(empty)" : log;
                if (_host.OpenText is not null) await _host.OpenText(text).ConfigureAwait(true);
                else GitReviewDialogs.Info(text, "git review CLI log");
                return;
            }

            case "startReview":
                await StartReviewAsync().ConfigureAwait(true);
                return;

            case "abortReview":
            {
                var source = State.State?.Source;
                if (source is null) return;
                if (!GitReviewDialogs.Confirm(
                        UserCopy.AbortTitle(source), UserCopy.AbortDetail, UserCopy.AbortButton))
                {
                    return;
                }
                await RunAsync("abortReview", progress: UserCopy.AbortingProgress(source))
                    .ConfigureAwait(true);
                return;
            }

            case "saveReview":
            {
                var source = State.State?.Source;
                if (source is null) return;
                if (!GitReviewDialogs.Confirm(
                        UserCopy.SaveTitle(source), UserCopy.SaveDetail, UserCopy.SaveButton))
                {
                    return;
                }
                await RunAsync("saveReview", progress: UserCopy.SavingProgress(source))
                    .ConfigureAwait(true);
                return;
            }

            case "finishReview":
                await FinishAsync().ConfigureAwait(true);
                return;

            case "undoFinish":
                await UndoFinishAsync().ConfigureAwait(true);
                return;

            case "resumeFinish":
                // Which side the finish was aimed at is state, not a new decision: the
                // resume has to target what the interrupted finish targeted.
                await RunAsync(
                    "resumeFinish",
                    new ActionParams.ResumeFinish(State.Finish?.Onto == true),
                    progress: UserCopy.ResumeProgress).ConfigureAwait(true);
                return;

            case "continueReview":
                await ContinueAsync(index).ConfigureAwait(true);
                return;

            case "discardInventory":
                await DiscardInventoryAsync(index).ConfigureAwait(true);
                return;

            // Draft block (012): four BODY controls. No .vsct entry, no command id,
            // no Tools menu item — the canonical's count of 27 does not move.
            case "openDraft":
            {
                var draft = DraftRowAt(index);
                if (draft is null || _host.OpenPath is null) return;
                await _host.OpenPath(draft.Path).ConfigureAwait(true);
                return;
            }

            case "copyDraftPrompt":
            {
                var draft = DraftRowAt(index);
                if (draft is null) return;
                System.Windows.Clipboard.SetText(UserCopy.DraftAgentPrompt(draft.Path));
                return;
            }

            case "startFromDraft":
                await StartFromDraftAsync(index).ConfigureAwait(true);
                return;

            case "discardDraft":
                await DiscardDraftAsync(index).ConfigureAwait(true);
                return;

            case "cleanReview":
                await CleanAsync().ConfigureAwait(true);
                return;

            case "forgetReview":
                await ForgetAsync().ConfigureAwait(true);
                return;

            case "setBase":
                await SetConfigAsync(baseBranch: true).ConfigureAwait(true);
                return;

            case "setRemote":
                await SetConfigAsync(baseBranch: false).ConfigureAwait(true);
                return;

            case "compareReview":
                await CompareAsync().ConfigureAwait(true);
                return;

            case "walkthroughInit":
                await WalkthroughInitAsync().ConfigureAwait(true);
                return;

            case "walkthroughBuild":
                await WalkthroughBuildAsync().ConfigureAwait(true);
                return;

            case "previewEdits":
            case "previewEditsStat":
                if (_host.PreviewEdits is not null)
                    await _host.PreviewEdits(wire == "previewEditsStat").ConfigureAwait(true);
                return;

            case "goToEntry":
                await GoToEntryAsync().ConfigureAwait(true);
                return;

            case "openEntry":
                await OpenEntryAsync().ConfigureAwait(true);
                return;

            case "openChange":
                await OpenChangeAsync(index).ConfigureAwait(true);
                return;

            case "showWhy":
            {
                if (_host.OpenText is null) return;
                // The panel's own why, not a model rebuilt here: BuildPanelModel takes
                // the text as an input, so a model built without it reads as one whose
                // why is still loading and this action would never open anything.
                var why = _panel.Why?.Text;
                if (string.IsNullOrEmpty(why)) return;
                await _host.OpenText(why!).ConfigureAwait(true);
                return;
            }
        }
    }

    // -- reading ------------------------------------------------------------

    /// <summary>
    /// Next / prev. A navigation that lands on the same position is not a failure: the
    /// CLI says why on stdout (first or last entry), and that line is the answer.
    /// </summary>
    private async Task NavigateAsync(string wire)
    {
        if (State.Situation != Situation.Review) return;
        var before = State.State?.Position;
        var result = await _panel.Mutations.RunActionAsync(wire).ConfigureAwait(true);
        await _panel.RefreshAsync().ConfigureAwait(true);
        if (result is null) return;
        if (result.ExitCode is not 0 || result.TimedOut)
        {
            // Information, not error — same as VS Code for a refused navigation.
            GitReviewDialogs.Info(
                CliMessage.CliErrorText(result.Stderr, result.Stdout, UserCopy.NavigateFailed(wire)));
            return;
        }
        var after = _panel.State.Current.State?.Position;
        if (before != after) return;
        var message = CliMessage.FirstCliLine(result.Stdout);
        if (message.Length > 0) GitReviewDialogs.Info(message);
    }

    /// <summary>
    /// The whole entry sequence, in the CLI's order. Opens what is picked; it does not
    /// move the cursor — the CLI has no verb for jumping to an arbitrary position, and
    /// synthesising one out of next/prev would be behaviour this client invented.
    /// </summary>
    private async Task GoToEntryAsync()
    {
        var state = State;
        if (!SituationIds.IsReviewReadable(state.Situation) || state.EntriesList.Count == 0) return;
        var labels = state.EntriesList
            .Select(e =>
            {
                var pick = PanelModelBuilder.EntryPickLabel(
                    e, state.State?.Position, Subject(state, e.Position));
                return pick.Description.Length > 0
                    ? $"{pick.Label}  ({pick.Description})"
                    : pick.Label;
            })
            .ToList();
        var current = state.EntriesList
            .Select((e, i) => (Entry: e, Index: i))
            .FirstOrDefault(x => x.Entry.Position == state.State?.Position);
        var idx = GitReviewDialogs.Choose(
            UserCopy.ProductTitle, "Go to entry", labels, current.Index);
        if (idx < 0) return;
        await OpenEntryRecordAsync(state, state.EntriesList[idx]).ConfigureAwait(true);
    }

    private static string? Subject(ReviewState state, int position) =>
        state.Subjects is not null && state.Subjects.TryGetValue(position, out var s) ? s : null;

    private Task OpenEntryAsync()
    {
        var state = State;
        var entry = PanelModelBuilder.CurrentEntry(state.EntriesList, state.State?.Position);
        return entry is null ? Task.CompletedTask : OpenEntryRecordAsync(state, entry);
    }

    /// <summary>
    /// "File" for an entry. In walk and whole an entry is a path, so this is the
    /// working-tree file. In step an entry is a commit, and the only honest thing to open
    /// for a commit is its diff.
    /// </summary>
    private async Task OpenEntryRecordAsync(ReviewState state, EntryRecord entry)
    {
        var mode = state.State?.Mode;
        if (mode is null) return;
        if (mode == ReviewMode.Step)
        {
            await OpenCommitDiffAsync(entry.Id as string).ConfigureAwait(true);
            return;
        }
        if (_host.OpenEntryFile is null) return;
        var display = DisplayOf(entry.Id);
        await _host.OpenEntryFile(display).ConfigureAwait(true);
        _panel.RememberOpened(display);
    }

    /// <summary>
    /// "Diff". Walk and whole diff the base blob against the working tree, which is where
    /// the pull request lives during a review. Step is a commit: with an index it is one
    /// file of it (parent blob vs commit blob, neither side the working tree), without one
    /// it is the whole commit.
    /// </summary>
    private async Task OpenChangeAsync(int? index)
    {
        var state = State;
        var mode = state.State?.Mode;
        if (mode is null) return;

        if (mode == ReviewMode.Step)
        {
            if (index is null)
            {
                var commit = PanelModelBuilder.CurrentEntry(state.EntriesList, state.State?.Position);
                await OpenCommitDiffAsync(commit?.Id as string).ConfigureAwait(true);
                return;
            }
            var file = state.FilesList.FirstOrDefault(f => f.Position == index);
            if (file is null || state.State?.Current is not string sha) return;
            var path = DisplayOf(file.Id);
            await OpenCommitFileDiffAsync(sha, path).ConfigureAwait(true);
            _panel.RememberOpened(path);
            return;
        }

        var entry = index is not null
            ? state.EntriesList.FirstOrDefault(e => e.Position == index)
            : PanelModelBuilder.CurrentEntry(state.EntriesList, state.State?.Position);
        if (entry is null) return;
        var display = DisplayOf(entry.Id);

        var cwd = Cwd;
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        // Which sides this file actually has comes from git, not from the entry name:
        // an entry the reviewer has since reverted has no diff left to show, and a file
        // the pull request adds or deletes only exists on one side. Both are answers,
        // and building the request from the path alone could state neither. Not being able
        // to ask git is a third answer, and not one about the review: reporting it as "no
        // changes left" would state, of a file the walkthrough just pointed at, something
        // this host never checked.
        var changes = await RangeChanges.ForRangeAsync(_panel.Cli, cwd).ConfigureAwait(true);
        if (changes is null)
        {
            GitReviewDialogs.Error(UserCopy.OpenRangeFailed);
            return;
        }
        var change = changes.FirstOrDefault(
            c => c.Path == display || c.After == display || c.Before == display);
        if (change is null)
        {
            GitReviewDialogs.Info(UserCopy.OpenNoChangesLeft(display));
            return;
        }
        await OpenDiffsAsync(new[] { RangeDiff(change) }).ConfigureAwait(true);
        _panel.RememberOpened(display);
    }

    /// <summary>
    /// The review range: HEAD sits at the lower bound with the pull request staged on top,
    /// so "before" is the blob at HEAD and "after" is what the reviewer is editing.
    /// </summary>
    private static DiffRequest RangeDiff(CommitChange change) => new(
        change.Path,
        new DiffSide("HEAD", change.Before, "Base (HEAD)"),
        new DiffSide(null, change.After, "Working tree"));

    private async Task OpenCommitDiffAsync(string? sha)
    {
        if (sha is null) return;
        var cwd = Cwd;
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        var changes = await RangeChanges.ForCommitAsync(_panel.Cli, cwd, sha).ConfigureAwait(true);
        if (changes is null)
        {
            GitReviewDialogs.Error(UserCopy.OpenCommitFailed(sha));
            return;
        }
        if (changes.Count == 0)
        {
            GitReviewDialogs.Info(UserCopy.OpenCommitEmpty(sha));
            return;
        }
        var requests = changes.Take(CommitDiffFileCap).Select(c => CommitDiff(sha, c)).ToList();
        await OpenDiffsAsync(requests).ConfigureAwait(true);
    }

    private async Task OpenCommitFileDiffAsync(string sha, string path)
    {
        var cwd = Cwd;
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        var changes = await RangeChanges.ForCommitAsync(_panel.Cli, cwd, sha).ConfigureAwait(true);
        if (changes is null)
        {
            GitReviewDialogs.Error(UserCopy.OpenCommitFailed(sha));
            return;
        }
        var change = changes.FirstOrDefault(c => c.Path == path || c.After == path || c.Before == path);
        if (change is null)
        {
            GitReviewDialogs.Info(UserCopy.OpenNoChangesLeft(path));
            return;
        }
        await OpenDiffsAsync(new[] { CommitDiff(sha, change) }).ConfigureAwait(true);
    }

    /// <summary>A commit against its parent — neither side is the working tree.</summary>
    private static DiffRequest CommitDiff(string sha, CommitChange change)
    {
        var shortSha = sha.Length > 7 ? sha.Substring(0, 7) : sha;
        return new DiffRequest(
            change.Path,
            new DiffSide($"{sha}^", change.Before, $"{shortSha}^"),
            new DiffSide(sha, change.After, shortSha));
    }

    private async Task OpenDiffsAsync(IReadOnlyList<DiffRequest> requests)
    {
        if (_host.OpenDiffs is null || requests.Count == 0) return;
        await _host.OpenDiffs(requests).ConfigureAwait(true);
    }

    // -- lifecycle ----------------------------------------------------------

    private async Task StartReviewAsync()
    {
        var cwd = Cwd;
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        var started = await StartWizard.RunAsync(
            _panel.Cli,
            _panel.Mutations,
            _panel.State,
            cwd,
            _host).ConfigureAwait(true);
        if (started) await _panel.RefreshAsync().ConfigureAwait(true);
    }

    /// <summary>
    /// Finish. Where the edits land is the one decision, and it is a pick rather than a
    /// yes/no: the two options are sentences, and a message box would have hidden them
    /// behind "Yes" and "No".
    /// </summary>
    private async Task FinishAsync()
    {
        var state = State;
        if (state.Readonly == true)
        {
            GitReviewDialogs.Info(UserCopy.ReadonlyFinish);
            return;
        }
        if (state.State is null) return;
        var source = state.State.Source;
        var reviewBranch = state.State.Branch;

        var idx = GitReviewDialogs.Choose(
            UserCopy.FinishLocationTitle(source),
            UserCopy.FinishLocationPlaceholder,
            new[] { UserCopy.FinishLocationSeparate, UserCopy.FinishLocationOnto });
        if (idx < 0) return;
        var ontoSource = idx == 1;

        var result = await RunAsync(
            "finishReview",
            new ActionParams.FinishOnto(ontoSource),
            progress: UserCopy.FinishingProgress(source)).ConfigureAwait(true);
        if (result is null || result.ExitCode is not 0 || result.TimedOut) return;

        // Derived from refreshed state, never from finish's human stdout.
        var destination = UserCopy.FinishDestination(ontoSource, source);
        var outcome = FinishOutcomeLogic.FinishOutcome(_panel.State.Current, reviewBranch);
        GitReviewDialogs.Info(UserCopy.FinishSuccess(destination, outcome));
    }

    /// <summary>
    /// Undo. When the CLI refuses because the undo would drop work, it names
    /// <c>--force</c> as the escape — and only then is the second, louder confirmation
    /// offered. Any other failure is just reported.
    /// </summary>
    private async Task UndoFinishAsync()
    {
        var detail = State.Situation == Situation.FinishConflict
            ? UserCopy.UndoDetailConflict
            : UserCopy.UndoDetailPending;
        if (!GitReviewDialogs.Confirm(UserCopy.UndoTitle, detail, UserCopy.UndoButton)) return;

        var result = await RunAsync(
            "undoFinish",
            new ActionParams.UndoFinish(false),
            showFailure: false,
            progress: UserCopy.UndoingProgress).ConfigureAwait(true);
        if (result is null || (result.ExitCode == 0 && !result.TimedOut)) return;

        var text = CliMessage.FlattenCliMessage(result.Stderr);
        if (text.Length == 0)
        {
            GitReviewDialogs.Error(UserCopy.UndoAbortFailed);
            return;
        }
        if (!text.Contains("--force", StringComparison.Ordinal))
        {
            GitReviewDialogs.Error(text);
            return;
        }
        if (!GitReviewDialogs.Confirm(text, UserCopy.UndoForceDetail, UserCopy.UndoForceButton)) return;
        await RunAsync(
            "undoFinish",
            new ActionParams.UndoFinish(true),
            progress: UserCopy.ForceUndoingProgress).ConfigureAwait(true);
    }

    /// <summary>
    /// Continue. From an inventory row the review is already known; from the menu it is
    /// picked, and a row that cannot be resumed says so instead of failing in the CLI.
    /// </summary>
    private async Task ContinueAsync(int? index)
    {
        var branches = State.BranchesList;
        if (index is null)
        {
            if (branches.Count == 0)
            {
                GitReviewDialogs.Info(UserCopy.NoSavedReviews);
                return;
            }
            var labels = branches
                .Select((b, i) => PanelModelBuilder.ResumableSourceAt(branches, i) is not null
                    ? $"{b.Name}  (resumable)"
                    : b.Name)
                .ToList();
            var picked = GitReviewDialogs.Choose(
                UserCopy.ProductTitle, "Continue which saved review?", labels);
            if (picked < 0) return;
            index = picked;
        }

        var source = PanelModelBuilder.ResumableSourceAt(branches, index.Value);
        if (source is null)
        {
            GitReviewDialogs.Error(UserCopy.NotResumable);
            return;
        }
        if (!GitReviewDialogs.Confirm(
                UserCopy.ContinueTitle(source),
                UserCopy.ContinueDetail(source),
                UserCopy.ContinueButton))
        {
            return;
        }
        await RunAsync(
            "continueReview",
            new ActionParams.Continue(source),
            progress: UserCopy.ContinuingProgress(source)).ConfigureAwait(true);
    }

    // -- housekeeping -------------------------------------------------------

    /// <summary>
    /// Discard one review. From an inventory row the name is known; from the menu it is
    /// typed, because the reviews the menu can reach are not necessarily the ones this
    /// branch's inventory lists.
    /// </summary>
    private async Task DiscardInventoryAsync(int? index)
    {
        string name;
        if (index is null)
        {
            var typed = GitReviewDialogs.Input(
                "Discard", "Review branch name to discard (e.g. review-saved/feature/x):");
            if (typed is null) return;
            name = typed;
        }
        else
        {
            var branches = State.BranchesList;
            if (index < 0 || index >= branches.Count) return;
            name = branches[index.Value].Name;
        }

        var src = HousekeepingLogic.SourceFromReviewName(name);
        var action = name.StartsWith("review-saved/", StringComparison.Ordinal)
            ? new HousekeepingAction(HousekeepingKind.ForgetSavedOne, src)
            : new HousekeepingAction(HousekeepingKind.CleanOne, src);
        await ConfirmAndRunHousekeepingAsync(action).ConfigureAwait(true);
    }

    /// <summary>
    /// The draft row at <paramref name="index"/>, resolved against the HOST's state. The
    /// index is the only thing a row control carries, and it is never trusted: what ends
    /// up in the CLI comes from here.
    /// </summary>
    private DraftRecord? DraftRowAt(int? index) =>
        PanelModelBuilder.DraftAt(State.DraftsList, index);

    /// <summary>
    /// "Validate and start" on a draft row. The four steps live in the wizard, because
    /// step 4 is the usual start with its confirmation and staleness guard.
    /// </summary>
    private async Task StartFromDraftAsync(int? index)
    {
        var draft = DraftRowAt(index);
        if (draft is null) return;
        var cwd = Cwd;
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        var started = await StartWizard.StartFromDraftAsync(
            _panel.Cli,
            _panel.Mutations,
            _panel.State,
            cwd,
            _host,
            draft).ConfigureAwait(true);
        if (started) await _panel.RefreshAsync().ConfigureAwait(true);
    }

    /// <summary>
    /// Discard THIS row's draft, with a confirmation first: it is prose written by hand.
    /// Never --all — an action on one row does not touch the others.
    /// </summary>
    private async Task DiscardDraftAsync(int? index)
    {
        var draft = DraftRowAt(index);
        if (draft is null) return;
        if (!GitReviewDialogs.Confirm(
                UserCopy.DiscardDraftTitle(draft.Src),
                UserCopy.DiscardDraftDetail(draft.Src, draft.Path),
                UserCopy.DiscardDraftButton))
        {
            return;
        }
        await RunAsync(
            "forgetDraft",
            new ActionParams.ForgetDraft(draft.Src),
            progress: UserCopy.DiscardDraftProgress(draft.Src)).ConfigureAwait(true);
    }

    /// <summary>
    /// Clean. A pending finish is the one case with a single sensible answer — keep the
    /// fixes, drop the rest — so it is offered directly instead of asked about.
    /// </summary>
    private async Task CleanAsync()
    {
        var pending = HousekeepingLogic.PendingFinishInfo(State);
        if (pending is not null)
        {
            await ConfirmAndRunHousekeepingAsync(new HousekeepingAction(
                HousekeepingKind.CleanKeepFixes,
                pending.Value.Source,
                pending.Value.Onto)).ConfigureAwait(true);
            return;
        }

        var idx = GitReviewDialogs.Choose(
            UserCopy.CleanPickTitle,
            "What to delete",
            new[] { UserCopy.CleanOneLabel, UserCopy.CleanAllLabel });
        if (idx < 0) return;
        HousekeepingAction action;
        if (idx == 0)
        {
            var src = PickSourceName(savedOnly: false, forClean: true);
            if (src is null) return;
            action = new HousekeepingAction(HousekeepingKind.CleanOne, src);
        }
        else
        {
            action = new HousekeepingAction(HousekeepingKind.CleanAll);
        }
        await ConfirmAndRunHousekeepingAsync(action).ConfigureAwait(true);
    }

    private async Task ForgetAsync()
    {
        var idx = GitReviewDialogs.Choose(
            UserCopy.ForgetPickTitle,
            "What to discard",
            new[]
            {
                UserCopy.ForgetSavedOneLabel,
                UserCopy.ForgetSavedAllLabel,
                UserCopy.ForgetDeltaOneLabel,
                UserCopy.ForgetDeltaAllLabel,
                UserCopy.ForgetDeltaStaleLabel,
            });
        if (idx < 0) return;

        HousekeepingAction action;
        switch (idx)
        {
            case 0:
            {
                var src = PickSourceName(savedOnly: true, forClean: false);
                if (src is null) return;
                action = new HousekeepingAction(HousekeepingKind.ForgetSavedOne, src);
                break;
            }
            case 1:
                action = new HousekeepingAction(HousekeepingKind.ForgetSavedAll);
                break;
            case 2:
            {
                var src = PickSourceName(savedOnly: false, forClean: false);
                if (src is null) return;
                action = new HousekeepingAction(HousekeepingKind.ForgetDeltaOne, src);
                break;
            }
            case 3:
                action = new HousekeepingAction(HousekeepingKind.ForgetDeltaAll);
                break;
            default:
                action = new HousekeepingAction(HousekeepingKind.ForgetDeltaStale);
                break;
        }
        await ConfirmAndRunHousekeepingAsync(action).ConfigureAwait(true);
    }

    /// <summary>
    /// Which branch a housekeeping verb applies to. The reviews this client knows about
    /// are offered as a list, plus a way out for the ones it does not: a delta marker can
    /// outlive every review branch that would have named it.
    /// </summary>
    private string? PickSourceName(bool savedOnly, bool forClean)
    {
        var branches = State.BranchesList;
        var filtered = savedOnly
            ? branches.Where(b => b.Saved || b.Name.StartsWith("review-saved/", StringComparison.Ordinal))
            : branches;
        var names = filtered
            .Select(b => HousekeepingLogic.SourceFromReviewName(b.Name))
            .Distinct(StringComparer.Ordinal)
            .ToList();

        var title = forClean
            ? UserCopy.CleanBranchTitle
            : savedOnly ? UserCopy.ForgetSavedSourceTitle : UserCopy.ForgetDeltaSourceTitle;

        if (names.Count > 0)
        {
            var options = names.Append(UserCopy.EnterBranchName).ToList();
            var idx = GitReviewDialogs.Choose(title, "Source branch name", options);
            if (idx < 0) return null;
            if (options[idx] != UserCopy.EnterBranchName) return options[idx];
        }

        var prompt = forClean ? UserCopy.CleanBranchPrompt : UserCopy.ForgetSourcePrompt;
        return GitReviewDialogs.Input(title, prompt);
    }

    private async Task ConfirmAndRunHousekeepingAsync(HousekeepingAction action)
    {
        var copy = HousekeepingLogic.ConfirmCopyFor(action);
        if (!GitReviewDialogs.Confirm(copy.Title, copy.Detail, copy.Button)) return;
        // One verb per kind (clean / forget), resolved in the domain.
        var verb = HousekeepingLogic.VerbForHousekeeping(action) == "forget"
            ? "forgetReview"
            : "cleanReview";
        // The confirmation's own question, as a statement: same line the extension
        // puts in its progress notification.
        await RunAsync(
            verb,
            new ActionParams.Housekeeping(action),
            progress: HousekeepingProgress(copy.Title)).ConfigureAwait(true);
    }

    // -- settings -----------------------------------------------------------

    /// <summary>
    /// Base branch / remote. The candidates come from a fresh <c>config --porcelain</c>
    /// rather than the panel's state: the panel only carries them in the no-review
    /// situation, and both of these are reachable in every situation.
    /// </summary>
    private async Task SetConfigAsync(bool baseBranch)
    {
        var cwd = Cwd;
        if (cwd is null)
        {
            GitReviewDialogs.Error(UserCopy.NoSoleRoot);
            return;
        }
        var result = await _panel.Cli.InvokeAsync("config", new[] { "--porcelain" }, cwd)
            .ConfigureAwait(true);
        if (result.ExitCode != 0)
        {
            GitReviewDialogs.CliError(result.Stderr, UserCopy.CouldNotReadConfig, result.Stdout);
            return;
        }
        ConfigPorcelainResult parsed;
        try
        {
            parsed = ConfigPorcelain.ParseConfigPorcelain(result.Stdout);
        }
        catch
        {
            GitReviewDialogs.Error(UserCopy.CouldNotParseConfig);
            return;
        }

        if (baseBranch)
        {
            var candidates = parsed.Candidates
                .OrderByDescending(c => c.Current)
                .ThenBy(c => c.Name, StringComparer.Ordinal)
                .ToList();
            if (candidates.Count == 0)
            {
                GitReviewDialogs.Error(UserCopy.NoBranchesForBase);
                return;
            }
            var idx = GitReviewDialogs.Choose(
                UserCopy.SetBaseTitle,
                UserCopy.SetBasePrompt,
                candidates.Select(ConfigPorcelain.BranchPickerLabel).ToList());
            if (idx < 0) return;
            await RunAsync("setBase", new ActionParams.SetConfig("base", candidates[idx].Name))
                .ConfigureAwait(true);
            return;
        }

        var remotes = parsed.Remotes
            .OrderByDescending(r => r.Current)
            .ThenBy(r => r.Name, StringComparer.Ordinal)
            .ToList();
        if (remotes.Count == 0)
        {
            GitReviewDialogs.Error(UserCopy.NoRemotes);
            return;
        }
        var pick = GitReviewDialogs.Choose(
            UserCopy.SetRemoteTitle,
            UserCopy.SetRemotePrompt,
            remotes.Select(r => r.Current ? $"{r.Name}  (current)" : r.Name).ToList());
        if (pick < 0) return;
        await RunAsync("setRemote", new ActionParams.SetConfig("remote", remotes[pick].Name))
            .ConfigureAwait(true);
    }

    // -- compare / walkthrough ---------------------------------------------

    private async Task CompareAsync()
    {
        var lower = GitReviewDialogs.Input(UserCopy.CompareLowerTitle, "Branch, tag or commit");
        if (lower is null) return;
        var upper = GitReviewDialogs.Input(UserCopy.CompareUpperTitle, "Branch, tag or commit");
        if (upper is null) return;

        var idx = GitReviewDialogs.Choose(
            UserCopy.CompareLayoutTitle,
            UserCopy.CompareLayoutPlaceholder,
            new[]
            {
                "Walkthrough — curated reading order if the upper tip has a walkthrough",
                "Walkthrough — keys only — only entries marked key (--keys)",
                "Commit by commit — one commit at a time (--step)",
                "Whole diff — entire diff at once (--no-walk)",
            });
        if (idx < 0) return;
        var layout = idx switch
        {
            0 => ReviewLayout.Walk,
            1 => ReviewLayout.Keys,
            2 => ReviewLayout.Step,
            _ => ReviewLayout.Whole,
        };
        if (!GitReviewDialogs.Confirm(
                UserCopy.CompareConfirmTitle(lower, upper, layout),
                UserCopy.CompareConfirmDetail,
                UserCopy.CompareButton))
        {
            return;
        }
        var flags = layout switch
        {
            ReviewLayout.Step => new[] { "--step" },
            ReviewLayout.Whole => new[] { "--no-walk" },
            ReviewLayout.Keys => new[] { "--keys" },
            _ => Array.Empty<string>(),
        };
        await RunAsync(
            "compareReview",
            new ActionParams.Compare(flags, lower, upper),
            network: true,
            progress: UserCopy.ComparingProgress(lower, upper)).ConfigureAwait(true);
    }

    /// <summary>
    /// Walkthrough init. A refusal because one already exists is the only failure that
    /// turns into a question, and it is distinguished by the file being there — not by
    /// matching the CLI's wording.
    /// </summary>
    private async Task WalkthroughInitAsync()
    {
        var cwd = Cwd;
        var first = await RunAsync(
            "walkthroughInit",
            new ActionParams.WalkthroughInit(false),
            showFailure: false,
            progress: UserCopy.WalkthroughInitProgress).ConfigureAwait(true);
        if (first is null) return;
        if (first.ExitCode == 0 && !first.TimedOut)
        {
            await OpenWalkthroughAsync(cwd).ConfigureAwait(true);
            return;
        }

        var walkthrough = WalkthroughFile(cwd);
        var exists = walkthrough is not null && File.Exists(walkthrough);
        if (!exists)
        {
            GitReviewDialogs.CliError(first.Stderr, UserCopy.WalkthroughInitFailed, first.Stdout);
            return;
        }
        if (!GitReviewDialogs.Confirm(
                UserCopy.WalkthroughExistsTitle,
                UserCopy.WalkthroughExistsDetail,
                UserCopy.WalkthroughOverwriteButton))
        {
            return;
        }
        var forced = await RunAsync(
            "walkthroughInit",
            new ActionParams.WalkthroughInit(true),
            progress: UserCopy.WalkthroughOverwriteProgress).ConfigureAwait(true);
        if (forced is not null && forced.ExitCode == 0 && !forced.TimedOut)
            await OpenWalkthroughAsync(cwd).ConfigureAwait(true);
    }

    private async Task WalkthroughBuildAsync()
    {
        if (!GitReviewDialogs.Confirm(
                UserCopy.WalkthroughBuildTitle,
                UserCopy.WalkthroughBuildDetail,
                UserCopy.WalkthroughBuildButton))
        {
            return;
        }
        var cwd = Cwd;
        var result = await RunAsync(
            "walkthroughBuild", progress: UserCopy.WalkthroughBuildProgress).ConfigureAwait(true);
        if (result is null || result.ExitCode is not 0 || result.TimedOut) return;
        GitReviewDialogs.Info(UserCopy.WalkthroughBuilt);
        await OpenWalkthroughAsync(cwd).ConfigureAwait(true);
    }

    private static string? WalkthroughFile(string? cwd) => cwd is null
        ? null
        : Path.Combine(cwd, WalkthroughPath.Replace('/', Path.DirectorySeparatorChar));

    private async Task OpenWalkthroughAsync(string? cwd)
    {
        var path = WalkthroughFile(cwd);
        if (path is null || _host.OpenPath is null || !File.Exists(path)) return;
        await _host.OpenPath(path).ConfigureAwait(true);
    }

    // -- running ------------------------------------------------------------

    /// <summary>
    /// Every mutation goes through here: re-read the state after the confirmation, refuse
    /// if the repository moved while the dialog was open, then run under the mutation lock
    /// and refresh. Returns null when there was nothing to report on (busy, or stale) —
    /// those already told the reviewer what happened.
    /// </summary>
    /// <summary>
    /// One mutation: staleness re-check, the CLI call, the refresh that follows, and a
    /// failure reported the way its counterpart reports it. <paramref name="progress"/>
    /// is what the shell says while that runs -- the reviewer who started a finish from
    /// the menu is not necessarily watching the panel's greyed-out buttons. It covers
    /// the two refreshes as well as the verb: on Windows those are seconds of their own.
    /// </summary>
    private async Task<InvokeResult?> RunAsync(
        string action,
        ActionParams? params_ = null,
        bool showFailure = true,
        bool network = false,
        string? progress = null)
    {
        using var reporting = progress is not null && _host.Progress is not null
            ? _host.Progress(progress)
            : null;
        var token = StaleGuard.CaptureToken(_panel.State.Current);
        await _panel.RefreshAsync().ConfigureAwait(true);
        if (!StaleGuard.TokenStillValid(token, _panel.State.Current))
        {
            GitReviewDialogs.Info(UserCopy.StaleMessage(action, IsForce(params_)));
            return null;
        }

        var result = await _panel.Mutations
            .RunActionAsync(action, params_, network: network)
            .ConfigureAwait(true);
        // Discarded because another mutation holds the lock. The notice belongs to
        // the lock's own listener, which says it for every surface; saying it here
        // as well would show it twice for a click in the panel.
        if (result is null) return null;
        if ((result.ExitCode is not 0 || result.TimedOut) && showFailure)
        {
            GitReviewDialogs.CliError(
                result.Stderr, UserCopy.FailureFallback(action, params_), result.Stdout);
        }
        await _panel.RefreshAsync().ConfigureAwait(true);
        return result;
    }

    /// <summary>The confirmation title turned into a running-now line ("Clean up?" -> "Clean up...").</summary>
    private static string HousekeepingProgress(string title) =>
        title.EndsWith("?", StringComparison.Ordinal)
            ? title.Substring(0, title.Length - 1) + "…"
            : title;

    private static bool IsForce(ActionParams? params_) =>
        params_ is ActionParams.UndoFinish { Force: true };

    private static string DisplayOf(object id) =>
        id is PathRef pathRef ? pathRef.Display : id.ToString() ?? "";

    private static void OpenUrl(string url) =>
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
