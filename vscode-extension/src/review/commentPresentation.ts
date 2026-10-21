import {CommentEntry, CommentsReport} from "../cli/commentsPorcelain";
import {COMMENTS_COPY as copy} from "./userCopy";

/** Decode exactly once: a literal %09 is encoded as %2509 on the wire. */
export function decodeComment(value: string): string {
    return value.replace(/%(25|09|0D|0A|3E)/g, (_, code: string) => ({"25": "%", "09": "\t", "0D": "\r", "0A": "\n", "3E": ">"}[code]!));
}
export interface CommentPresentation {ordinal: number; label: string; body: string; location: string; version: string; preview: string; warning: string; canOpenDiff: boolean}
export function presentComment(report: CommentsReport, entry: CommentEntry): CommentPresentation {
    const rows = (tag: string) => report.rows.filter(r => r.tag === tag && r.fields[0] === String(entry.ordinal)).map(r => r.fields);
    const lines = rows("comment-body").map(f => decodeComment(f[1]));
    let first = 0, last = lines.length;
    while (first < last && !lines[first].trim()) first++;
    while (last > first && !lines[last - 1].trim()) last--;
    const body = lines.slice(first, last).join("\n");
    const scope = rows("comment-scope")[0];
    const line = rows("comment-location")[0];
    const columns = rows("comment-columns")[0];
    const side = scope?.[2] ?? line?.[1];
    const paths = rows("comment-path");
    const file = paths.find(f => f[1] === side)?.[2];
    let location: string = copy.locationUnavailable;
    if (scope?.[1] === "general") location = copy.general;
    else if (file) location = decodeComment(file) + (line ? ":" + line[2] + (columns ? ":" + columns[2] : "") + "–" + line[3] + (columns ? ":" + columns[3] : "") : "") + " · " + (side === "base" ? copy.baseSide : copy.headSide);
    const version = rows("comment-version")[0];
    const title = entry.title === (file ? decodeComment(file) : location) ? location : entry.title + " · " + location;
    const preview = Array.from(body.replace(/\s+/g, " ").trim());
    return {canOpenDiff: scope?.[1] !== "general" && !!file, ordinal: entry.ordinal, label: entry.number + ". " + title, body: body || copy.noBody, location,
        version: (version ? copy.originalChanges + " · " + version[1].slice(0, 8) + " → " + version[2].slice(0, 8) : ""),
        warning: rows("comment-unversioned").length ? copy.originalUnversioned : "",
        preview: preview.length > 160 ? preview.slice(0, 159).join("") + "…" : preview.join("")};
}
