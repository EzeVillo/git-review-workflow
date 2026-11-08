import * as vscode from "vscode";
import {confirmMutation} from "../review/confirm";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import * as path from "node:path";
import {CommentDocument, CommentsReport, parseComments} from "../cli/commentsPorcelain";
import {invokeGitReview, InvokeOptions, InvokeResult} from "../cli/invoke";
import {commentsArgs, commentsOwnedBy, commentDestinations, CommentLocation, saveCommentBuffers, selectionCoordinates, commentRangeEndpoints} from "../review/commentsFlow";
import {sameDraftFile} from "../review/draftFlow";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {COMMENTS_COPY as copy, STALE} from "../review/userCopy";
import {commentsComposer} from "../views/commentsComposer";
import {commentsBrowser} from "../views/commentsBrowser";
import {presentComment, CommentPresentation} from "../review/commentPresentation";
import {PanelRevealer, revealPanel} from "../views/reveal";

export const COMMENT_BLOB_SCHEME = "git-review-comment";
const readGit = promisify(execFile);
let saveCommentDocument = (document: vscode.TextDocument): Thenable<boolean> => document.save();
/** The integration harness substitutes the save boundary; TextDocument is immutable. */
export function setCommentDocumentSaverForTest(save?: (document: vscode.TextDocument) => Thenable<boolean>): void {
    saveCommentDocument = save ?? (document => document.save());
}
/** Provenance belongs to views we opened, never inferred from a host URI. */
export const commentProvenance = new Map<string, CommentLocation>();
const commentRanges = new Map<string, {base: string; head: string}>();
const rootKey = (cwd: string): string => process.platform === "win32" ? path.resolve(cwd).toLowerCase() : path.resolve(cwd);
export function rememberCommentRange(cwd: string, report?: CommentsReport): void {
    if (report?.base && report.head) commentRanges.set(rootKey(cwd), {base: report.base, head: report.head});
    else commentRanges.delete(rootKey(cwd));
}
export function commentRange(cwd: string): {base: string; head: string} | undefined {return commentRanges.get(rootKey(cwd));}
export function rememberCommentSide(cwd: string, uri: vscode.Uri, file: string, side: "base" | "head", before?: string, after?: string, commit?: string): vscode.Uri {
    const range = commentRange(cwd);
    if (!range || (commit && !range.head.startsWith(commit))) return uri;
    const location: CommentLocation = {path: file, side, start: 1, end: 1, basePath: before, headPath: after};
    if (uri.scheme !== "file") {location.base = range.base; location.head = range.head;}
    commentProvenance.set(uri.toString(), location);
    return uri;
}
export class CommentBlobProvider implements vscode.TextDocumentContentProvider {
    async provideTextDocumentContent(uri: vscode.Uri): Promise<string> {
        const query = JSON.parse(uri.query) as {cwd: string; oid?: string};
        if (!query.oid) return ""; // Only an explicit absent side has no OID.
        if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(query.oid)) throw Error(copy.historyFailed);
        const result = await readGit("git", ["cat-file", "blob", query.oid], {cwd: query.cwd, encoding: "utf8", env: {...process.env, GIT_NO_LAZY_FETCH: "1"}, windowsHide: true, timeout: 30000, maxBuffer: 20 * 1024 * 1024});
        return result.stdout;
    }
}
function failure(result: InvokeResult): string | undefined {
    return result.exitCode === 0 ? undefined : result.exitCode === 4 ? STALE : result.stderr.trim() || copy.failed;
}
export async function readComments(options: InvokeOptions, context?: string, all = false): Promise<CommentsReport> {
    const result = await invokeGitReview("comments", ["status", "--porcelain", ...(context ? ["--context", context] : []), ...(all ? ["--all"] : [])], options);
    const report = parseComments(result.stdout);
    if (result.exitCode !== 0) report.diagnostics.push({path: "", code: "read", message: result.stderr.trim() || copy.failed});
    return report;
}
async function savePaths(documents: readonly CommentDocument[]): Promise<boolean> {
    return saveCommentBuffers(vscode.workspace.textDocuments.filter(doc => doc.uri.scheme === "file" && documents.some(row => sameDraftFile(doc.uri.fsPath, row.path))).map(doc => ({get isDirty() {return doc.isDirty;}, save: () => saveCommentDocument(doc)})));
}
export async function saveSessionComments(manager: ReviewStateManager, options: InvokeOptions, source?: string, scope = "active"): Promise<boolean> {
    try {
        if (vscode.workspace.textDocuments.every(document => document.isDirty === false)) return true;
    } catch { /* Unknown keeps the selective ownership query. */ }
    const response = await invokeGitReview("comments", ["status", "--porcelain", ...(scope !== "active" ? ["--all"] : [])], options);
    if (response.exitCode !== 0 || response.timedOut || response.errorCode) {
        await manager.refreshPrimary();
        void vscode.window.showErrorMessage(copy.saveFailed);
        return false;
    }
    const report = parseComments(response.stdout);
    if (source === undefined && scope === "all") {
        source = manager.state.state?.source;
        const current = manager.state.fixes?.find(row => row.current);
        if (source === undefined && current?.name.startsWith("review-fixes/")) source = current.name.slice("review-fixes/".length);
        if (source === undefined) return true;
    }
    const owners = report.contexts.filter(c => (scope === "all" || c.state === scope) && (source === undefined || c.source === source) && (scope !== "all" || c.owner === "review/" + source)).map(c => c.owner).filter((owner): owner is string => owner !== undefined);
    if (await savePaths(commentsOwnedBy(report, owners))) return true;
    await manager.refresh();
    void vscode.window.showErrorMessage(copy.saveFailed);
    return false;
}
let lastCommentEditor: vscode.TextEditor | undefined;
/** Diff selections can belong to the side that activeTextEditor does not report. */
export function rememberCommentEditor(editor: vscode.TextEditor | undefined): void {
    if (editor) lastCommentEditor = editor;
}
function captureLocation(cwd: string): CommentLocation | undefined {
    const editor = lastCommentEditor ?? vscode.window.activeTextEditor;
    // Moving focus into the panel keeps the visible code selection. Closing a
    // tab must clear it even while VS Code keeps its TextDocument in memory.
    if (!editor || editor.document.isClosed || !vscode.window.visibleTextEditors.includes(editor)) {
        lastCommentEditor = undefined;
        return undefined;
    }
    const original = commentProvenance.get(editor.document.uri.toString());
    if (original) {
        return {...original, ...selectionCoordinates(editor.selection.anchor, editor.selection.active), hasSelection: !editor.selection.isEmpty, snippet: editor.document.getText(editor.selection).slice(0, 2000), ...(editor.document.isDirty ? {unversioned: true} : {})};
    }
    if (editor.document.uri.scheme !== "file") return undefined;
    const relative = path.relative(cwd, editor.document.uri.fsPath).replace(/\\/g, "/");
    if (relative.startsWith("../") || path.isAbsolute(relative)) return undefined;
    return {path: relative, side: "head", ...selectionCoordinates(editor.selection.anchor, editor.selection.active), hasSelection: !editor.selection.isEmpty, snippet: editor.document.getText(editor.selection).slice(0, 2000), ...(editor.document.isDirty ? {unversioned: true} : {})};
}
export async function addComment(lock: MutationLock, manager: ReviewStateManager, getOptions: () => InvokeOptions, reveal: PanelRevealer): Promise<void> {
    // Read selection before any picker or webview moves focus.
    const options = getOptions();
    const location = manager.state.situation === "finish-conflict" ? undefined : captureLocation(options.cwd);
    const opaque = !location && !!vscode.window.activeTextEditor && manager.state.situation !== "finish-conflict";
    if (!["review", "finish-conflict"].includes(manager.state.situation)) return;
    const initial = await readComments(options);
    const destinations = commentDestinations(initial);
    if (!initial.guard || !destinations.length) return;
    let choice: string | undefined;
    if (initial.identity === "ambiguous") {
        const selected = await vscode.window.showQuickPick([
            {label: copy.newContext, description: copy.newContextDetail, id: ""},
            ...initial.candidates.map(c => ({label: copy.continueContext + ": " + c.label, description: copy.continueContextDetail, detail: c.description, id: c.id})),
        ], {title: copy.chooseContext, placeHolder: destinations.includes("shared") ? copy.contextHint : copy.localContextHint, matchOnDetail: true});
        if (!selected) return;
        choice = selected.id;
    }
    commentsComposer(location, destinations, async (kind, text, scope) => {
        let entered = false;
        const outcome = await lock.run(async () => {
            entered = true;
            const current = await readComments(options);
            if (current.guard !== initial.guard) {await manager.refresh(); return STALE;}
            if (!(await savePaths(current.documents.filter(d => d.kind === kind)))) {await manager.refresh(); return copy.saveFailed;}
            const fresh = await readComments(options);
            if (fresh.guard !== initial.guard) {await manager.refresh(); return STALE;}
            const born = !fresh.documents.some(d => d.presence === "present");
            const args = commentsArgs(fresh, "add", kind);
            args.push("--stdin");
            if (choice !== undefined) args.push(choice ? "--use-context" : "--new-context", ...(choice ? [choice] : []));
            if (location && scope !== "general" && manager.state.situation !== "finish-conflict") {
                args.push("--path", location.path, "--side", location.side);
                if (scope === "selection") args.push("--start-line", String(location.start), "--end-line", String(location.end));
                if (scope === "selection" && location.startColumn !== undefined && location.endColumn !== undefined) args.push("--start-column", String(location.startColumn), "--end-column", String(location.endColumn));
                if (location.unversioned) args.push("--unversioned");
                if (location.base && location.head) args.push("--base", location.base, "--head", location.head);
                if (location.basePath) args.push("--base-path", location.basePath);
                if (location.headPath) args.push("--head-path", location.headPath);
            }
            const result = await invokeGitReview("comments", args, {...options, stdin: text});
            await manager.refresh();
            const error = failure(result);
            if (!error && born) revealPanel("addComment", reveal, true);
            return error;
        });
        return entered ? outcome : copy.failed;
    }, opaque ? copy.opaque : undefined);
}
export async function commentRowAction(action: string, index: unknown, lock: MutationLock, manager: ReviewStateManager, getOptions: () => InvokeOptions): Promise<void> {
    try {
    if (typeof index !== "number" || !Number.isInteger(index)) return;
    const row = manager.state.comments?.documents[index]; if (!row) return;
    if (action === "copyCommentPath") {
        if (row.kind !== "local" || row.presence !== "present") return;
        await vscode.env.clipboard.writeText(row.path);
        void vscode.window.showInformationMessage(copy.pathCopied);
        return;
    }
    if (action === "openComments") {await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(vscode.Uri.file(row.path)), {preview: false}); return;}
    if (action === "deleteComments" && !await confirmMutation("deleteComments", copy.deleteTitle, copy.deleteDetail, copy.delete)) return;
    await lock.run(async () => {
        const options = getOptions(), initial = await readComments(options, row.context);
        if (!(await savePaths([row]))) {void vscode.window.showErrorMessage(copy.saveFailed); return;}
        const fresh = await readComments(options, row.context);
        if ((fresh.guard ?? fresh.contexts[0]?.guard) !== (initial.guard ?? initial.contexts[0]?.guard)) {void vscode.window.showInformationMessage(STALE); return;}
        if (action === "prepareSharedComments") {
            const choice = await vscode.window.showQuickPick([{label: copy.compareDelivery, compare: true}, {label: copy.retryDelivery, compare: false}], {title: copy.deliveryTitle});
            if (!choice) return;
            const checkArgs = [...commentsArgs(fresh, "prepare", "shared", row.context), "--check", "--porcelain"];
            const check = await invokeGitReview("comments", checkArgs, options);
            if (failure(check)) {void vscode.window.showErrorMessage(failure(check)!); return;}
            const files = parseComments(check.stdout).deliveryFiles;
            if (choice.compare) {
                const side = (role: string): vscode.Uri => {
                    const file = files.find(f => f.role === role); if (!file) throw Error(copy.failed);
                    return file.presence === "present" ? vscode.Uri.file(file.path) : vscode.Uri.from({scheme: COMMENT_BLOB_SCHEME, path: "/absent-" + role, query: JSON.stringify({cwd: options.cwd})});
                };
                await vscode.commands.executeCommand("vscode.diff", side("prepared"), side("destination"), copy.deliveryTitle);
                return;
            }
            if (!(await savePaths(files.filter(f => f.role !== "baseline").map(f => ({path: f.path, context: row.context, kind: "shared" as const, presence: f.presence, revision: f.revision}))))) {void vscode.window.showErrorMessage(copy.saveFailed); return;}
            const ready = await readComments(options, row.context);
            if ((ready.guard ?? ready.contexts[0]?.guard) !== (fresh.guard ?? fresh.contexts[0]?.guard)) {void vscode.window.showInformationMessage(STALE); return;}
            const result = await invokeGitReview("comments", commentsArgs(ready, "prepare", "shared", row.context), options);
            await manager.refresh();
            if (failure(result)) void vscode.window.showErrorMessage(failure(result)!);
            return;
        }
        if (action === "openCommentDiff") {
            const entries = await invokeGitReview("comments", commentsArgs(fresh, "entries", row.kind, row.context), options);
            if (failure(entries)) {void vscode.window.showErrorMessage(failure(entries)!); return;}
            let report = parseComments(entries.stdout);
            if (!report.entries.length) {void vscode.window.showInformationMessage(copy.empty); return;}
            const presentations = () => report.entries.map(e => presentComment(report, e));
            const canDelete = fresh.contexts.some(c => c.id === row.context && (["active", "result"].includes(c.state) || (c.state === "repository" && row.kind === "local")));
            commentsBrowser(presentations(), async ordinal => {
                const entry = report.entries.find(e => e.ordinal === ordinal);
                if (!entry || !presentComment(report, entry).canOpenDiff) return;
                const args = commentsArgs({...fresh, documents: report.documents}, "diff", row.kind, row.context, ordinal);
                const recipe = await invokeGitReview("comments", [...args, "--porcelain"], options);
                if (failure(recipe)) throw Error(failure(recipe));
                await openCommentRecipe(parseComments(recipe.stdout), options, args, presentComment(report, entry));
            }, canDelete ? async ordinal => {
                let outcome: CommentPresentation[] | undefined;
                const entered = await lock.run(async () => {
                    try {
                        if (!await savePaths([row])) throw Error(copy.saveFailed);
                        const args = commentsArgs({...fresh, documents: report.documents}, "delete", row.kind, row.context, ordinal);
                        const result = await invokeGitReview("comments", args, options);
                        if (failure(result)) throw Error(failure(result));
                        const next = await invokeGitReview("comments", commentsArgs(fresh, "entries", row.kind, row.context), options);
                        if (failure(next)) throw Error(failure(next));
                        report = parseComments(next.stdout);
                        outcome = presentations();
                        return true;
                    } finally {await manager.refresh();}
                });
                if (!entered || !outcome) throw Error(copy.failed);
                return outcome;
            } : undefined);
            return;
        }
        const operation = action === "deleteComments" ? "delete" : action === "initComments" ? "init" : action === "renumberComments" ? "renumber" : "prepare";
        const args = commentsArgs(fresh, operation, row.kind, row.context);
        if (operation === "delete") args[args.indexOf("--expect-document") + 1] = row.revision;
        const result = await invokeGitReview("comments", args, options);
        await manager.refresh();
        const error = failure(result); if (error) void vscode.window.showErrorMessage(error);
    });
    } catch (error) {
        await manager.refresh();
        void vscode.window.showErrorMessage(error instanceof Error ? error.message : copy.failed);
    }
}
async function openCommentRecipe(report: CommentsReport, options: InvokeOptions, guardedArgs: string[], comment: CommentPresentation): Promise<void> {
    if (report.blobs.length === 0) {
        // A general comment has a range but no invented file. Let CLI render it.
        const result = await invokeGitReview("comments", guardedArgs, options);
        if (failure(result)) throw Error(failure(result));
        await vscode.window.showTextDocument(await vscode.workspace.openTextDocument({language: "diff", content: comment.location + "\n" + comment.version + "\n" + comment.warning + "\n\n" + comment.body + "\n\n" + result.stdout}), {viewColumn: vscode.ViewColumn.Beside}); return;
    }
    const uri = (side: string): vscode.Uri => {
        const blob = report.blobs.find(b => b.side === side);
        if (!blob || !["present", "absent"].includes(blob.presence) || (blob.presence === "present" && !blob.oid)) throw Error(copy.historyFailed);
        const file = blob.path.replace(/%(25|09|0D|0A|3E)/g, (_, value: string) => ({"25": "%", "09": "\t", "0D": "\r", "0A": "\n", "3E": ">"}[value]!));
        const result = vscode.Uri.from({scheme: COMMENT_BLOB_SCHEME, path: "/" + file, query: JSON.stringify({cwd: options.cwd, oid: blob.oid})});
        if (blob.presence === "present" && report.range) commentProvenance.set(result.toString(), {path: file, side: side === "base" ? "base" : "head", start: 1, end: 1, base: report.range.base, head: report.range.head});
        return result;
    };
    const base = uri("base"), head = uri("head");
    highlights.delete(base.toString()); highlights.delete(head.toString()); highlightVisible();
    // Read both before opening; a missing blob cannot masquerade as an empty side.
    await vscode.workspace.openTextDocument(base); await vscode.workspace.openTextDocument(head);
    await vscode.commands.executeCommand("vscode.diff", base, head, comment.location + " · " + comment.preview.slice(0, 60), {viewColumn: vscode.ViewColumn.Beside});
    const location = report.locations.find(l => l.ordinal === comment.ordinal);
    if (location) {
        const target = location.side === "base" ? base : head;
        const document = await vscode.workspace.openTextDocument(target);
        const [start, end] = commentRangeEndpoints(location, Array.from({length: document.lineCount}, (_, i) => document.lineAt(i).text.length));
        const range = new vscode.Range(start.line, start.character, end.line, end.character);
        highlightComment(target, range, comment.body, location.startColumn === undefined);
    }
}

/** Decorations survive focus changes and unified/side-by-side viewer switches. */
const highlights = new Map<string, {range: vscode.Range; body: string; wholeLine: boolean}>();
export function commentHighlights(): vscode.Disposable {
    const style = {backgroundColor: new vscode.ThemeColor("editor.findMatchHighlightBackground"), border: "1px solid", borderColor: new vscode.ThemeColor("editor.findMatchBorder"), overviewRulerColor: new vscode.ThemeColor("editorOverviewRuler.findMatchForeground")};
    const decoration = vscode.window.createTextEditorDecorationType({...style, isWholeLine: false});
    const wholeLineDecoration = vscode.window.createTextEditorDecorationType({...style, isWholeLine: true});
    const apply = (editors: readonly vscode.TextEditor[]) => {
        for (const editor of editors) {
            const mark = highlights.get(editor.document.uri.toString());
            const options = mark ? [{range: mark.range, hoverMessage: new vscode.MarkdownString().appendText(mark.body)}] : [];
            editor.setDecorations(decoration, mark && !mark.wholeLine ? options : []);
            editor.setDecorations(wholeLineDecoration, mark?.wholeLine ? options : []);
            if (mark) {
                editor.selection = new vscode.Selection(mark.range.start, mark.range.end);
                editor.revealRange(mark.range, vscode.TextEditorRevealType.InCenterIfOutsideViewport);
            }
        }
    };
    highlightVisible = () => apply(vscode.window.visibleTextEditors);
    const changed = vscode.window.onDidChangeVisibleTextEditors(apply);
    const closed = vscode.workspace.onDidCloseTextDocument(document => highlights.delete(document.uri.toString()));
    return {dispose() {changed.dispose(); closed.dispose(); decoration.dispose(); wholeLineDecoration.dispose(); highlights.clear(); highlightVisible = () => {};}};
}
let highlightVisible = () => {};
function highlightComment(uri: vscode.Uri, range: vscode.Range, body: string, wholeLine: boolean): void {
    highlights.set(uri.toString(), {range, body, wholeLine}); highlightVisible();
}

export function commentTarget(cwd: string): string {
    const capture = captureLocation(cwd);
    return capture ? (capture.hasSelection ? copy.selection + " · " + capture.path + ":" + capture.start + (capture.startColumn !== undefined ? ":" + capture.startColumn : "") + "–" + capture.end + (capture.endColumn !== undefined ? ":" + capture.endColumn : "") : copy.file + " · " + capture.path) + " (" + (capture.side === "base" ? copy.baseSide : copy.headSide) + ")" : copy.general;
}
