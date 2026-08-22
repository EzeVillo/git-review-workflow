using System;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace GitReview.VS.Vsix;

/// <summary>
/// The fourth refresh signal, and the narrowest: a document the shell just saved.
///
/// It exists for the authoring guides, which have no watcher — the reviewer's lives in
/// the ROOT of the gitdir, which changes on every git operation, so watching that
/// directory would be a storm of notifications over the file that changes least. What
/// the panel needs is not "the file changed" but "the person finished writing it", and
/// that is exactly what a save is.
///
/// The equivalent in the other two clients is the same idea in their own shape: VS Code
/// subscribes to <c>onDidSaveTextDocument</c>, IntelliJ matches the VFS event a save
/// produces. None of the three adds a watch root for a guide.
///
/// The moniker is handed on raw. Deciding whether it is one of the guides is the
/// domain's job (<c>DraftWatch.IsReportedGuide</c>), against the paths the CLI reported
/// — never against a path rebuilt from the gitdir layout.
/// </summary>
internal sealed class DocumentSaveListener : IVsRunningDocTableEvents3, IDisposable
{
    private readonly Action<string> _onSaved;
    private IVsRunningDocumentTable? _rdt;
    private uint _cookie;

    private DocumentSaveListener(Action<string> onSaved) => _onSaved = onSaved;

    /// <summary>
    /// Advise the running document table, or answer null when the shell cannot give it
    /// to us. Null is not an error worth surfacing: it costs the panel one automatic
    /// refresh, and Refresh is a button.
    /// </summary>
    public static DocumentSaveListener? Attach(IServiceProvider services, Action<string> onSaved)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (services.GetService(typeof(SVsRunningDocumentTable)) is not IVsRunningDocumentTable rdt)
        {
            return null;
        }
        var listener = new DocumentSaveListener(onSaved) { _rdt = rdt };
        if (ErrorHandler.Failed(rdt.AdviseRunningDocTableEvents(listener, out listener._cookie)))
        {
            return null;
        }
        return listener;
    }

    public int OnAfterSave(uint docCookie)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        var moniker = MonikerOf(docCookie);
        if (!string.IsNullOrEmpty(moniker)) _onSaved(moniker!);
        return VSConstants.S_OK;
    }

    private string? MonikerOf(uint docCookie)
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (_rdt is null) return null;
        try
        {
            return ErrorHandler.Succeeded(_rdt.GetDocumentInfo(
                docCookie,
                out _,
                out _,
                out _,
                out var moniker,
                out _,
                out _,
                out _))
                ? moniker
                : null;
        }
        catch (Exception)
        {
            // A cookie the table no longer knows is one save we do not react to, not a
            // reason to take the panel down with it.
            return null;
        }
    }

    public void Dispose()
    {
        ThreadHelper.ThrowIfNotOnUIThread();
        if (_rdt is not null && _cookie != 0)
        {
            _rdt.UnadviseRunningDocTableEvents(_cookie);
        }
        _cookie = 0;
        _rdt = null;
    }

    // The rest of the table's events are not ours. Implemented, never acted on: the
    // interface is all-or-nothing, and a partial implementation does not compile.
    public int OnAfterFirstDocumentLock(uint c, uint l, uint e, uint d) => VSConstants.S_OK;

    public int OnBeforeLastDocumentUnlock(uint c, uint l, uint e, uint d) => VSConstants.S_OK;

    public int OnAfterAttributeChange(uint c, uint a) => VSConstants.S_OK;

    public int OnBeforeDocumentWindowShow(uint c, int f, IVsWindowFrame frame) => VSConstants.S_OK;

    public int OnAfterDocumentWindowHide(uint c, IVsWindowFrame frame) => VSConstants.S_OK;

    public int OnAfterAttributeChangeEx(
        uint c,
        uint a,
        IVsHierarchy hOld,
        uint idOld,
        string mkOld,
        IVsHierarchy hNew,
        uint idNew,
        string mkNew) => VSConstants.S_OK;

    public int OnBeforeSave(uint docCookie) => VSConstants.S_OK;
}
