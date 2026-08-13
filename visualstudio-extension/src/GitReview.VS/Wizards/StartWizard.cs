using System.Windows;
using GitReview.Domain;
using GitReview.Host;

namespace GitReview.VS.Wizards;

/// <summary>
/// Multi-step start flow (branch → source → range → layout → confirm).
/// Labels byte-for-byte with UserCopy / LayoutOffers (VS Code + JetBrains).
/// </summary>
public static class StartWizard
{
    public static async Task<bool> RunAsync(
        CliInvoker cli,
        MutationRunner mutations,
        string cwd,
        ReviewState state,
        CancellationToken ct = default)
    {
        if (state.Config?.Base is null)
        {
            MessageBox.Show(UserCopy.ConfigureBaseFirst, UserCopy.ProductTitle);
            return false;
        }

        var configResult = await cli.InvokeAsync("config", new[] { "--porcelain" }, cwd, cancellationToken: ct)
            .ConfigureAwait(true);
        if (configResult.ExitCode != 0)
        {
            MessageBox.Show(UserCopy.CouldNotReadConfig, UserCopy.ProductTitle);
            return false;
        }

        ConfigPorcelainResult porcelain;
        try
        {
            porcelain = ConfigPorcelain.ParseConfigPorcelain(configResult.Stdout);
        }
        catch
        {
            MessageBox.Show(UserCopy.CouldNotParseConfig, UserCopy.ProductTitle);
            return false;
        }

        var branches = ConfigPorcelain.BranchPickerItems(porcelain.Candidates);
        if (branches.Count == 0)
        {
            MessageBox.Show(UserCopy.NoBranchesForReview, UserCopy.ProductTitle);
            return false;
        }

        var branch = Pick(
            UserCopy.StartBranchTitle,
            UserCopy.StartBranchPlaceholder,
            branches.Select(b => (ConfigPorcelain.BranchPickerLabel(b), b.Name)).ToList());
        if (branch is null) return false;

        var sourcePick = Pick(
            UserCopy.StartOriginTitle,
            UserCopy.StartOriginPlaceholder,
            UserCopy.SourceLabels.Select(s => (s.Label, s.Source.Id())).ToList());
        if (sourcePick is null) return false;
        var source = ReviewSourceExt.Parse(sourcePick) ?? ReviewSource.Remote;

        var rangePick = Pick(
            UserCopy.StartRangeTitle,
            UserCopy.StartRangePlaceholder,
            UserCopy.RangeLabels.Select(r => (r.Label, r.Range.Id())).ToList());
        if (rangePick is null) return false;
        var range = rangePick == "delta" ? ReviewRange.Delta : ReviewRange.Full;

        // Offers for this branch
        var offerFlags = LayoutOffers.OfferConfigFlags(source, range).ToList();
        offerFlags.Add("--");
        offerFlags.Add(branch);
        var offersResult = await cli.InvokeAsync(
            "config",
            new[] { "--porcelain" }.Concat(offerFlags).ToList(),
            cwd,
            network: source == ReviewSource.Remote,
            cancellationToken: ct).ConfigureAwait(true);
        IReadOnlyList<ReadingOffer>? offers = null;
        if (offersResult.ExitCode == 0)
        {
            try { offers = ConfigPorcelain.ParseConfigPorcelain(offersResult.Stdout).Offers; }
            catch { /* fallback */ }
        }

        var layoutItems = LayoutOffers.BuildLayoutItems(offers);
        var layoutPick = Pick(
            UserCopy.StartLayoutTitle,
            UserCopy.StartLayoutPlaceholder,
            layoutItems.Select(i => (i.Label + " — " + i.Description, i.Label)).ToList());
        if (layoutPick is null) return false;
        var item = layoutItems.First(i => i.Label == layoutPick || layoutPick.StartsWith(i.Label, StringComparison.Ordinal));
        var layout = item.Layout;

        // Draft path (011) is interactive in the IDE; for now surface the wait message.
        if (item.Draft is not null)
        {
            MessageBox.Show(
                UserCopy.DraftWaitMessage(branch),
                UserCopy.DraftWaitTitle,
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            // Host should open the draft file and resume — full loop lives in DraftFlow.
        }

        var intent = new ReviewIntent(branch, layout, range, source);
        var delta = ConfigPorcelain.DeltaForSource(porcelain.Deltas, source.Id());
        var validation = ReviewIntentLogic.ValidateIntent(intent, new IntentValidationContext(delta));
        if (validation is IntentValidationResult.Fail fail)
        {
            MessageBox.Show(fail.Reason, UserCopy.ProductTitle);
            return false;
        }

        var args = ReviewIntentLogic.IntentToArgs(intent, branch);
        var confirm = MessageBox.Show(
            UserCopy.StartConfirmDetail(args, porcelain.Config.Base),
            UserCopy.StartConfirmTitle(branch, layout),
            MessageBoxButton.OKCancel,
            MessageBoxImage.Question);
        if (confirm != MessageBoxResult.OK) return false;

        var result = await mutations.RunActionAsync(
            "startReview",
            new ActionParams.Start(intent, branch),
            network: true,
            ct: ct).ConfigureAwait(true);

        if (result is null)
        {
            MessageBox.Show(UserCopy.DiscardBusy, UserCopy.ProductTitle);
            return false;
        }
        if (result.ExitCode is not null and not 0)
        {
            MessageBox.Show(
                CliMessage.CliErrorText(result.Stderr, result.Stdout, UserCopy.StartFailed),
                UserCopy.ProductTitle,
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return false;
        }
        return true;
    }

    private static string? Pick(string title, string prompt, IReadOnlyList<(string Label, string Value)> items)
    {
        if (items.Count == 0) return null;
        // Simple sequential MessageBox chooser (no VS QuickPick API outside the IDE).
        // Inside VS, replace with a proper picker UI.
        var body = prompt + "\n\n" + string.Join("\n",
            items.Select((it, i) => $"{i + 1}. {it.Label}"));
        body += "\n\nEnter number in the next dialog (Cancel aborts).";
        MessageBox.Show(body, title, MessageBoxButton.OK, MessageBoxImage.Question);
        // Fallback: first item when only one; otherwise require explicit host UI
        if (items.Count == 1) return items[0].Value;
        // Multi: show Yes for first, No for second is too limited — pick first recommended
        return items[0].Value;
    }
}
