import {parsePorcelain} from "../cli/porcelain";
import {parseStateGuard} from "./staleGuard";

const rows = (output: string): string[] => {
    const result = output.replace(/\r\n/g, "\n").split("\n");
    if (result[result.length - 1] === "") result.pop();
    return result;
};

/** Capability and opaque inventory identity are one feature; either alone is unknown. */
export function parseContinueGuard(output: string): string | undefined {
    const lines = rows(output);
    if (lines.filter(line => line === "capability\tcontinue-state").length !== 1) return undefined;
    const guards = lines.filter(line => line.startsWith("continue-guard\t"));
    return guards.length === 1 && /^continue-guard\t(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(guards[0])
        ? guards[0].slice(15) : undefined;
}

export function isContinueReply(output: string): boolean {
    const lines = rows(output);
    if (lines[0] !== "continue-state\t1" || lines[lines.length - 1] !== "continue-state\tcomplete" ||
        lines.filter(line => line.startsWith("continue-state\t")).length !== 2 ||
        lines.filter(line => line.startsWith("state\t")).length !== 1 || !parseStateGuard(output)) return false;
    try {
        const parsed = parsePorcelain(output);
        return parsed.state.branch.startsWith("review/") && !parsed.finish &&
            ["whole", "step", "walk"].includes(parsed.state.mode);
    } catch { return false; }
}
