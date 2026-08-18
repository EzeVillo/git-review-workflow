using System.Diagnostics;
using System.Windows;
using GitReview.Domain;
using GitReview.Host;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// Full action matrix for the 27 product actions + panel-only controls.
/// Confirmations and copy match UserCopy / HousekeepingLogic (byte-for-byte with other clients).
/// </summary>
public sealed class ActionDispatcher
{
    private readonly GitReviewPanelController _panel;
    private readonly Func<string, Task>? _openFile;
    private readonly Func<string, string?, string?, Task>? _openDiff;
    private readonly Func<IReadOnlyList<(string Path, string? Before, string? After)>, Task>? _openAllDiffs;
    private readonly Func<string, Task>? _openTextDocument;
    private readonly Func<Task>? _runStartWizard;

    public ActionDispatcher(
        GitReviewPanelController panel,
        Func<string, Task>? openFile = null,
        Func<string, string?, string?, Task>? openDiff = null,
        Func<IReadOnlyList<(string Path, string? Before, string? After)>, Task>? openAllDiffs = null,
        Func<string, Task>? openTextDocument = null,
        Func<Task>? runStartWizard = null)
    {
        _panel = panel;
        _openFile = openFile;
        _openDiff = openDiff;
        _openAllDiffs = openAllDiffs;
        _openTextDocument = openTextDocument;
        _runStartWizard = runStartWizard;
        panel.HostAction += HandleAsync;
    }

    public async Task HandleAsync(string wire, int? index, string? supportLinkId)
    {
        var state = _panel.State.Current;
        var cwd = SoleTarget.PickSoleTarget(
            // roots via state manager's last refresh context — use mutation cwd
            new[] { GetCwd() }.Where(x => x is not null).Cast<string>().ToList());

        switch (wire)
        {
            case "refresh":
                await _panel.RefreshAsync().ConfigureAwait(true);
                return;
            case "next":
            case "prev":
            {
                var before = state.State?.Position;
                var r = await _panel.Mutations.RunActionAsync(wire).ConfigureAwait(true);
                await _panel.RefreshAsync().ConfigureAwait(true);
                var after = _panel.State.Current.State?.Position;
                if (r is not null && r.ExitCode == 0 && before == after && !string.IsNullOrWhiteSpace(r.Stdout))
                    MessageBox.Show(CliMessage.FirstCliLine(r.Stdout), UserCopy.ProductTitle);
                return;
            }
            case "copyCliInstall":
            {
                var cmd = state.Situation == Situation.CliOutdated
                    ? InstallHint.NpmUpdateCmd
                    : InstallHint.NpmInstallCmd;
                Clipboard.SetText(cmd);
                return;
            }
            case "installCli":
                OpenUrl(UserCopy.InstallDocsUrl);
                return;
            case "openSupport":
            {
                var url = SupportLinks.UrlFor(supportLinkId);
                if (url is not null) OpenUrl(url);
                return;
            }
            case "outOfRangeHelp":
                MessageBox.Show(UserCopy.OutOfRangeFallback, UserCopy.ProductTitle);
                return;
            case "showCliLog":
            {
                var log = string.Join("\n", CliInvoker.CliLogSink.Snapshot());
                MessageBox.Show(string.IsNullOrEmpty(log) ? "(empty)" : log, "git review CLI log");
                return;
            }
            case "startReview":
                if (_runStartWizard is not null) await _runStartWizard().ConfigureAwait(true);
                else MessageBox.Show("Start wizard is only available inside Visual Studio.", UserCopy.ProductTitle);
                return;
            case "abortReview":
            {
                var source = state.State?.Source ?? "this branch";
                if (!Confirm(UserCopy.AbortTitle(source), UserCopy.AbortDetail, UserCopy.AbortButton)) return;
                await RunCheckedAsync("abortReview").ConfigureAwait(true);
                return;
            }
            case "saveReview":
            {
                var source = state.State?.Source ?? "this branch";
                if (!Confirm(UserCopy.SaveTitle(source), UserCopy.SaveDetail, UserCopy.SaveButton)) return;
                await RunCheckedAsync("saveReview").ConfigureAwait(true);
                return;
            }
            case "finishReview":
            {
                if (state.Readonly == true)
                {
                    MessageBox.Show(UserCopy.ReadonlyFinish, UserCopy.ProductTitle);
                    return;
                }
                var onto = PickFinishOnto(state.State?.Source ?? "branch");
                if (onto is null) return;
                await RunCheckedAsync("finishReview", new ActionParams.FinishOnto(onto.Value)).ConfigureAwait(true);
                return;
            }
            case "undoFinish":
            {
                var detail = state.Situation == Situation.FinishConflict
                    ? UserCopy.UndoDetailConflict
                    : UserCopy.UndoDetailPending;
                if (!Confirm(UserCopy.UndoTitle, detail, UserCopy.UndoButton)) return;
                await RunCheckedAsync("undoFinish", new ActionParams.UndoFinish(false)).ConfigureAwait(true);
                return;
            }
            case "resumeFinish":
                await RunCheckedAsync("resumeFinish", new ActionParams.ResumeFinish(false)).ConfigureAwait(true);
                return;
            case "continueReview":
            {
                if (index is null) return;
                var source = PanelModelBuilder.ResumableSourceAt(state.BranchesList, index.Value);
                if (source is null)
                {
                    MessageBox.Show(UserCopy.NotResumable, UserCopy.ProductTitle);
                    return;
                }
                if (!Confirm(UserCopy.ContinueTitle(source), UserCopy.ContinueDetail(source), UserCopy.ContinueButton))
                    return;
                await RunCheckedAsync("continueReview", new ActionParams.Continue(source)).ConfigureAwait(true);
                return;
            }
            case "discardInventory":
            {
                if (index is null || index < 0 || index >= state.BranchesList.Count) return;
                var branch = state.BranchesList[index.Value];
                var src = Porcelain.SourceOf(branch);
                HousekeepingAction action;
                if (branch.Saved)
                    action = new HousekeepingAction(HousekeepingKind.ForgetSavedOne, src);
                else
                    action = new HousekeepingAction(HousekeepingKind.CleanOne, src);
                var copy = HousekeepingLogic.ConfirmCopyFor(action);
                if (!Confirm(copy.Title, copy.Detail, copy.Button)) return;
                await RunCheckedAsync(
                    branch.Saved ? "forgetReview" : "cleanReview",
                    new ActionParams.Housekeeping(action)).ConfigureAwait(true);
                return;
            }
            case "cleanReview":
            {
                var pending = HousekeepingLogic.PendingFinishInfo(state);
                if (pending is not null)
                {
                    var action = new HousekeepingAction(
                        HousekeepingKind.CleanKeepFixes, pending.Value.Source, pending.Value.Onto);
                    var copy = HousekeepingLogic.ConfirmCopyFor(action);
                    if (!Confirm(copy.Title, copy.Detail, copy.Button)) return;
                    await RunCheckedAsync("cleanReview", new ActionParams.Housekeeping(action)).ConfigureAwait(true);
                }
                else
                {
                    MessageBox.Show(
                        "Use Tools → git review → Clean for full housekeeping options.",
                        UserCopy.ProductTitle);
                }
                return;
            }
            case "compareReview":
            case "walkthroughInit":
            case "walkthroughBuild":
            case "setBase":
            case "setRemote":
            case "forgetReview":
            case "previewEdits":
            case "previewEditsStat":
            case "goToEntry":
                MessageBox.Show(
                    $"Action '{wire}' is available from the git review menu when running inside Visual Studio.",
                    UserCopy.ProductTitle);
                return;
            case "openEntry":
            {
                var entry = PanelModelBuilder.CurrentEntry(state.EntriesList, state.State?.Position);
                if (entry is null) return;
                var display = entry.Id is PathRef pr ? pr.Display : entry.Id.ToString() ?? "";
                if (_openFile is not null)
                {
                    await _openFile(display).ConfigureAwait(true);
                    _panel.RememberOpened(display);
                }
                return;
            }
            case "openChange":
            {
                if (_openDiff is null) return;
                // index targets a file row (step/whole); otherwise current entry
                string display;
                if (index is not null)
                {
                    var file = state.FilesList.FirstOrDefault(f => f.Position == index)
                               ?? state.EntriesList.FirstOrDefault(e => e.Position == index);
                    if (file is null) return;
                    display = file.Id is PathRef p ? p.Display : file.Id.ToString() ?? "";
                }
                else
                {
                    var entry = PanelModelBuilder.CurrentEntry(state.EntriesList, state.State?.Position);
                    if (entry is null) return;
                    display = entry.Id is PathRef p ? p.Display : entry.Id.ToString() ?? "";
                }
                await _openDiff(display, null, null).ConfigureAwait(true);
                _panel.RememberOpened(display);
                return;
            }
            case "openAllChanges":
            {
                if (_openAllDiffs is null) return;
                var files = state.EntriesList
                    .Select(e => (Path: e.Id is PathRef p ? p.Display : e.Id.ToString() ?? "", Before: (string?)null, After: (string?)null))
                    .ToList();
                if (files.Count == 0)
                {
                    MessageBox.Show(UserCopy.OpenRangeEmpty, UserCopy.ProductTitle);
                    return;
                }
                await _openAllDiffs(files).ConfigureAwait(true);
                return;
            }
            case "showWhy":
            {
                if (_openTextDocument is null) return;
                var model = PanelModelBuilder.BuildPanelModel(
                    state, new PanelInputs(false));
                var why = model.Why?.Text;
                if (string.IsNullOrEmpty(why)) return;
                await _openTextDocument(why).ConfigureAwait(true);
                return;
            }
        }
    }

    private async Task RunCheckedAsync(string action, ActionParams? p = null)
    {
        var token = StaleGuard.CaptureToken(_panel.State.Current);
        // Re-check after confirm
        await _panel.RefreshAsync().ConfigureAwait(true);
        if (!StaleGuard.TokenStillValid(token, _panel.State.Current))
        {
            MessageBox.Show(UserCopy.StaleMessage(action), UserCopy.ProductTitle);
            return;
        }
        var r = await _panel.Mutations.RunActionAsync(action, p).ConfigureAwait(true);
        if (r is null)
        {
            MessageBox.Show(UserCopy.DiscardBusy, UserCopy.ProductTitle);
            return;
        }
        if (r.ExitCode is not null and not 0)
        {
            MessageBox.Show(
                CliMessage.CliErrorText(r.Stderr, r.Stdout, UserCopy.FailureFallback(action, p)),
                UserCopy.ProductTitle,
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
        await _panel.RefreshAsync().ConfigureAwait(true);
    }

    private static bool Confirm(string title, string detail, string button)
    {
        var result = MessageBox.Show(
            detail,
            title,
            MessageBoxButton.OKCancel,
            MessageBoxImage.Question);
        return result == MessageBoxResult.OK;
    }

    private static bool? PickFinishOnto(string source)
    {
        var r = MessageBox.Show(
            UserCopy.FinishLocationSeparate + "\n\n" +
            "Yes = separate branch (review-fixes/…)\n" +
            "No = onto the PR branch\n" +
            "Cancel = abort",
            UserCopy.FinishLocationTitle(source),
            MessageBoxButton.YesNoCancel,
            MessageBoxImage.Question);
        return r switch
        {
            MessageBoxResult.Yes => false,
            MessageBoxResult.No => true,
            _ => null,
        };
    }

    private string? GetCwd()
    {
        // Best-effort: read from service via panel refresh roots is private.
        // MutationRunner already enforces sole cwd.
        return null;
    }

    private static void OpenUrl(string url) =>
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
