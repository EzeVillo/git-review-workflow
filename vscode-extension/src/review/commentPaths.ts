export const hasCommentPaths = (output: string): boolean =>
    output.split(/\r?\n/).filter(line => line === "capability\tcomments-paths").length === 1;
export interface CommentPaths {paths: string[] | null}
/** Null paths explicitly request the legacy inventory; undefined is invalid. */
export function parseCommentPaths(output: string, guard: string): CommentPaths | undefined {
    const lines = output.replace(/\r\n/g, "\n").split("\n");
    if (lines[lines.length - 1] === "") lines.pop();
    const head = lines[0]?.split("\t");
    if (head?.length !== 4 || head[0] !== "comments-paths" || head[1] !== "1" ||
        !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(guard) || head[2] !== guard ||
        lines[lines.length - 1] !== "comments-paths\tcomplete") return undefined;
    if (head[3] === "legacy") return lines.length === 2 ? {paths: null} : undefined;
    if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(head[3]) || lines.length !== 4) return undefined;
    const paths: string[] = [];
    for (const [i, kind] of ["local", "shared"].entries()) {
        const prefix = `comments-path\t${kind}\t`;
        if (!lines[i + 1].startsWith(prefix)) return undefined;
        const raw = lines[i + 1].slice(prefix.length);
        if (!raw || /%(?!25|09|0A|0D|3E)/.test(raw)) return undefined;
        paths.push(decodeURIComponent(raw));
    }
    return {paths};
}
