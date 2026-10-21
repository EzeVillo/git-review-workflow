import {CommentDocumentKind, CommentDocument, CommentsReport} from "../cli/commentsPorcelain";
import {COMMENTS_COPY as copy} from "./userCopy";

export function commentDestinations(report: CommentsReport, operation = "add"): ("local" | "shared")[] {
    return [...new Set(report.rows.filter(r => r.tag === "comments-capability" && r.fields[0] === operation).map(r => r.fields[1]).filter((kind): kind is "local" | "shared" => kind === "local" || kind === "shared"))];
}
export function commentsOwnedBy(report: CommentsReport, owners: readonly string[]): CommentDocument[] {
    const contexts = new Set(report.contexts.filter(context => context.owner !== undefined && owners.includes(context.owner)).map(context => context.id));
    return report.documents.filter(document => contexts.has(document.context));
}

export type CommentScope = "selection" | "file" | "general";
export interface CommentLocation {hasSelection?: boolean; snippet?: string; path: string; side: "base" | "head"; start: number; end: number; startColumn?: number; endColumn?: number; unversioned?: boolean; base?: string; head?: string; basePath?: string; headPath?: string}
/** Wire positions are 1-based UTF-16, with an exclusive end when columns exist. */
export function selectionCoordinates(anchor: {line: number; character: number}, active: {line: number; character: number}): Pick<CommentLocation, "start" | "end" | "startColumn" | "endColumn"> {
    const forward = anchor.line < active.line || (anchor.line === active.line && anchor.character <= active.character);
    const [start, end] = forward ? [anchor, active] : [active, anchor];
    return {start: start.line + 1, end: end.line + 1, startColumn: start.character + 1, endColumn: end.character + 1};
}
export function commentRangeEndpoints(location: Pick<CommentLocation, "start" | "end" | "startColumn" | "endColumn">, lengths: readonly number[]): [{line: number; character: number}, {line: number; character: number}] {
    const {start, end, startColumn, endColumn} = location;
    const precise = startColumn !== undefined || endColumn !== undefined;
    const first = precise ? (startColumn ?? 0) - 1 : 0;
    const last = precise ? (endColumn ?? 0) - 1 : lengths[end - 1];
    if (![start, end, first, last].every(Number.isSafeInteger) || start < 1 || end < start || end > lengths.length || first < 0 || last < 0 || first > lengths[start - 1] || last > lengths[end - 1] || (precise && start === end && first >= last)) throw Error(copy.rangeUnavailable);
    return [{line: start - 1, character: first}, {line: end - 1, character: last}];
}
export function selectionLines(anchor: {line: number; character: number}, active: {line: number; character: number}): [number, number] {
    const ordered = anchor.line < active.line || (anchor.line === active.line && anchor.character <= active.character) ? [anchor, active] : [active, anchor];
    const [start, end] = ordered;
    return [start.line + 1, Math.max(start.line + 1, end.line + (end.line > start.line && end.character === 0 ? 0 : 1))];
}
export function commentsArgs(report: CommentsReport, operation: string, kind?: CommentDocumentKind, context?: string, ordinal?: number): string[] {
    const args = [operation];
    if (kind && operation !== "prepare") args.push("--document", kind);
    if (context) args.push("--context", context);
    if (operation === "entries") {args.push("--porcelain"); return args;}
    const guard = context ? report.contexts.find(c => c.id === context)?.guard ?? report.guard : report.guard;
    if (!guard) throw new Error(copy.missingContext);
    args.push("--expect-context", guard);
    if (operation === "save") {
        for (const document of ["local", "shared"] as const) {
            const doc = report.documents.find(d => d.kind === document && (!context || d.context === context));
            if (doc?.revision === "unreadable") throw new Error(copy.unreadable);
            args.push("--expect-" + document, doc?.revision ?? "absent");
        }
    } else {
        const doc = report.documents.find(d => d.kind === kind && (!context || d.context === context));
        if (doc?.revision === "unreadable") throw new Error(copy.unreadable);
        args.push("--expect-document", doc?.revision ?? "absent");
    }
    if (ordinal !== undefined) args.push("--entry", String(ordinal));
    return args;
}
export interface SavableComment {isDirty: boolean; save(): PromiseLike<boolean>}
export async function saveCommentBuffers(documents: readonly SavableComment[]): Promise<boolean> {
    for (const doc of documents) {
        if (!doc.isDirty) continue;
        try {if (!(await doc.save()) || doc.isDirty) return false;} catch {return false;}
    }
    return true;
}
