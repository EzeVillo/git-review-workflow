import {PathRef, toPathRef} from "./unquote";

export type ReviewMode = "whole" | "step" | "walk";
export type WalkthroughStatus = "none" | "applied" | "degraded";

export interface StateRecord {
    branch: string;
    source: string;
    tip: string;
    mode: ReviewMode;
    walkthrough: WalkthroughStatus;
    /** Sólo en step/walk. */
    position?: number;
    /** Sólo en step/walk; derivado ahora. */
    total?: number;
    /** Sólo en step/walk; registrado al iniciar. */
    recorded?: number;
    /** SHA corto (step) o PathRef (walk). Sólo en step/walk. */
    current?: string | PathRef;
    /** Sólo en walk. */
    essential?: boolean;
}

export interface EntryRecord {
    position: number;
    /** SHA corto (step) o PathRef (walk). */
    id: string | PathRef;
    /** Sólo en modo walk. */
    essential?: boolean;
    /** Sólo en modo step. */
    banked?: boolean;
}

export interface UncoveredRecord {
    id: PathRef;
}

export interface PorcelainResult {
    state: StateRecord;
    entries: EntryRecord[];
    uncovered: UncoveredRecord[];
}

function toBool(field: string | undefined): boolean {
    return field === "1";
}

function toInt(field: string | undefined): number {
    return field === undefined ? 0 : parseInt(field, 10);
}

/**
 * Tokeniza la salida de `git review status --porcelain` (registros
 * `state`/`entry`/`uncovered`). El campo `mode` del registro `state` se lee
 * **primero** y decide la aridad esperada de las líneas siguientes — nunca al
 * revés (research.md Decisión 2, data-model.md). Etiquetas desconocidas y
 * campos extra al final: se ignoran (FR-003).
 */
export function parsePorcelain(stdout: string): PorcelainResult {
    const lines = stdout.split("\n").filter((line) => line.length > 0);
    if (lines.length === 0) {
        throw new Error("porcelain output has no state record");
    }

    let state: StateRecord | undefined;
    const entries: EntryRecord[] = [];
    const uncovered: UncoveredRecord[] = [];

    for (const line of lines) {
        const fields = line.split("\t");
        const tag = fields[0];

        switch (tag) {
            case "state": {
                const mode = fields[4] as ReviewMode;
                const walkthrough = fields[5] as WalkthroughStatus;
                const record: StateRecord = {
                    branch: fields[1],
                    source: fields[2],
                    tip: fields[3],
                    mode,
                    walkthrough,
                };
                if (mode === "step" || mode === "walk") {
                    record.position = toInt(fields[6]);
                    record.total = toInt(fields[7]);
                    record.recorded = toInt(fields[8]);
                    record.current = mode === "walk" ? toPathRef(fields[9]) : fields[9];
                }
                if (mode === "walk") {
                    record.essential = toBool(fields[10]);
                }
                state = record;
                break;
            }
            case "entry": {
                if (!state) {
                    throw new Error("entry record before state record");
                }
                const position = toInt(fields[1]);
                const rawId = fields[2];
                const entry: EntryRecord = {
                    position,
                    id: state.mode === "walk" ? toPathRef(rawId) : rawId,
                };
                if (state.mode === "walk") {
                    entry.essential = toBool(fields[3]);
                } else if (state.mode === "step") {
                    entry.banked = toBool(fields[3]);
                }
                entries.push(entry);
                break;
            }
            case "uncovered": {
                uncovered.push({id: toPathRef(fields[1])});
                break;
            }
            default:
                // Etiqueta desconocida: se ignora (FR-003).
                break;
        }
    }

    if (!state) {
        throw new Error("porcelain output has no state record");
    }

    return {state, entries, uncovered};
}
