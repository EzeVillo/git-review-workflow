using System.IO;
using GitReview.Domain;
using GitReview.Host;
using GitReview.VS.ToolWindows;

namespace GitReview.VS.Wizards;

/// <summary>
/// Multi-step start flow: branch → origin → range → reading order → confirm, with the
/// draft loop (011) hanging off the reading-order step. Same steps, same order and the
/// same <see cref="UserCopy"/> labels as the VS Code start assistant and the JetBrains
/// wizard.
///
/// Every step is a real modal picker (<see cref="GitReviewDialogs.Choose"/>): cancelling
/// one ends the wizard, and nothing is ever chosen on the reviewer's behalf. It used to
/// print the options into a message box and then take the first one regardless, which
/// meant a review started on whichever branch happened to sort first.
/// </summary>
public static class StartWizard
{
    public static async Task<bool> RunAsync(
        CliInvoker cli,
        MutationRunner mutations,
        ReviewStateManager stateManager,
        string cwd,
        PanelHost host,
        CancellationToken ct = default)
    {
        // Fresh config --porcelain (config + candidates), not the panel's cache: the
        // panel only carries candidates in the no-review situation.
        var configResult = await cli.InvokeAsync("config", new[] { "--porcelain" }, cwd, cancellationToken: ct)
            .ConfigureAwait(true);
        if (configResult.ExitCode != 0)
        {
            GitReviewDialogs.CliError(configResult.Stderr, UserCopy.CouldNotReadConfig, configResult.Stdout);
            return false;
        }

        ConfigPorcelainResult porcelain;
        try
        {
            porcelain = ConfigPorcelain.ParseConfigPorcelain(configResult.Stdout);
        }
        catch (Exception ex)
        {
            GitReviewDialogs.Error(string.IsNullOrWhiteSpace(ex.Message)
                ? UserCopy.CouldNotParseConfig
                : ex.Message);
            return false;
        }

        // Read from the CLI rather than the panel state: a base set from another window
        // a second ago is still a base.
        if (porcelain.Config.Base is null)
        {
            GitReviewDialogs.Error(UserCopy.ConfigureBaseFirst);
            return false;
        }

        var branches = ConfigPorcelain.BranchPickerItems(porcelain.Candidates);
        if (branches.Count == 0)
        {
            GitReviewDialogs.Error(UserCopy.NoBranchesForReview);
            return false;
        }

        var branchIdx = GitReviewDialogs.Choose(
            UserCopy.StartBranchTitle,
            UserCopy.StartBranchPlaceholder,
            branches.Select(ConfigPorcelain.BranchPickerLabel).ToList());
        if (branchIdx < 0) return false;
        var branch = branches[branchIdx].Name;

        var defaultSource = SourcePreference.ResolveDefaultSource(
            new SourcePreferenceLevels(GlobalValue: host.DefaultSource?.Invoke()));
        var sourceIdx = GitReviewDialogs.Choose(
            UserCopy.StartOriginTitle,
            UserCopy.StartOriginPlaceholder,
            UserCopy.SourceLabels.Select(s => s.Label).ToList(),
            defaultIndex: IndexOfSource(defaultSource));
        if (sourceIdx < 0) return false;
        var source = UserCopy.SourceLabels[sourceIdx].Source;

        // The range step only exists when there is a delta marker to compare against:
        // offering "only what is new" without one is offering a validation error.
        var range = ReviewRange.Full;
        var deltas = await LoadDeltasAsync(cli, cwd, branch, ct).ConfigureAwait(true);
        if (ConfigPorcelain.DeltaForSource(deltas, source.Id()) is not null)
        {
            var rangeIdx = GitReviewDialogs.Choose(
                UserCopy.StartRangeTitle,
                UserCopy.StartRangePlaceholder,
                UserCopy.RangeLabels.Select(r => r.Label).ToList());
            if (rangeIdx < 0) return false;
            range = UserCopy.RangeLabels[rangeIdx].Range;
        }

        var offersResult = await LoadOffersAsync(cli, cwd, branch, source, range, ct).ConfigureAwait(true);
        if (!offersResult.Ok)
        {
            GitReviewDialogs.CliError(offersResult.Stderr, UserCopy.CouldNotReadOffers, offersResult.Stdout);
            return false;
        }

        var context = new WizardContext(
            Cli: cli,
            Mutations: mutations,
            StateManager: stateManager,
            Cwd: cwd,
            Host: host,
            Branch: branch,
            Source: source,
            Range: range,
            Base: porcelain.Config.Base,
            Deltas: offersResult.Deltas ?? deltas);

        return await LayoutStepAsync(context, offersResult.Offers, ct).ConfigureAwait(true);
    }

    /// <summary>
    /// Everything the steps from the reading order onwards need. A record because the
    /// draft loop re-enters the reading-order step, and passing eight arguments back and
    /// forth is how one of them ends up stale.
    /// </summary>
    private sealed record WizardContext(
        CliInvoker Cli,
        MutationRunner Mutations,
        ReviewStateManager StateManager,
        string Cwd,
        PanelHost Host,
        string Branch,
        ReviewSource Source,
        ReviewRange Range,
        string? Base,
        IReadOnlyList<DeltaRecord>? Deltas);

    /// <summary>
    /// Reading-order step. Separate — and re-entered — because a reviewer who enters the
    /// draft flow and cancels comes back here with the draft intact and the offer already
    /// recomputed by the CLI.
    /// </summary>
    private static async Task<bool> LayoutStepAsync(
        WizardContext ctx,
        IReadOnlyList<ReadingOffer>? offers,
        CancellationToken ct)
    {
        var items = LayoutOffers.BuildLayoutItems(offers);
        var labels = items
            .Select(i => i.Description.Length > 0 ? $"{i.Label} — {i.Description}" : i.Label)
            .ToList();
        var idx = GitReviewDialogs.Choose(
            UserCopy.StartLayoutTitle,
            UserCopy.StartLayoutPlaceholder,
            labels);
        if (idx < 0) return false;
        var picked = items[idx];
        if (picked.Draft is null)
            return await ConfirmAndStartAsync(ctx, picked.Layout, ct).ConfigureAwait(true);

        // Nothing is asked: which of the three draft paths applies was already
        // decided by the CLI when it picked which offer to emit, which is the only
        // side that can — the question is whether the order still covers the range,
        // and answering it takes both tips.
        return await RunDraftFlowAsync(
            ctx,
            DraftFlow.InitialDraftFlowState(picked.Draft.Value),
            ct).ConfigureAwait(true);
    }

    /// <summary>
    /// What is left of the draft path (012). The decisions live in <see cref="DraftFlow"/>;
    /// this is only the vehicle: one invocation, and the wizard closes.
    ///
    /// It does not open the draft and leaves no dialog waiting. The continuation —
    /// filling it in, validating it, starting the review — lives in the panel's draft
    /// block, over a state that outlives closing the IDE.
    /// </summary>
    private static async Task<bool> RunDraftFlowAsync(
        WizardContext ctx,
        DraftFlowState start,
        CancellationToken ct)
    {
        var state = start;

        while (true)
        {
            switch (state)
            {
                case DraftFlowState.Create create:
                {
                    var outcome = await InvokeDraftAsync(ctx, build: false, create.Force, ct).ConfigureAwait(true);
                    // A note on success (the draft covers the author's walkthrough) is
                    // shown like start's own notes are.
                    if (outcome.Ok && outcome.Text.Length > 0) GitReviewDialogs.Info(outcome.Text);
                    state = DraftFlow.AdvanceDraftFlow(
                        create,
                        new DraftFlowEvent.Created(
                            outcome.Ok,
                            outcome.Ok
                                ? null
                                : outcome.Text.Length > 0 ? outcome.Text : UserCopy.DraftFailed));
                    break;
                }

                case DraftFlowState.Done:
                    // The post-mutation refresh brings the draft's row to the panel,
                    // with its path. Nothing else to do here.
                    return true;

                case DraftFlowState.Back back:
                {
                    if (back.Error is not null) GitReviewDialogs.Error(back.Error);
                    // With the offers up to date: if the draft was created, the offer to
                    // write one is now the offer to continue it.
                    var offers = await LoadOffersAsync(
                        ctx.Cli, ctx.Cwd, ctx.Branch, ctx.Source, ctx.Range, ct).ConfigureAwait(true);
                    return await LayoutStepAsync(ctx, offers.Offers, ct).ConfigureAwait(true);
                }

                default:
                    return false;
            }
        }
    }

    private sealed record DraftOutcome(bool Ok, string Text);

    /// <summary>
    /// Under the mutation lock, like every other CLI call this client makes. Drafting
    /// touches no git state, but it runs with the panel and its refreshes live.
    /// </summary>
    private static async Task<DraftOutcome> InvokeDraftAsync(
        WizardContext ctx,
        bool build,
        bool force,
        CancellationToken ct)
    {
        using var reporting = ctx.Host.Progress?.Invoke(UserCopy.DraftProgress(ctx.Branch, build));
        var result = await ctx.Mutations.RunArgvAsync(
            "walkthrough",
            ReviewIntentLogic.DraftArgs(ctx.Branch, ctx.Source, ctx.Range, build, force),
            ct: ct).ConfigureAwait(true);
        if (result is null) return new DraftOutcome(false, MutationLock.DiscardReason);
        return new DraftOutcome(
            result.ExitCode == 0 && !result.TimedOut,
            CliMessage.FlattenCliMessage(result.Stderr));
    }

    private sealed record OffersResult(
        bool Ok,
        IReadOnlyList<ReadingOffer>? Offers,
        IReadOnlyList<DeltaRecord>? Deltas,
        IReadOnlyList<DraftRecord>? Drafts = null,
        string Stderr = "",
        string Stdout = "");

    /// <summary>Reading offers for a resolved (branch, origin, range).</summary>
    private static async Task<OffersResult> LoadOffersAsync(
        CliInvoker cli,
        string cwd,
        string branch,
        ReviewSource source,
        ReviewRange range,
        CancellationToken ct)
    {
        var args = new List<string> { "--porcelain" };
        args.AddRange(LayoutOffers.OfferConfigFlags(source, range));
        args.Add("--");
        args.Add(branch);
        var result = await cli.InvokeAsync(
            "config",
            args,
            cwd,
            network: source == ReviewSource.Remote,
            cancellationToken: ct).ConfigureAwait(true);
        if (result.ExitCode != 0 || result.TimedOut)
            return new OffersResult(false, null, null, null, result.Stderr, result.Stdout);
        try
        {
            var parsed = ConfigPorcelain.ParseConfigPorcelain(result.Stdout);
            return new OffersResult(true, parsed.Offers, parsed.Deltas, parsed.Drafts);
        }
        catch
        {
            // Unreadable offers are not a failed start: BuildLayoutItems falls back to
            // step + whole, which every review supports.
            return new OffersResult(true, null, null);
        }
    }

    private static async Task<IReadOnlyList<DeltaRecord>?> LoadDeltasAsync(
        CliInvoker cli,
        string cwd,
        string branch,
        CancellationToken ct)
    {
        var result = await cli.InvokeAsync(
            "config",
            new[] { "--porcelain", "--", branch },
            cwd,
            cancellationToken: ct).ConfigureAwait(true);
        if (result.ExitCode != 0) return null;
        try
        {
            return ConfigPorcelain.ParseConfigPorcelain(result.Stdout).Deltas;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// "Validate and start" on a row of the panel's draft block (012): the same four
    /// steps as the extension, with THAT row's flags.
    ///
    /// It lives here and not in the dispatcher because step 4 is the usual start, with
    /// its confirmation, its staleness guard and its error handling: a second copy of
    /// that would be a second way to start a review.
    /// </summary>
    public static async Task<bool> StartFromDraftAsync(
        CliInvoker cli,
        MutationRunner mutations,
        ReviewStateManager stateManager,
        string cwd,
        PanelHost host,
        DraftRecord draft,
        CancellationToken ct = default)
    {
        // Without the flags it was generated with there is nothing to replicate, and
        // guessing them would make --build die on drift over a valid draft. The panel
        // already omits the control; this is the host's own guard.
        if (draft.Source == DraftSource.Unknown || draft.Range == DraftRange.Unknown) return false;

        var source = draft.Source switch
        {
            DraftSource.Local => ReviewSource.Local,
            DraftSource.Offline => ReviewSource.Offline,
            _ => ReviewSource.Remote,
        };
        var range = draft.Range == DraftRange.Delta ? ReviewRange.Delta : ReviewRange.Full;

        await SaveDraftAsync(host, draft.Path).ConfigureAwait(true);

        var built = await mutations.RunArgvAsync(
            "walkthrough",
            ReviewIntentLogic.DraftArgs(draft.Src, source, range, build: true),
            network: false,
            ct: ct).ConfigureAwait(true);
        if (built is null)
        {
            GitReviewDialogs.Info(UserCopy.DiscardBusy);
            return false;
        }
        if (built.ExitCode != 0)
        {
            // The reason for the rejection was written by the CLI: rewording it would be
            // inventing a second validation vocabulary. The panel and the draft are left
            // exactly as they were.
            GitReviewDialogs.CliError(built.Stderr, UserCopy.DraftBuildFailed, built.Stdout);
            return false;
        }

        // The draft is readable by now; what is re-read is whether it marked key entries,
        // and only the CLI knows that. With the SAME flags — and the `delta` records come
        // back in the same report, which is what validates an incremental range.
        var layout = ReviewLayout.Walk;
        IReadOnlyList<DeltaRecord>? deltas = null;
        var report = await cli.InvokeAsync(
            "config",
            ReviewIntentLogic.DraftConfigArgs(draft.Src, source, range),
            cwd,
            network: false,
            cancellationToken: ct).ConfigureAwait(true);
        if (report.ExitCode == 0)
        {
            ConfigPorcelainResult? parsed = null;
            try
            {
                parsed = ConfigPorcelain.ParseConfigPorcelain(report.Stdout);
            }
            catch
            {
                parsed = null;
            }
            deltas = parsed?.Deltas;
            if (DraftFlow.OffersIncludeKeys(parsed?.Offers))
            {
                var idx = GitReviewDialogs.Choose(
                    UserCopy.StartLayoutTitle,
                    UserCopy.DraftKeysPlaceholder,
                    UserCopy.DraftKeysLabels.Select(k => k.Label).ToList());
                if (idx < 0) return false;
                layout = UserCopy.DraftKeysLabels[idx].KeysOnly ? ReviewLayout.Keys : ReviewLayout.Walk;
            }
        }

        var ctx = new WizardContext(
            cli,
            mutations,
            stateManager,
            cwd,
            host,
            draft.Src,
            source,
            range,
            stateManager.Current.Config?.Base,
            deltas);
        return await ConfirmAndStartAsync(ctx, layout, ct).ConfigureAwait(true);
    }

    /// <summary>
    /// Saves the draft document if it is open and dirty, and only that one.
    /// <c>walkthrough draft --build</c> reads the file off disk, and the editor may hold
    /// the filled-in order unsaved: then the CLI validates the empty skeleton and answers
    /// "unfilled entries remain" with the text in plain sight. The path comes from the
    /// CLI — never one this client built.
    /// </summary>
    private static async Task SaveDraftAsync(PanelHost host, string path)
    {
        if (host.SavePath is null) return;
        try
        {
            await host.SavePath(path).ConfigureAwait(true);
        }
        catch
        {
            // Not being able to flush the buffer is the CLI's problem to report: it will
            // say what is still missing from the file it can see.
        }
    }


    private static async Task<bool> ConfirmAndStartAsync(
        WizardContext ctx,
        ReviewLayout layout,
        CancellationToken ct)
    {
        var intent = new ReviewIntent(ctx.Branch, layout, ctx.Range, ctx.Source);
        var delta = ConfigPorcelain.DeltaForSource(ctx.Deltas, ctx.Source.Id());
        if (ReviewIntentLogic.ValidateIntent(intent, new IntentValidationContext(delta))
            is IntentValidationResult.Fail fail)
        {
            GitReviewDialogs.Error(fail.Reason);
            return false;
        }

        var args = ReviewIntentLogic.IntentToArgs(intent, ctx.Branch);
        if (!GitReviewDialogs.Confirm(
                UserCopy.StartConfirmTitle(ctx.Branch, layout),
                UserCopy.StartConfirmDetail(args, ctx.Base),
                UserCopy.StartConfirmButton))
        {
            return false;
        }

        // The wizard was open long enough for the repository to have moved on; a start
        // that lands on a different situation than the one it was configured for is a
        // start nobody asked for.
        var token = StaleGuard.CaptureToken(ctx.StateManager.Current);
        await ctx.StateManager.RefreshAsync(ct).ConfigureAwait(true);
        var current = ctx.StateManager.Current;
        if (!StaleGuard.TokenStillValid(token, current)
            || current.Situation is not (Situation.NoReview or Situation.FinishPending))
        {
            GitReviewDialogs.Info(UserCopy.StartStaleWizard);
            return false;
        }

        // A start fetches, so it is the longest wait this client has -- and the wizard
        // it was configured in is gone by now, leaving nothing on screen that says so.
        using var reporting = ctx.Host.Progress?.Invoke(UserCopy.StartingProgress(ctx.Branch));
        var result = await ctx.Mutations.RunActionAsync(
            "startReview",
            new ActionParams.Start(intent, ctx.Branch),
            network: true,
            ct: ct).ConfigureAwait(true);

        // Discarded: the lock's own listener says so, for every surface at once.
        if (result is null) return false;
        if (result.ExitCode == 0 && !result.TimedOut)
        {
            // A successful start still emits notes on stderr (FR-031).
            var note = CliMessage.FlattenCliMessage(result.Stderr);
            if (note.Length > 0) GitReviewDialogs.Info(note);
            return true;
        }

        var text = CliMessage.CliErrorText(result.Stderr, result.Stdout, UserCopy.StartFailed);
        if (StartFailure.ClassifyStartFailure(result.Stderr) == StartFailureCategory.Network)
        {
            // Credentials cannot be typed into a dialog the CLI never prompts to: the
            // reviewer gets the exact command line to re-run in a terminal.
            var resolved = ResolveCommand.Resolve("start", args, ctx.Cli.GitReviewPath);
            GitReviewDialogs.Error(
                $"{text}\n\nTo retry with credentials, run in a terminal:\n" +
                CliLog.FormatCommandLine(resolved.Command, resolved.Args));
            return false;
        }
        GitReviewDialogs.Error(text);
        return false;
    }

    private static int IndexOfSource(ReviewSource source)
    {
        for (var i = 0; i < UserCopy.SourceLabels.Count; i++)
            if (UserCopy.SourceLabels[i].Source == source)
                return i;
        return 0;
    }
}
