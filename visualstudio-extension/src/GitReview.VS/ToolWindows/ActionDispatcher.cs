using System.Diagnostics;
using System.IO;
using GitReview.Domain;
using GitReview.Host;
using GitReview.VS.Diff;
using GitReview.VS.Wizards;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// The full action matrix: the 27 product actions plus the panel-only controls, each
/// with its own confirmation, picker and staleness re-check. Confirmation and error
/// copy come from <see cref="UserCopy"/> and <see cref="HousekeepingLogic"/>.
///
/// Every action is answered here whether clicked in the panel or picked from Tools →
/// git review: the menu routes through the panel's own action path, one implementation
/// per action rather than per surface.
/// </summary>
public sealed class ActionDispatcher
{
    private readonly GitReviewPanelController _panel;
    private readonly PanelHost _host;

    /// <summary>The walkthrough the author commits, relative to the repository root.</summary>
    private const string WalkthroughPath = ".review/walkthrough.md";

    /// <summary>
    /// Cap on the files a single commit's Diff opens at once: Visual Studio gives each
    /// one its own comparison window, and a commit that touches two hundred files
    /// should not open two hundred of them.
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
                if (!GitReviewDialogs.Confirm(ControlId.AbortReview,
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
                if (!GitReviewDialogs.Confirm(ControlId.SaveReview,
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

            // Draft block: four BODY controls. No .vsct entry, no command id, no Tools
            // menu item — the canonical's count of 27 does not move.
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

            // Authoring-guide block: same shape as the draft block above.
            case "openGuide":
            {
                var guide = GuideRowAt(index);
                if (guide is null || guide.State == GuideState.Absent || _host.OpenPath is null) return;
                await _host.OpenPath(guide.Path).ConfigureAwait(true);
                return;
            }

            case "createGuide":
                await CreateGuideAsync(index).ConfigureAwait(true);
                return;

            case "discardGuide":
                await DiscardGuideAsync(index).ConfigureAwait(true);
                return;

            // "Edits you extracted": row -> index, same shape as the block above.
            case "discardFixes":
                await DiscardFixesAsync(index).ConfigureAwait(true);
                return;

            case "discardAllFixes":
                await DiscardAllFixesAsync().ConfigureAwait(true);
                return;

            // The author's walkthrough row. Neither control mutates anything, so neither
            // takes the lock; updating it is walkthroughInit, a product action of its own.
            case "openWalkthrough":
            {
                var w = State.Walkthrough;
                if (w is null || w.State == WalkthroughState.Absent || _host.OpenPath is null) return;
                await _host.OpenPath(w.Path).ConfigureAwait(true);
                return;
            }

            case "copyWalkthroughPrompt":
            {
                var w = State.Walkthrough;
                if (w is null || w.State == WalkthroughState.Absent) return;
                System.Windows.Clipboard.SetText(UserCopy.WalkthroughAgentPrompt(w.Path));
                return;
            }

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
                // The panel's own why, not a model rebuilt here: BuildPanelModel takes it
                // as an input, so a model built without it reads as still loading.
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
            // Information, not error: a refused navigation is not a failure.
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
        // The sides actually present come from git, not from the entry name: a reverted
        // entry has no diff left, and an added/deleted file exists on only one side. A
        // failure to ask git gets its own error rather than being folded into "no
        // changes left".
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
        if (!started) return;
        await _panel.RefreshAsync().ConfigureAwait(true);
        // El acuse es el panel: hay que revelarlo (ver CLAUDE.md, "se revela, no se
        // notifica"). Caso que lo motivó: el camino del borrador no cambia de
        // situación, solo nace el bloque de borradores arriba de todo. Va después del
        // refresco y solo en verde.
        PanelReveal.Reveal(ControlId.StartReview, _host);
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
        // null cuando el panel ya lo dijo (ver UserCopy.FinishSuccess).
        // El acuse normal es el banner de finish-pending, así que el panel debe estar
        // a la vista: Finish también se dispara desde el menú, donde puede no estarlo.
        PanelReveal.Reveal(ControlId.FinishReview, _host);

        var toast = UserCopy.FinishSuccess(destination, outcome);
        if (toast is not null) GitReviewDialogs.Info(toast);
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
        if (!GitReviewDialogs.Confirm(ControlId.UndoFinish, UserCopy.UndoTitle, detail, UserCopy.UndoButton)) return;

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
        if (!GitReviewDialogs.Confirm(ControlId.UndoFinish, text, UserCopy.UndoForceDetail, UserCopy.UndoForceButton)) return;
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
        if (!GitReviewDialogs.Confirm(ControlId.ContinueReview,
                UserCopy.ContinueTitle(source),
                UserCopy.ContinueDetail(source),
                UserCopy.ContinueButton))
        {
            return;
        }
        var result = await RunAsync(
            "continueReview",
            new ActionParams.Continue(source),
            progress: UserCopy.ContinuingProgress(source)).ConfigureAwait(true);
        if (result is null || result.ExitCode is not 0 || result.TimedOut) return;
        // La situación entera cambia —no-review pasa a review— y esto se dispara
        // también desde el menú, con el panel cerrado.
        PanelReveal.Reveal(ControlId.ContinueReview, _host);
    }

    // -- housekeeping -------------------------------------------------------

    /// <summary>
    /// Discard one review. From an inventory row the name is known; from the menu it is
    /// picked out of that same inventory — filtered by typing, but never invented. This
    /// verb deletes branches, so a name that reaches the CLI without having been listed
    /// is a name nobody checked.
    /// </summary>
    private async Task DiscardInventoryAsync(int? index)
    {
        var branches = State.BranchesList;
        string name;
        if (index is null)
        {
            if (branches.Count == 0)
            {
                GitReviewDialogs.Error(UserCopy.NoReviewsToDiscard);
                return;
            }

            var names = branches.Select(b => b.Name).Distinct(StringComparer.Ordinal).ToList();
            var idx = GitReviewDialogs.Choose("Discard", "Review branch to discard", names);
            if (idx < 0) return;
            name = names[idx];
        }
        else
        {
            if (index < 0 || index >= branches.Count) return;
            name = branches[index.Value].Name;
        }

        var src = HousekeepingLogic.SourceFromReviewName(name);
        var action = name.StartsWith("review-saved/", StringComparison.Ordinal)
            ? new HousekeepingAction(HousekeepingKind.ForgetSavedOne, src)
            : new HousekeepingAction(HousekeepingKind.CleanOne, src);
        await ConfirmAndRunHousekeepingAsync(ControlId.DiscardInventory, action).ConfigureAwait(true);
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
        if (!started) return;
        await _panel.RefreshAsync().ConfigureAwait(true);
        // El panel pasa a review de punta a punta. Vino de una fila propia, así que
        // casi siempre es no-op — no distinguir el origen es deliberado: sería
        // estado de más.
        PanelReveal.Reveal(ControlId.StartFromDraft, _host);
    }

    /// <summary>
    /// Discard THIS row's draft, with a confirmation first: it is prose written by hand.
    /// Never --all — an action on one row does not touch the others.
    /// </summary>
    private async Task DiscardDraftAsync(int? index)
    {
        var draft = DraftRowAt(index);
        if (draft is null) return;
        if (!GitReviewDialogs.Confirm(ControlId.DiscardDraft,
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

    private GuideRecord? GuideRowAt(int? index) =>
        PanelModelBuilder.GuideAt(State.GuidesList, index);

    /// <summary>
    /// Asks the CLI for the empty file, then opens it: the CLI owns the write (the CLI
    /// is the only source of truth, see CLAUDE.md), so opening uses the path it reported
    /// rather than deriving one. It opens automatically because the file is created
    /// EMPTY on purpose — without opening it the row would just sit there saying "empty".
    /// </summary>
    private async Task CreateGuideAsync(int? index)
    {
        var guide = GuideRowAt(index);
        if (guide is null || guide.State != GuideState.Absent) return;
        var result = await RunAsync(
            "createGuide",
            new ActionParams.CreateGuide(guide.Kind == GuideKind.Team),
            progress: UserCopy.CreateGuideProgress).ConfigureAwait(true);
        if (result is { ExitCode: 0 } && _host.OpenPath is not null)
        {
            await _host.OpenPath(guide.Path).ConfigureAwait(true);
        }
    }

    /// <summary>
    /// Discard YOUR guide, with a confirmation first: it is prose written by hand. The
    /// shared one never gets here — the layout draws it no control, because removing it
    /// is git rm plus a commit and the CLI refuses --delete --team.
    /// </summary>
    private async Task DiscardGuideAsync(int? index)
    {
        var guide = GuideRowAt(index);
        if (guide is null || guide.Kind != GuideKind.Own || guide.State == GuideState.Absent) return;
        if (!GitReviewDialogs.Confirm(ControlId.DiscardGuide,
                UserCopy.DiscardGuideTitle,
                UserCopy.DiscardGuideDetail(guide.Path),
                UserCopy.DiscardGuideButton))
        {
            return;
        }
        await RunAsync(
            "deleteGuide",
            new ActionParams.DeleteGuide(),
            progress: UserCopy.DiscardGuideProgress).ConfigureAwait(true);
    }

    /// <summary>
    /// Drops the branch of edits of THIS row, confirmed first with the cost as the CLI
    /// reported it — nothing here is derived, since only git knows whether those commits
    /// already reached the base.
    ///
    /// Always --fixes-only, even if the session is gone by the time this runs: the argv
    /// can't depend on a value re-read after the confirmation, or a review that came back
    /// in that window could get taken down by a button that only promises to delete edits.
    /// </summary>
    private async Task DiscardFixesAsync(int? index)
    {
        var row = PanelModelBuilder.FixesAt(State.FixesList, index);
        if (row is null || row.Current) return;
        await ConfirmAndRunHousekeepingAsync(ControlId.DiscardFixes, new HousekeepingAction(
            HousekeepingKind.CleanFixesOne,
            HousekeepingLogic.SourceFromReviewName(row.Name),
            FixesState: row.State,
            Session: row.Session)).ConfigureAwait(true);
    }

    /// <summary>
    /// Drops every branch of edits at once: clean --fixes-only with no branch, which by
    /// clean's own scoping only ever enumerates review-fixes branches — so unlike a bare
    /// clean it needs no index or row to resolve against.
    /// </summary>
    private async Task DiscardAllFixesAsync()
    {
        await ConfirmAndRunHousekeepingAsync(ControlId.DiscardAllFixes, 
            new HousekeepingAction(HousekeepingKind.CleanFixesOneAll)).ConfigureAwait(true);
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
            await ConfirmAndRunHousekeepingAsync(ControlId.CleanReview, new HousekeepingAction(
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
        await ConfirmAndRunHousekeepingAsync(ControlId.CleanReview, action).ConfigureAwait(true);
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
        // forgetReview no tiene control de panel —llega por el menú y la paleta—, así
        // que no tiene ControlId propio: el canónico declara `confirms:` por CONTROL, y
        // sin control no hay dónde declararlo. Comparte la puerta del housekeeping con
        // clean, que sí lo tiene, y por eso pasa el suyo.
        await ConfirmAndRunHousekeepingAsync(ControlId.CleanReview, action).ConfigureAwait(true);
    }

    /// <summary>
    /// Which branch a housekeeping verb applies to — one of the reviews this client
    /// knows about, never typed blind. A delta marker can outlive its review branch,
    /// which is why "stale" and "every" need no name at all. The picker still filters
    /// as you type; it just cannot invent a row.
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

        if (names.Count == 0)
        {
            GitReviewDialogs.Error(
                forClean ? UserCopy.NoReviewsToClean
                    : savedOnly ? UserCopy.NoSavedReviews : UserCopy.NoDeltaSources);
            return null;
        }

        var idx = GitReviewDialogs.Choose(title, "Source branch name", names);
        return idx < 0 ? null : names[idx];
    }

    /// <summary>
    /// One bound of <c>compare</c>. The only picker in this client that accepts a value
    /// outside its list, because the CLI takes a commit-ish there — a tag or a SHA is a
    /// real answer. With no candidates to show it degrades to the plain input.
    /// </summary>
    private static string? PickCommitIsh(string title, IReadOnlyList<string> candidates) =>
        candidates.Count == 0
            ? GitReviewDialogs.Input(title, "Branch, tag or commit")
            : GitReviewDialogs.ChooseOrType(title, "Branch, tag or commit", candidates);

    /// <param name="id">
    /// The control the reviewer actually pressed — discardInventory, discardFixes,
    /// discardAllFixes, clean or forget — travels through rather than being guessed
    /// from the action: the confirmation gate checks what was declared for the
    /// control, not the verb.
    /// </param>
    private async Task ConfirmAndRunHousekeepingAsync(ControlId id, HousekeepingAction action)
    {
        var copy = HousekeepingLogic.ConfirmCopyFor(action);
        if (!GitReviewDialogs.Confirm(id, copy.Title, copy.Detail, copy.Button)) return;
        var verb = HousekeepingLogic.VerbForHousekeeping(action) == "forget"
            ? "forgetReview"
            : "cleanReview";
        // The confirmation's own question, restated as a running-now line.
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
            var candidates = ConfigPorcelain.BranchPickerItems(parsed.Candidates);
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
        // Las candidatas que la CLI ya reportó, más lo que se tipee: compare toma un
        // commit-ish, así que un tag o un SHA valen — pero mostrar la lista evita que
        // el caso común (una rama) haya que escribirlo de memoria.
        var candidates = (State.Candidates ?? Array.Empty<CandidateBranch>())
            .Select(c => c.Name)
            .Distinct(StringComparer.Ordinal)
            .ToList();
        var lower = PickCommitIsh(UserCopy.CompareLowerTitle, candidates);
        if (lower is null) return;
        var upper = PickCommitIsh(UserCopy.CompareUpperTitle, candidates);
        if (upper is null) return;

        var idx = GitReviewDialogs.Choose(
            UserCopy.CompareLayoutTitle,
            UserCopy.CompareLayoutPlaceholder,
            new[]
            {
                "Walkthrough — guided reading order if the upper tip has a walkthrough",
                "Walkthrough — keys only — only entries marked key",
                "Commit by commit — one commit at a time",
                "Whole diff — entire diff at once",
            });
        if (idx < 0) return;
        var layout = idx switch
        {
            0 => ReviewLayout.Walk,
            1 => ReviewLayout.Keys,
            2 => ReviewLayout.Step,
            _ => ReviewLayout.Whole,
        };
        if (!GitReviewDialogs.Confirm(ControlId.CompareReview,
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
    /// Walkthrough init: reconcile-vs-start-over is asked BEFORE the verb runs, not after
    /// a failure — init now updates instead of refusing, so there is no CLI error left to
    /// hang the offer off of.
    ///
    /// Nothing is asked when there is nothing to preserve, nor over a Superseded file:
    /// that one belongs to another PR and the CLI already starts over on its own.
    /// </summary>
    private async Task WalkthroughInitAsync()
    {
        var cwd = Cwd;
        var w = State.Walkthrough;
        var reconcilable = w is not null
            && w.State != WalkthroughState.Absent
            && w.State != WalkthroughState.Superseded;

        var force = false;
        if (reconcilable)
        {
            var picked = GitReviewDialogs.Choose(
                UserCopy.WalkthroughExistsTitle,
                UserCopy.WalkthroughExistsDetail,
                new[] { UserCopy.WalkthroughUpdateButton, UserCopy.WalkthroughStartOverButton });
            if (picked == GitReviewDialogs.Cancelled) return;
            force = picked == 1;
        }

        var result = await RunAsync(
            "walkthroughInit",
            new ActionParams.WalkthroughInit(force),
            progress: force
                ? UserCopy.WalkthroughOverwriteProgress
                : UserCopy.WalkthroughInitProgress).ConfigureAwait(true);
        if (result is not null && result.ExitCode == 0 && !result.TimedOut)
            await OpenWalkthroughAsync(cwd).ConfigureAwait(true);
    }

    private async Task WalkthroughBuildAsync()
    {
        if (!GitReviewDialogs.Confirm(ControlId.WalkthroughBuild,
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
        // Sin toast: el refresco ya deja la fila con el badge al día y el par
        // annotated/total recontado, y la línea de abajo abre el archivo (ver CLAUDE.md,
        // "Lo que el panel muestra no se notifica").
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
    /// Every mutation: re-read state after the confirmation, refuse if the repository
    /// moved while the dialog was open, run under the mutation lock, then refresh.
    /// Returns null when there is nothing left to report (busy, or stale) — both already
    /// told the reviewer what happened.
    ///
    /// <paramref name="progress"/> covers the two refreshes as well as the verb itself —
    /// on Windows those are seconds of their own — because a finish started from the menu
    /// may not have the panel's greyed-out buttons in view.
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
            GitReviewDialogs.Info(UserCopy.Stale);
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

    private static string DisplayOf(object id) =>
        id is PathRef pathRef ? pathRef.Display : id.ToString() ?? "";

    private static void OpenUrl(string url) =>
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
