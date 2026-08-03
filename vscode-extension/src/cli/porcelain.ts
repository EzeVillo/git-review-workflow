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
    /**
     * Sólo en modo walk. `false` cuando el path cambia en el rango de la
     * review pero no tiene entrada propia en el walkthrough — el orden de
     * lectura lo agrega al final en vez de omitirlo.
     */
    annotated?: boolean;
    /** Sólo en modo step. */
    banked?: boolean;
}

export interface PorcelainResult {
    state: StateRecord;
    entries: EntryRecord[];
}

/**
 * Un registro `branch` de `git review list --porcelain`
 * (001-contrato-porcelain/contracts/list-porcelain.md). Ojo con la diferencia
 * respecto de `StateRecord`: acá `total` es el **registrado**, no el derivado
 * ahora — un inventario no re-deriva la secuencia de cada rama del repositorio.
 */
export interface BranchRecord {
    /** Nombre de la rama: `review/<x>` o `review-saved/<x>`. */
    name: string;
    saved: boolean;
    current: boolean;
    /** Sin `reviewsource`: metadata ausente, y entonces sin `mode`. */
    orphan: boolean;
    /** Ausente sólo si `orphan`. */
    mode?: ReviewMode;
    /** Presentes sólo en step/walk y sólo si la CLI emitió las dos. */
    position?: number;
    total?: number;
}

function toBool(field: string | undefined): boolean {
    return field === "1";
}

function toInt(field: string | undefined): number {
    return field === undefined ? 0 : parseInt(field, 10);
}

/** Como `toInt`, pero un campo ausente o no numérico es ausencia, no un `0`. */
function toOptionalInt(field: string | undefined): number | undefined {
    if (field === undefined || field.length === 0) {
        return undefined;
    }
    const value = parseInt(field, 10);
    return Number.isNaN(value) ? undefined : value;
}

/**
 * Tokeniza la salida de `git review status --porcelain` (registros
 * `state`/`entry`). El campo `mode` del registro `state` se lee **primero** y
 * decide la aridad esperada de las líneas siguientes — nunca al revés
 * (research.md Decisión 2, data-model.md). Etiquetas desconocidas y campos
 * extra al final: se ignoran (FR-003).
 */
export function parsePorcelain(stdout: string): PorcelainResult {
    const lines = stdout.split("\n").filter((line) => line.length > 0);
    if (lines.length === 0) {
        throw new Error("porcelain output has no state record");
    }

    let state: StateRecord | undefined;
    const entries: EntryRecord[] = [];

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
                    entry.annotated = toBool(fields[4]);
                } else if (state.mode === "step") {
                    entry.banked = toBool(fields[3]);
                }
                entries.push(entry);
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

    return {state, entries};
}

/**
 * Nombre *source* de una review: el de la rama sin su prefijo. Es el argumento
 * que espera `git review continue` (`feature/checkout`, no
 * `review-saved/feature/checkout`), y el único valor del inventario que vuelve a
 * la CLI — ver contracts/cli-invocation.md § `list --porcelain`. Sin prefijo
 * conocido devuelve el nombre tal cual: inventar un recorte sería peor que
 * pasar algo que la CLI va a rechazar con su propio mensaje.
 */
export function sourceOf(branch: BranchRecord): string {
    for (const prefix of ["review-saved/", "review/"]) {
        if (branch.name.startsWith(prefix)) {
            return branch.name.slice(prefix.length);
        }
    }
    return branch.name;
}

/**
 * Tokeniza `git review list --porcelain` (registros `branch`). Mismo formato
 * porcelain v1 y mismas reglas que `parsePorcelain`: etiquetas desconocidas y
 * campos extra al final se ignoran (FR-003). A diferencia de `status`, la
 * ausencia de registros es un resultado válido — un repositorio sin reviews —
 * y no un error de formato.
 */
export function parseListPorcelain(stdout: string): BranchRecord[] {
    const branches: BranchRecord[] = [];

    for (const line of stdout.split("\n")) {
        if (line.length === 0) {
            continue;
        }
        const fields = line.split("\t");
        if (fields[0] !== "branch") {
            continue;
        }
        const record: BranchRecord = {
            name: fields[1] ?? "",
            saved: toBool(fields[2]),
            current: toBool(fields[3]),
            orphan: toBool(fields[4]),
        };
        if (!record.orphan) {
            record.mode = (fields[5] ?? "whole") as ReviewMode;
            // Omitidos, nunca a medias: el contrato los emite de a pares o no
            // los emite, así que un solo campo presente es salida que no
            // entendemos y se descarta entera (nunca se rellena con un 0, que
            // sería un cursor inventado).
            const position = toOptionalInt(fields[6]);
            const total = toOptionalInt(fields[7]);
            if (position !== undefined && total !== undefined) {
                record.position = position;
                record.total = total;
            }
        }
        branches.push(record);
    }

    return branches;
}
