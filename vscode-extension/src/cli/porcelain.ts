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
    /**
     * Asunto de cada commit de la secuencia, por `position` — sólo en modo step
     * (contracts/status-porcelain.md).
     *
     * Mapas y no campos de `EntryRecord` por dos razones: emparejar por
     * `position` es lo que el contrato exige (nunca por orden de aparición), y
     * dejarlos afuera conserva intacta la forma de `EntryRecord` que los tests
     * existentes ya afirman.
     *
     * Opcionales porque **la ausencia del mapa entero significa "la CLI no
     * provee este dato"**, y eso es distinto de un mapa con una entrada vacía,
     * que significa "el dato existe y está vacío" (FR-004). Misma disciplina que
     * `toOptionalInt`: un campo ausente no se convierte en un valor inventado.
     */
    subjects?: Map<number, string>;
    /** Autor de cada commit, por `position`. Sólo en step; ver `subjects`. */
    authors?: Map<number, string>;
    /** Base del rango. Sólo en modo whole, y sólo si hay una registrada. */
    base?: string;
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

/**
 * El campo de **texto libre** de un registro: todo lo que sigue al `skip`-ésimo
 * tab de `line`, hasta el fin de línea.
 *
 * No es `line.split("\t")[skip]`, y la diferencia es la razón por la que estos
 * registros existen. El asunto de un commit y el nombre de un autor los escribe
 * una persona, no git, así que **pueden contener un tab literal** — a diferencia
 * de un path, que git cita incondicionalmente (research.md Decisión 1, medido).
 * Con `split` un asunto con un tab adentro se partiría en varios elementos y el
 * consumidor mostraría sólo el primero, en silencio. Por eso el contrato manda
 * el texto libre como último campo del registro: acá no hay nada después que
 * desplazar, y leer "el resto de la línea" es exacto.
 *
 * `undefined` cuando la línea no llega a tener `skip` tabs: es un registro que
 * no entendemos, no un campo vacío. Un campo legítimamente vacío (un commit sin
 * asunto) sí devuelve `""` — la distinción que pide FR-004.
 */
function restAfterTab(line: string, skip: number): string | undefined {
    let index = -1;
    for (let i = 0; i < skip; i++) {
        index = line.indexOf("\t", index + 1);
        if (index === -1) {
            return undefined;
        }
    }
    return line.slice(index + 1);
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
    // Se crean sólo si el registro llegó: un mapa vacío diría "la CLI reporta
    // asuntos y esta review no tiene ninguno", que es otra cosa (FR-004).
    let subjects: Map<number, string> | undefined;
    let authors: Map<number, string> | undefined;
    let base: string | undefined;

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
                // El id es un SHA sólo en step; en los otros dos modos es un
                // path — incluido whole, que no tenía registros entry antes de
                // esta feature (research.md Decisión 4).
                const entry: EntryRecord = {
                    position,
                    id: state.mode === "step" ? rawId : toPathRef(rawId),
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
            // El texto libre se lee como "el resto de la línea desde el segundo
            // tab", nunca como `fields[2]`: un asunto o un nombre de autor
            // pueden contener un tab literal y `split` los partiría en varios
            // elementos, dejando ver sólo el primero (research.md Decisión 1).
            case "subject":
            case "author": {
                const position = toOptionalInt(fields[1]);
                const text = restAfterTab(line, 2);
                if (position === undefined || text === undefined) {
                    // Registro que no entendemos: se descarta entero, sin
                    // inventarle una posición ni un texto.
                    break;
                }
                if (tag === "subject") {
                    (subjects ??= new Map()).set(position, text);
                } else {
                    (authors ??= new Map()).set(position, text);
                }
                break;
            }
            // Registro único y sin posición: la base es de la review, no de una
            // entrada. Un solo tab que saltar, y el texto libre es el resto.
            case "base": {
                const text = restAfterTab(line, 1);
                if (text !== undefined) {
                    base = text;
                }
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

    const result: PorcelainResult = {state, entries};
    if (subjects) {
        result.subjects = subjects;
    }
    if (authors) {
        result.authors = authors;
    }
    if (base !== undefined) {
        result.base = base;
    }
    return result;
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
