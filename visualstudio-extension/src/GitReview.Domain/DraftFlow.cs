namespace GitReview.Domain;

/// <summary>
/// What is left of the draft path inside the wizard (012,
/// contracts/client-draft-panel.md § 3): create, and finish.
///
/// There used to be a loop: create → open → <b>wait</b> → validate → reload
/// offers → pick keys. The wait was a dialog that stayed open while the reviewer
/// wrote their reading order, and everything after it depended on that dialog
/// still being there. What Build, Reload and PickKeys did now lives in
/// "Validate and start", a panel control, over a state that outlives closing the
/// IDE. The wizard waits for nothing.
///
/// It does not open the draft either, and so it no longer needs its path: in the
/// instant after creating it there is no `draft` record yet to carry one, so
/// opening there would need either an extra invocation or building the path
/// again — exactly what this feature removes.
/// </summary>
public abstract record DraftFlowState
{
    /// <summary>
    /// Invoke `walkthrough draft`. Force is the difference between reconciling
    /// what is there — keeping every why whose file is still in range — and
    /// throwing it away for a blank skeleton.
    /// </summary>
    public sealed record Create(bool Force = false, bool Update = false) : DraftFlowState
    {
        public static readonly Create Instance = new();
    }

    /// <summary>
    /// The wizard is finished. No review was started and no notice is left open:
    /// the draft is in the panel, with its four controls.
    /// </summary>
    public sealed record Done : DraftFlowState
    {
        public static readonly Done Instance = new();
    }

    /// <summary>
    /// Back to the reading-shape step, without redoing the branch choice. The
    /// draft is NOT deleted: the next pass offers it as DraftResume. Error only
    /// when going back because of a failure.
    /// </summary>
    public sealed record Back(string? Error = null) : DraftFlowState;
}

public abstract record DraftFlowEvent
{
    /// <summary>Result of `walkthrough draft`.</summary>
    public sealed record Created(bool Ok, string? Error = null) : DraftFlowEvent;
}

public static class DraftFlow
{
    /// <summary>
    /// The three ways in, and only two of them invoke anything:
    /// <list type="bullet">
    /// <item>Create — there is no file: the skeleton is written.</item>
    /// <item>Resume — there is a half-written one and it is used as it is. Nothing
    /// is invoked, so the wizard is already done.</item>
    /// <item>Update — there is one that fell behind the range and it is reconciled
    /// with today's. It is the SAME command as Create: the verb updates instead
    /// of refusing.</item>
    /// </list>
    ///
    /// There is no StartOver, and the absence is deliberate. It existed as the
    /// other half of a modal that asked, over any already-used draft, whether to
    /// reconcile or start from scratch. That modal is gone: the CLI now offers
    /// draft-update only when there IS something to reconcile, so no question is
    /// left to ask. Starting over is the one thing that destroys hand-written
    /// prose, and the modal left it one click away in a step people walked
    /// straight past; it stays available as what it is — a deliberate act — via
    /// Discard on the draft row, or walkthrough draft --force from the terminal.
    /// </summary>
    public static DraftFlowState InitialDraftFlowState(LayoutOffers.DraftStep step) => step switch
    {
        LayoutOffers.DraftStep.Resume => DraftFlowState.Done.Instance,
        // Update no toca el argv: decide el ACUSE. Un create no tiene ninguno --
        // el refresco deja la fila del borrador dibujada, y todo lo que el verbo
        // dice ahi tiene su propia fila en el panel --, y un update si, porque
        // "N kept, M added, K dropped" no se ve en ninguna.
        _ => new DraftFlowState.Create(Update: step == LayoutOffers.DraftStep.Update),
    };

    /// <summary>
    /// Transition. An event that does not belong to the current state leaves it
    /// untouched: the machine invents no paths, and the host cannot skip a step
    /// by sending the wrong event.
    /// </summary>
    public static DraftFlowState AdvanceDraftFlow(DraftFlowState state, DraftFlowEvent ev) => state switch
    {
        // With no draft there is nothing to show in the panel: the failure is
        // the CLI's and the reviewer goes back to the reading-shape step.
        DraftFlowState.Create => ev is DraftFlowEvent.Created c
            ? c.Ok ? DraftFlowState.Done.Instance : new DraftFlowState.Back(c.Error)
            : state,
        DraftFlowState.Done or DraftFlowState.Back => state,
        _ => state,
    };

    /// <summary>
    /// Whether the CLI offers `keys` over an already-validated draft — that is,
    /// whether it carries entries marked essential and there are two readings to
    /// offer. "Validate and start" consumes it, since that is what asks now.
    /// </summary>
    public static bool OffersIncludeKeys(IReadOnlyList<ReadingOffer>? offers) =>
        offers is not null && offers.Any(o => o.Id == OfferId.Keys);
}
