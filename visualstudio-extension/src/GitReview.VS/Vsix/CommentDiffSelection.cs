using GitReview.Domain;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Editor;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Differencing;
using Microsoft.VisualStudio.Text.Editor;

namespace GitReview.VS.Vsix;

internal static class CommentDiffSelection
{
    public static void Apply(IVsWindowFrame frame, IReadOnlyList<string> location, IReadOnlyList<string>? columns = null)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        ErrorHandler.ThrowOnFailure(frame.GetProperty((int)__VSFPROPID.VSFPROPID_DocView, out var view));
        if (view is not IVsDifferenceCodeWindow code) throw new InvalidOperationException(CommentsCopy.rangeUnavailable);
        var viewer = code.DifferenceViewer;
        var source = location[1] == "base" ? viewer.LeftView : viewer.RightView;
        var first = int.Parse(location[2]); var last = int.Parse(location[3]);
        var snapshot = source.TextSnapshot;
        if (first < 1 || last < first || last > snapshot.LineCount) throw new InvalidOperationException(CommentsCopy.rangeUnavailable);
        var offsets = Comments.TextOffsets(snapshot.GetText(), first, last, columns is null ? null : int.Parse(columns[2]), columns is null ? null : int.Parse(columns[3]));
        var span = new SnapshotSpan(snapshot, Span.FromBounds(offsets.Start, offsets.End));
        void Reveal() {
            if (source.IsClosed) return;
            var target = viewer.ViewMode == DifferenceViewMode.Inline ? viewer.InlineView : source;
            var mapped = target.BufferGraph.MapUpToBuffer(span, SpanTrackingMode.EdgeInclusive, target.TextBuffer);
            if (mapped.Count == 0) return; // Inline projection is populated asynchronously.
            var selection = new SnapshotSpan(mapped[0].Start, mapped[mapped.Count - 1].End);
            target.Selection.Select(selection, false);
            target.ViewScroller.EnsureSpanVisible(selection, EnsureSpanVisibleOptions.AlwaysCenter);
        }
        void Changed(object? sender, EventArgs args) => Reveal();
        viewer.ViewModeChanged += Changed;
        viewer.DifferenceBuffer.SnapshotDifferenceChanged += Changed;
        viewer.Closed += (_,_) => { viewer.ViewModeChanged -= Changed; viewer.DifferenceBuffer.SnapshotDifferenceChanged -= Changed; };
        Reveal();
    }
}
