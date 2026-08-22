namespace GitReview.Domain;

public sealed record ActionArgv(string Verb, IReadOnlyList<string> Args, bool Network = false);

public abstract record ActionParams
{
    public sealed record Start(ReviewIntent Intent, string CurrentBranch) : ActionParams;
    public sealed record Continue(string Source) : ActionParams;
    public sealed record Empty : ActionParams
    {
        public static readonly Empty Instance = new();
    }
    public sealed record FinishOnto(bool OntoSource) : ActionParams;
    public sealed record UndoFinish(bool Force) : ActionParams;
    public sealed record ResumeFinish(bool OntoSource) : ActionParams;
    public sealed record Preview(bool Stat) : ActionParams;
    public sealed record Compare(IReadOnlyList<string> LayoutFlags, string Lower, string Upper) : ActionParams;
    public sealed record Housekeeping(HousekeepingAction Action) : ActionParams;
    public sealed record SetConfig(string Key, string Name) : ActionParams;
    public sealed record WalkthroughInit(bool Force) : ActionParams;
    /// <summary>012: discard ONE branch's draft, from the panel's draft block.</summary>
    public sealed record ForgetDraft(string Source) : ActionParams;

    /// <summary>Create an authoring guide, empty: the repository's shared one or yours.</summary>
    public sealed record CreateGuide(bool Team) : ActionParams;

    /// <summary>Remove yours. The shared one is not removed here: that is git rm plus a commit.</summary>
    public sealed record DeleteGuide : ActionParams;
    public sealed record WalkthroughBuild : ActionParams
    {
        public static readonly WalkthroughBuild Instance = new();
    }
    public sealed record Version : ActionParams
    {
        public static readonly Version Instance = new();
    }
    public sealed record StatusPorcelain : ActionParams
    {
        public static readonly StatusPorcelain Instance = new();
    }
    public sealed record StatusWhy(string RawPath) : ActionParams;
    public sealed record ListPorcelain : ActionParams
    {
        public static readonly ListPorcelain Instance = new();
    }
    public sealed record ConfigPorcelain : ActionParams
    {
        public static readonly ConfigPorcelain Instance = new();
    }
}

/// <summary>
/// Table-driven (action, params) → argv for the 27 contributes.commands.
/// </summary>
public static class ActionArgvMap
{
    public static ActionArgv ActionToArgv(string action, ActionParams? params_ = null)
    {
        params_ ??= ActionParams.Empty.Instance;
        return action switch
        {
            "startReview" => params_ is ActionParams.Start p
                ? new ActionArgv("start", ReviewIntentLogic.IntentToArgs(p.Intent, p.CurrentBranch), Network: true)
                : throw new ArgumentException("startReview requires Start params"),
            "continueReview" => params_ is ActionParams.Continue c
                ? new ActionArgv("continue", new[] { c.Source })
                : throw new ArgumentException("continueReview requires Continue params"),
            // Never --all nor --saved: an action on one row does not touch the others.
            "forgetDraft" => new ActionArgv(
                "forget",
                ReviewIntentLogic.ForgetDraftArgs(((ActionParams.ForgetDraft)params_!).Source)),
            // The verb is walkthrough; guide is the first argument, like draft.
            "createGuide" => new ActionArgv(
                "walkthrough",
                ReviewIntentLogic.CreateGuideArgs(((ActionParams.CreateGuide)params_!).Team)),
            "deleteGuide" => new ActionArgv("walkthrough", ReviewIntentLogic.DeleteGuideArgs()),
            "saveReview" => new ActionArgv("save", Array.Empty<string>()),
            "abortReview" => new ActionArgv("abort", Array.Empty<string>()),
            "finishReview" => new ActionArgv(
                "finish",
                params_ is ActionParams.FinishOnto { OntoSource: true }
                    ? new[] { "--onto-source" }
                    : Array.Empty<string>()),
            "undoFinish" => new ActionArgv(
                "finish",
                params_ is ActionParams.UndoFinish { Force: true }
                    ? new[] { "--abort", "--force" }
                    : new[] { "--abort" }),
            "resumeFinish" => new ActionArgv(
                "finish",
                params_ is ActionParams.ResumeFinish { OntoSource: true }
                    ? new[] { "--resume", "--onto-source" }
                    : new[] { "--resume" }),
            "next" => new ActionArgv("next", Array.Empty<string>()),
            "prev" => new ActionArgv("prev", Array.Empty<string>()),
            "previewEdits" => new ActionArgv("preview", Array.Empty<string>()),
            "previewEditsStat" => new ActionArgv("preview", new[] { "--stat" }),
            "compareReview" => params_ is ActionParams.Compare cmp
                ? new ActionArgv("compare", cmp.LayoutFlags.Concat(new[] { "--", cmp.Lower, cmp.Upper }).ToList())
                : throw new ArgumentException("compareReview requires Compare params"),
            "cleanReview" or "discardInventory" or "forgetReview" => params_ is ActionParams.Housekeeping hk
                ? new ActionArgv(
                    HousekeepingLogic.VerbForHousekeeping(hk.Action),
                    HousekeepingLogic.ArgsForHousekeeping(hk.Action),
                    Network: HousekeepingLogic.HousekeepingNeedsNetwork(hk.Action))
                : throw new ArgumentException("housekeeping action requires Housekeeping params"),
            "setBase" => params_ is ActionParams.SetConfig sb
                ? new ActionArgv("config", new[] { "base", "--", sb.Name })
                : throw new ArgumentException("setBase requires SetConfig params"),
            "setRemote" => params_ is ActionParams.SetConfig sr
                ? new ActionArgv("config", new[] { "remote", "--", sr.Name })
                : throw new ArgumentException("setRemote requires SetConfig params"),
            "walkthroughInit" => new ActionArgv(
                "walkthrough",
                params_ is ActionParams.WalkthroughInit { Force: true }
                    ? new[] { "init", "--force" }
                    : new[] { "init" }),
            "walkthroughBuild" => new ActionArgv("walkthrough", new[] { "build" }),
            "openEntry" or "openChange" or "showWhy"
                or "goToEntry" or "refresh" or "installCli" or "showCliLog"
                => new ActionArgv("", Array.Empty<string>()),
            _ => throw new ArgumentException($"unknown action: {action}"),
        };
    }

    /// <summary>
    /// The product actions this client offers: the 27 of
    /// <c>contracts/client-product-surface.yaml</c> minus <c>openAllChanges</c>, which
    /// the contract marks <c>not_in: [visualstudio]</c> — see <c>WholeBlocks</c> in
    /// <c>PanelLayout</c> for why this host cannot open a whole range at once without
    /// spraying a window per file.
    /// </summary>
    public static readonly IReadOnlyList<string> ProductActions = new[]
    {
        "openEntry",
        "openChange",
        "showWhy",
        "next",
        "prev",
        "goToEntry",
        "refresh",
        "installCli",
        "continueReview",
        "startReview",
        "setBase",
        "setRemote",
        "abortReview",
        "saveReview",
        "finishReview",
        "undoFinish",
        "resumeFinish",
        "discardInventory",
        "cleanReview",
        "forgetReview",
        "previewEdits",
        "previewEditsStat",
        "compareReview",
        "walkthroughInit",
        "walkthroughBuild",
        "showCliLog",
    };
}
