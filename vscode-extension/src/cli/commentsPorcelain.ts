export type CommentDocumentKind = "local" | "shared";
export interface CommentDocument {path: string; context: string; kind: CommentDocumentKind; presence: string; revision: string; count?: number}
export interface CommentContext {id: string; kind: string; state: string; guard: string; label: string; source?: string; owner?: string}
export interface CommentEntry {ordinal: number; number: string; line: number; title: string}
export interface CommentsReport {
    loading?: boolean;
    rows: {tag: string; fields: string[]}[];
    contexts: CommentContext[]; documents: CommentDocument[]; entries: CommentEntry[];
    diagnostics: {path: string; code: string; message: string}[];
    candidates: {id: string; label: string; description?: string}[];
    deliveries: {context: string; state: string; message: string}[];
    blobs: {path: string; side: string; presence: string; oid?: string}[];
    deliveryFiles: {path: string; role: string; presence: string; revision: string}[];
    identity?: string; guard?: string; base?: string; head?: string;
    range?: {ordinal: number; base: string; head: string};
    locations: {ordinal: number; side: string; start: number; end: number; startColumn?: number; endColumn?: number}[];
}
export function supportsCommentsAddReply(report: CommentsReport): boolean {
    return report.rows.some(row => row.tag === "comments-add-reply" && row.fields[0] === "1");
}

export function parseCommentsAddReply(text: string, document: CommentDocumentKind) {
    const lines = text.replace(/[\r\n]+$/, "").split(/\r?\n/);
    const header = lines.shift()?.split("\t");
    const token = /^[0-9a-f]{40}(?:[0-9a-f]{24})?$/;
    if (header?.length !== 4 || header[0] !== "comments-add-result" || header[1] !== "1" ||
        !token.test(header[2]) || !token.test(header[3]) || lines.pop() !== "comments-add-result-end\t1") return undefined;
    const report = parseComments(lines.join("\n"));
    const active = report.contexts.filter(context => context.state === "active");
    if (report.identity !== "resolved" || !report.guard || !token.test(report.guard) || active.length !== 1 ||
        active[0].guard !== report.guard || !report.documents.some(doc => doc.kind === document && doc.context === active[0].id &&
            doc.presence === "present" && token.test(doc.revision) && (doc.count ?? 0) > 0)) return undefined;
    return {before: header[2], after: header[3], report};
}
export function parseComments(text: string): CommentsReport {
    const report: CommentsReport = {rows: [], contexts: [], documents: [], entries: [], diagnostics: [], candidates: [], deliveries: [], blobs: [], deliveryFiles: [], locations: []};
    const minimum: Record<string, number> = {"comments-context": 5, "comments-owner": 2, "comments-guard": 1, "comments-document": 5, "comments-count": 2, "comments-diagnostic": 3, "comments-identity": 2, "comments-candidate": 2, "comments-delivery": 3, "comments-capture": 3, "comment-body": 2, "comment-scope": 3, "comment-entry": 4, "comment-version": 3, "comment-path": 3, "comment-location": 4, "comment-unversioned": 1, "comment-diagnostic": 3, "comment-diff": 3, "comment-blob": 3, "comments-delivery-file": 4};
    minimum["comments-capability"] = 2;
    minimum["comments-add-reply"] = 1;
    const counts = new Map<string, number>();
    minimum["comment-columns"] = 4;
    const owners = new Map<string, string[]>();
    for (const line of text.split(/\r?\n/)) {
        const [tag, ...f] = line.split("\t");
        if (!(tag in minimum) || f.length < minimum[tag]) continue;
        report.rows.push({tag, fields: f});
        switch (tag) {
            case "comments-context": report.contexts.push({id: f[0], kind: f[1], state: f[2], guard: f[3], label: f[4]}); break;
            case "comments-guard": report.guard = f[0]; break;
            case "comments-owner": if (f.length >= 2) owners.set(f[0], f.slice(1)); break;
            case "comments-document": if (f.length >= 5 && (f[2] === "local" || f[2] === "shared")) report.documents.push({path: f[0], context: f[1], kind: f[2], presence: f[3], revision: f[4]}); break;
            case "comments-count": if (/^\d+$/.test(f[1] ?? "")) counts.set(f[0], Number(f[1])); break;
            case "comments-diagnostic": if (f.length >= 3) report.diagnostics.push({path: f[0], code: f[1], message: f[2]}); break;
            case "comments-identity": report.identity = f[0]; break;
            case "comments-candidate": if (f.length >= 2) report.candidates.push({id: f[0], label: f[1], ...(f[2] ? {description: f[2]} : {})}); break;
            case "comments-delivery": if (f.length >= 3) report.deliveries.push({context: f[0], state: f[1], message: f[2]}); break;
            case "comments-capture": if (f.length >= 3) {report.guard = f[0]; report.base = f[1]; report.head = f[2];} break;
            case "comment-entry": if (f.length >= 4 && /^[1-9]\d*$/.test(f[0])) report.entries.push({ordinal: Number(f[0]), number: f[1], line: Number(f[2]), title: f[3]}); break;
            case "comment-diff": if (f.length >= 3) report.range = {ordinal: Number(f[0]), base: f[1], head: f[2]}; break;
            case "comment-blob": if (f.length >= 3) report.blobs.push({path: f[0], side: f[1], presence: f[2], ...(f[3] ? {oid: f[3]} : {})}); break;
            case "comment-location": if (f.length >= 4) report.locations.push({ordinal: Number(f[0]), side: f[1], start: Number(f[2]), end: Number(f[3])}); break;
            case "comments-delivery-file": if (f.length >= 4) report.deliveryFiles.push({path: f[0], role: f[1], presence: f[2], revision: f[3]}); break;
        }
    }
    for (const location of report.locations) {
        const columns = report.rows.find(r => r.tag === "comment-columns" && Number(r.fields[0]) === location.ordinal && r.fields[1] === location.side);
        if (columns) {location.startColumn = Number(columns.fields[2]); location.endColumn = Number(columns.fields[3]);}
    }
    for (const doc of report.documents) if (counts.has(doc.path)) doc.count = counts.get(doc.path);
    for (const context of report.contexts) {
        const owner = owners.get(context.id);
        if (owner) {context.source = owner[0]; context.owner = owner[1];}
    }
    return report;
}
