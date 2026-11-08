import {parsePorcelain} from "../cli/porcelain";
import {parseStateGuard} from "./staleGuard";

const lines = (output: string): string[] => output.split("\n").map(line => line.replace(/\r$/, ""));
export const hasNavigationState = (output: string): boolean =>
    lines(output).filter(line => line === "capability\tnavigation-state").length === 1;

export function isNavigationReply(output: string): boolean {
    const rows = lines(output);
    if (!hasNavigationState(output) || !parseStateGuard(output) ||
        rows.filter(line => line.startsWith("state\t")).length !== 1 ||
        rows.filter(line => line.startsWith("navigation\t")).length !== 1 ||
        !rows.some(line => line === "navigation\tmoved" || line === "navigation\tunchanged")) return false;
    try {
        const parsed = parsePorcelain(output);
        return parsed.state.branch.startsWith("review/") && !parsed.finish &&
            (parsed.state.mode === "walk" || parsed.state.mode === "step");
    } catch { return false; }
}

export function navigationNotice(output: string): string {
    const notices = lines(output).filter(line => line.startsWith("notice\t"));
    return notices.length === 1 ? notices[0].slice(7) : "";
}

/** Undefined is unknown/invalid; empty is an explicit absent explanation. */
export function parseInlineWhy(output: string): string | undefined {
    const rows = lines(output).map(line => line.split("\t"));
    const headers = rows.filter(row => row[0] === "why");
    if (headers.length !== 1 || headers[0].length !== 3 || !/^(0|[1-9][0-9]*)$/.test(headers[0][2])) return undefined;
    const header = headers[0], count = Number(header[2]);
    const body = rows.filter(row => row[0] === "why-line");
    if (header[1] === "absent") return count === 0 && body.length === 0 ? "" : undefined;
    if (header[1] !== "present" || count === 0 || count !== body.length) return undefined;
    let result = "";
    for (let index = 0; index < body.length; index++) {
        const row = body[index];
        if (row.length !== 3 || row[1] !== String(index+1)) return undefined;
        for (let at = 0; at < row[2].length; at++) {
            const ch = row[2][at];
            if (ch !== "\\") result += ch;
            else {
                if (++at === row[2].length) return undefined;
                const escaped = row[2][at];
                const value = escaped === "\\" ? "\\" : escaped === "t" ? "\t" : escaped === "r" ? "\r" : undefined;
                if (value === undefined) return undefined;
                result += value;
            }
        }
        result += "\n";
    }
    return result;
}
