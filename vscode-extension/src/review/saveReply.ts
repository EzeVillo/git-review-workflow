/** Optional complete no-review state returned only by save --porcelain. */
export const hasSaveState = (output: string): boolean =>
    output.split(/\r?\n/).filter(line => line === "capability\tsave-state").length === 1;
export interface SaveReply {list: string; config: string}
export function parseSaveReply(output: string): SaveReply | undefined {
    const lines = output.replace(/\r\n/g, "\n").split("\n");
    if (lines[lines.length - 1] === "") lines.pop();
    if (lines.shift() !== "save-state\t1" || lines.shift() !== "status\t2" ||
        lines.pop() !== "save-state\tcomplete") return undefined;
    const list: string[] = [], config: string[] = [];
    for (const line of lines) {
        if (line.startsWith("list\t") && !config.length) list.push(line.slice(5));
        else if (line.startsWith("config\t")) config.push(line.slice(7));
        else return undefined;
    }
    if (!list.some(line => /^branch\t[^\t]+\t1\t/.test(line)) ||
        config.filter(line => line.startsWith("config\tremote\t")).length !== 1) return undefined;
    return {list: list.join("\n") + "\n", config: config.join("\n") + "\n"};
}
