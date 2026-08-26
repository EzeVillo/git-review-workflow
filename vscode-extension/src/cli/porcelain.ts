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

/**
 * El registro `finish` de `status --porcelain`
 * (contracts/finish-state.md). `state` es siempre `"conflict"`: es el único
 * estado de cierre observable desde dentro de una review activa — un cierre
 * completo ya sacó a `HEAD` de `review/*`, así que ese lo reporta `list`, no
 * `status`.
 */
export interface StatusFinishRecord {
    state: "conflict";
    /** `true` si el cierre en curso llevaba `--onto-source`. */
    onto: boolean;
}

export interface PorcelainResult {
    state: StateRecord;
    entries: EntryRecord[];
    /** Sólo si hay un cierre trabado en curso sobre esta review (FR-027). */
    finish?: StatusFinishRecord;
    /**
     * `true` sólo cuando la CLI emitió el registro `readonly` (`git review
     * compare` / `reviewreadonly=1`). Ausente en cualquier otra review: no se
     * inventa `false` (omit, never blank — mismo criterio que `base`/`finish`).
     */
    readonly?: true;
    /**
     * `true` sólo cuando la CLI emitió el registro `keys` (walk solo-keys,
     * `start`/`compare --keys`). Ausente en cualquier otra review.
     */
    keysOnly?: true;
    /**
     * `true` sólo cuando la CLI emitió el registro `draft` (011): el orden de
     * lectura es el borrador del revisor y no el walkthrough del autor. Sólo se
     * da en walk. De dónde sale el walkthrough **no se infiere** en ningún
     * cliente: llega por este registro o no se sabe.
     */
    draft?: true;
    /**
     * Ruta absoluta del borrador en vigor, tal como la reportó la CLI en el
     * campo del registro `draft` (012). Va aparte del booleano a propósito: la
     * presencia sigue siendo la presencia, y un campo faltante (una CLI vieja,
     * o un registro recortado) no puede apagar la marca. El cliente **abre**
     * esta ruta y nunca arma una.
     */
    draftPath?: string;
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
    /**
     * Inventario de archivos del **commit actual** en modo step (registros
     * `file` del contrato). Posición 1-based *dentro de ese commit*, no de la
     * secuencia de commits. Vacío (nunca ausente en el parseo) cuando no hay
     * líneas `file` — commit sin paths, o CLI que no las emite. En whole/walk
     * la CLI no emite `file` (en whole los paths ya van como `entry`).
     */
    files: EntryRecord[];
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
    /**
     * El cierre sin resolver de esta review, si tiene uno
     * (contracts/finish-state.md). A diferencia de `StatusFinishRecord`, acá
     * `state` puede ser `"pending"`: `list` ve el repositorio entero, no sólo
     * la rama en la que está parado el usuario, así que también reporta un
     * cierre completo cuyo `HEAD` ya se movió a `review-fixes/<x>` (o a la
     * rama del PR con `--onto-source`).
     */
    finish?: {
        state: "pending" | "conflict";
        onto: boolean;
    };
}

/**
 * El estado de una rama `review-fixes/*`: cuánto trabajo cuesta descartarla.
 *
 * `empty` no es una variante de "seguro": una rama de fixes intacta está parada
 * en la punta del PR y no contiene **nada** tuyo, que es distinto de estar ya
 * integrada. `unknown` tampoco se pliega en `unmerged` — sin base configurada
 * la pregunta no tiene respuesta, y contestar la peor de las dos pinta de
 * peligrosa una rama que puede estar vacía.
 */
export type FixesState = "empty" | "merged" | "unmerged" | "unknown";

/**
 * Un registro `fixes` de `git review list --porcelain`: una rama
 * `review-fixes/<x>` que dejó un `finish`
 * (001-contrato-porcelain/contracts/list-porcelain.md).
 */
export interface FixesRecord {
    /** Nombre de la rama, tal como lo reportó la CLI: `review-fixes/<x>`. */
    name: string;
    /** La rama en la que está parado HEAD: la única que `clean` nunca borra. */
    current: boolean;
    /** `review/<x>` todavía existe, así que la review sigue abierta. */
    session: boolean;
    state: FixesState;
}

function parseFixesState(field: string | undefined): FixesState {
    switch (field) {
    case "empty":
    case "merged":
    case "unmerged":
        return field;
    default:
        // Un valor que no entendemos se lee como "no se puede decir", nunca
        // como uno de los tres concretos: el badge de esta fila es lo único que
        // separa tirar una rama vacía de tirar trabajo sin pushear.
        return "unknown";
    }
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

/** Modos que emite el contrato; cualquier otro es salida corrupta, no "whole" inventado. */
function parseReviewMode(field: string | undefined): ReviewMode | undefined {
    if (field === "whole" || field === "step" || field === "walk") {
        return field;
    }
    return undefined;
}

/**
 * Tokeniza la salida de `git review status --porcelain` (registros
 * `state`/`entry`). El campo `mode` del registro `state` se lee **primero** y
 * decide la aridad esperada de las líneas siguientes — nunca al revés
 * (research.md Decisión 2, data-model.md). Etiquetas desconocidas y campos
 * extra al final: se ignoran (FR-003).
 */
export function parsePorcelain(stdout: string): PorcelainResult {
    // Strip CR so CRLF (wrappers / Windows redirections) does not poison fields.
    const lines = stdout.split(/\r?\n/).filter((line) => line.length > 0);
    if (lines.length === 0) {
        throw new Error("porcelain output has no state record");
    }

    let state: StateRecord | undefined;
    const entries: EntryRecord[] = [];
    const files: EntryRecord[] = [];
    // Se crean sólo si el registro llegó: un mapa vacío diría "la CLI reporta
    // asuntos y esta review no tiene ninguno", que es otra cosa (FR-004).
    let subjects: Map<number, string> | undefined;
    let authors: Map<number, string> | undefined;
    let base: string | undefined;
    let finish: StatusFinishRecord | undefined;
    let isReadonly: true | undefined;
    let isKeysOnly: true | undefined;
    let isDraft: true | undefined;
    let draftPath: string | undefined;

    for (const line of lines) {
        const fields = line.split("\t");
        const tag = fields[0];

        switch (tag) {
            case "state": {
                const mode = parseReviewMode(fields[4]);
                if (mode === undefined) {
                    throw new Error(
                        `porcelain state has invalid mode: ${fields[4] === undefined ? "(missing)" : JSON.stringify(fields[4])}`
                    );
                }
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
            // Inventario del commit actual en step (no de la secuencia). El
            // path se trata como en whole/walk: PathRef, no string suelto.
            case "file": {
                if (!state) {
                    throw new Error("file record before state record");
                }
                const position = toInt(fields[1]);
                const rawPath = fields[2];
                if (rawPath === undefined || rawPath.length === 0) {
                    break;
                }
                files.push({position, id: toPathRef(rawPath)});
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
            // `state` es siempre `"conflict"` en este verbo (contracts/finish-
            // state.md): un cierre completo ya movió `HEAD` fuera de `review/*`,
            // así que `status` nunca llega a verlo.
            case "finish": {
                if (fields[1] === "conflict") {
                    finish = {state: "conflict", onto: toBool(fields[2])};
                }
                break;
            }
            // Compare read-only: tag alone, no fields. Presence = true.
            case "readonly": {
                isReadonly = true;
                break;
            }
            // Walk keys-only submode: tag alone, no fields. Presence = true.
            case "keys": {
                isKeysOnly = true;
                break;
            }
            // Reviewer's own draft walkthrough. La presencia del registro es la
            // marca; el campo (012) es la ruta absoluta, y se lee aparte para
            // que un registro sin él siga marcando el borrador igual.
            case "draft": {
                isDraft = true;
                if (fields[1] !== undefined && fields[1].length > 0) {
                    draftPath = fields[1];
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

    const result: PorcelainResult = {state, entries, files};
    if (subjects) {
        result.subjects = subjects;
    }
    if (authors) {
        result.authors = authors;
    }
    if (base !== undefined) {
        result.base = base;
    }
    if (finish !== undefined) {
        result.finish = finish;
    }
    if (isReadonly) {
        result.readonly = true;
    }
    if (isKeysOnly) {
        result.keysOnly = true;
    }
    if (isDraft) {
        result.draft = true;
    }
    if (draftPath !== undefined) {
        result.draftPath = draftPath;
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
/**
 * Los registros `fixes` de la misma salida, en una función aparte y no como un
 * segundo valor de `parseListPorcelain`: son ramas de *ediciones*, no reviews
 * —no hay nada que retomar ni que abortar en ellas— y todo consumidor del
 * inventario que ya existía sigue pidiendo exactamente lo que pedía.
 *
 * Se emparejan por etiqueta y no por posición, como el resto del contrato: que
 * la CLI las emita al final es una garantía sobre la salida, no algo de lo que
 * este parser dependa.
 */
export function parseListFixes(stdout: string): FixesRecord[] {
    const fixes: FixesRecord[] = [];
    for (const line of stdout.split(/\r?\n/)) {
        if (line.length === 0) {
            continue;
        }
        const fields = line.split("\t");
        if (fields[0] !== "fixes") {
            continue;
        }
        const name = fields[1];
        if (name === undefined || name.length === 0) {
            continue;
        }
        fixes.push({
            name,
            current: toBool(fields[2]),
            session: toBool(fields[3]),
            state: parseFixesState(fields[4]),
        });
    }
    return fixes;
}

export function parseListPorcelain(stdout: string): BranchRecord[] {
    const branches: BranchRecord[] = [];
    // Por nombre de rama, no por posición de línea: el contrato pone `finish`
    // justo después de su `branch`, pero `parsePorcelain` ya establece que un
    // consumidor empareja por etiqueta, nunca por orden de aparición (001).
    const finishByBranch = new Map<string, { state: "pending" | "conflict"; onto: boolean }>();

    for (const line of stdout.split(/\r?\n/)) {
        if (line.length === 0) {
            continue;
        }
        const fields = line.split("\t");
        if (fields[0] === "finish") {
            const branchName = fields[1];
            const state = fields[2];
            if (branchName !== undefined && (state === "pending" || state === "conflict")) {
                finishByBranch.set(branchName, {state, onto: toBool(fields[3])});
            }
            continue;
        }
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
            // Ausente o corrupto: sin mode (como orphan de metadata), no
            // inventar "whole" — un valor basura abriría paths basura.
            const mode = parseReviewMode(fields[5] ?? "whole");
            if (mode !== undefined) {
                record.mode = mode;
            }
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

    for (const branch of branches) {
        const finish = finishByBranch.get(branch.name);
        if (finish) {
            branch.finish = finish;
        }
    }

    return branches;
}
