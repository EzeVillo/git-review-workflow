using System.Diagnostics;
using GitReview.Domain;

namespace GitReview.VS.ToolWindows;

/// <summary>
/// THE ONLY GATE to bringing the panel into view, which is why it takes the id:
/// that is what makes the canonical's <c>reveals:</c> GOVERN instead of merely
/// describe — the lesson <c>confirms:</c> left, having been declared in three
/// places and governing in none.
///
/// It is called AFTER the refresh and only on success: revealing a panel that did
/// not change is the jump that teaches people to ignore jumps, and on a failure
/// the message is already on screen.
///
/// The vehicle comes from <see cref="PanelHost"/>, like every other host
/// capability here; the decision of whether it applies lives in the domain.
/// </summary>
internal static class PanelReveal
{
    public static void Reveal(ControlId id, PanelHost? host)
    {
        if (!PanelLayoutBuilder.RevealsPanel(id))
        {
            // An id the canonical does not declare does NOT reveal: here the safe
            // degradation is the opposite of Confirm's — an extra reveal makes the
            // panel jump when it should not, which is exactly the noise this table
            // exists to avoid.
            Debug.Fail($"Reveal() called for {id.Wire()}, which the canonical does not list under reveals:");
            return;
        }
        host?.RevealPanel?.Invoke();
    }
}
