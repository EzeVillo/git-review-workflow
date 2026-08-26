/**
 * Tokeniza `git review config --porcelain` (contracts/config-porcelain.md):
 * mismo formato porcelain v1 que `porcelain.ts`, mismo tokenizador línea por
 * línea (split por tab, primer campo = etiqueta), y mismas reglas — etiquetas
 * desconocidas y campos extra al final de un registro conocido se ignoran
 * (FR-003). Existe como módulo aparte porque el registro que reporta (config
 * efectiva + ramas candidatas) no tiene nada que ver con el de una review
 * activa: es la respuesta a "cómo se armaría", no a "cómo está armada"
 * (data-model.md § EffectiveConfig).
 *
 * 008: también parsea `offer` (formas de lectura viables para un tip/rango).
 */

export interface EffectiveConfig {
    /** Ausente = sin configurar, un estado normal (un review completo fallaría pidiéndola). */
    base?: string;
    /** Siempre presente: `origin` cuando no hay nada configurado, ya resuelto por la CLI. */
    remote: string;
}

export interface CandidateBranch {
    /** Sin el prefijo de namespace: el valor que vuelve a la CLI como argumento. */
    name: string;
    origin: "remote" | "local";
    current: boolean;
}

/**
 * Ramas para el picker de "branch to review" del asistente de inicio. El
 * porcelain puede traer una fila `remote` y otra `local` para el mismo nombre
 * (contracts/config-porcelain.md "Duplicados esperados": es el dato que hace
 * significativa la elección de origen) — pero ese origen se pregunta después,
 * como paso propio del asistente (`pickSource`), y el paso de rama sólo usa
 * `name`. Sin colapsar, las dos filas salen idénticas en la lista (mismo
 * nombre, sin nada que las distinga) y parecen una rama duplicada. Colapsa a
 * una entrada por nombre, prefiriendo la fila marcada `current` (paridad con
 * `branchPickerItems` de JetBrains).
 */
export function branchPickerItems(candidates: readonly CandidateBranch[]): CandidateBranch[] {
    const byName = new Map<string, CandidateBranch>();
    for (const candidate of candidates) {
        const prev = byName.get(candidate.name);
        if (prev === undefined || (candidate.current && !prev.current)) {
            byName.set(candidate.name, candidate);
        }
    }
    return [...byName.values()];
}

/** Remoto del repositorio elegible para `git review config remote` (porcelain `remote-candidate`). */
export interface CandidateRemote {
    name: string;
    /** Coincide con el remoto efectivo del registro `config`. */
    current: boolean;
}

/** Eje del marker `--delta`: tip de origin/<rama> vs refs/heads/<rama>. */
export type DeltaOrigin = "remote" | "local";

export interface DeltaRecord {
    name: string;
    tip: string;
    origin: DeltaOrigin;
}

/**
 * Forma de lectura viable reportada por la CLI (008).
 *
 * 011: `draft` / `draft-resume` / `draft-update` no son formas de lectura sino
 * el camino para conseguir una — el revisor se escribe el orden que el PR no
 * trae. Viajan por el mismo registro porque se eligen en el mismo paso del
 * asistente, y son mutuamente excluyentes entre sí
 * (contracts/config-porcelain-draft.md).
 *
 * Cuál de las tres llega lo decide la CLI y no se deriva acá: `draft-update`
 * dice que el borrador quedó desfasado del rango de hoy, que es una pregunta
 * que sólo contesta quien tiene los dos tips. El campo `state` del registro
 * `draft` NO sirve para eso — contesta otra ("¿ya se leyó este orden?"), así
 * que una rama que avanzó después de su review sigue diciendo `reviewed`.
 */
export type OfferId = "walk" | "keys" | "draft" | "draft-resume" | "draft-update" | "step" | "whole";
export type OfferRank = "recommended" | "available";

export interface ReadingOffer {
    id: OfferId;
    rank: OfferRank;
}

/**
 * Un borrador de walkthrough suelto: existe en el namespace activo del gitdir,
 * o sea que el revisor lo empezó y no pausó su review (registro `draft` de
 * `config --porcelain`, contracts/config-porcelain-drafts.md).
 *
 * Nada de esto se deriva acá: cada campo viene tal cual de la CLI. En
 * particular `path`, que el cliente **abre y nunca arma** — derivar el gitdir
 * para reconstruirla es justo lo que 012 retira.
 */
export interface DraftRecord {
    /** La rama a la que pertenece, verbatim (puede traer `/`). */
    src: string;
    /** Ruta absoluta, ya resuelta por la CLI. */
    path: string;
    /** Entradas con posición **y** why resueltos. */
    annotated: number;
    /** Entradas que el archivo declara (numeradas y `## ?.`). */
    total: number;
    /**
     * Con qué origen y rango se generó, leídos del bloque de instrucciones del
     * propio archivo. `unknown` cuando ese bloque se borró a mano, que es legal:
     * entonces no se ofrece *Validate and start*, porque invocar con los flags
     * por defecto fallaría siempre por deriva.
     */
    source: DraftSource;
    range: DraftRange;
    /** Si su review ya terminó. Ver {@link DraftState}. */
    state: DraftState;
}

export type DraftSource = "remote" | "local" | "offline" | "unknown";
export type DraftRange = "full" | "delta" | "unknown";

/**
 * Si la review que este borrador alimentaba ya terminó (`reviewed`) o si
 * todavía tiene una review por delante (`fresh`). Lo decide la CLI comparando
 * el tip del propio borrador contra el marcador de la última review completa
 * de esa rama; acá no se deriva nada.
 *
 * El archivo sobrevive a la review en los dos casos —`clean` no toca prosa—,
 * así que esto no es "existe o no": es dónde se dibuja y qué se ofrece.
 */
export type DraftState = "fresh" | "reviewed";

/** Cuál de las dos guías de autoría es (registro `guide` de `config --porcelain`). */
export type GuideKind = "team" | "own";

/**
 * En qué estado está una guía. Los tres los decide la CLI y ninguno se infiere
 * acá: `empty` no es lo mismo que `absent` aunque las dos signifiquen "no hay
 * convenciones aplicándose" — con el archivo ahí lo que se ofrece es abrirlo,
 * no crearlo, y descartarlo es posible donde descartar uno que no existe no.
 */
export type GuideState = "in-force" | "empty" | "absent";

/**
 * Una guía de autoría: prosa sobre el CONTENIDO del walkthrough (qué entradas
 * merecen `> key`, cómo escribir un porqué, qué va en el heads-up).
 *
 * La extensión no lee un byte de su contenido — la abre y nada más, igual que
 * con el borrador. Y `path` viene tal cual de la CLI: **se abre, nunca se arma**.
 */
export interface GuideRecord {
    kind: GuideKind;
    /** Ruta absoluta, ya resuelta por la CLI. Existe en disco sólo si `state !== "absent"`. */
    path: string;
    state: GuideState;
}

/**
 * En qué estado está el walkthrough del autor respecto de la rama que tiene
 * puesta. Los cuatro los decide la CLI y ninguno se infiere acá — en particular
 * `unknown`, que NO es `stale`: sin el bloque de instrucciones (borrarlo a mano
 * es legal) la pregunta no tiene respuesta, y contestar la peor de las dos
 * mandaría a rehacer un orden de lectura que puede estar perfecto.
 *
 * `superseded` tampoco es `stale`: el archivo es el walkthrough de un PR que ya
 * se mergeó a la base y viajó con el merge, así que no quedó atrás — es de otro
 * rango. Lo que se ofrece ahí es empezar de cero, no reconciliar.
 */
export type WalkthroughState = "in-sync" | "stale" | "superseded" | "unknown" | "absent";

/**
 * El walkthrough committeado de la rama en la que estás parado, y si sigue
 * describiendo lo que el PR cambia hoy.
 *
 * Existe porque un walkthrough se escribe cuando el PR está terminado y después
 * el PR sigue moviéndose: vuelven los comentarios, cambian tres archivos, y el
 * momento en que eso pasa es exactamente aquel en el que nadie está pensando en
 * el walkthrough. `stale` es un "conviene mirar", nunca un veredicto — el
 * veredicto es de `build`, que es lo que corre el control de la fila.
 *
 * `path` viene tal cual de la CLI, como el del borrador y el de las guías: **se
 * abre, nunca se arma**.
 */
export interface WalkthroughRecord {
    /** Ruta absoluta de `.review/walkthrough.md`, exista o no el archivo. */
    path: string;
    state: WalkthroughState;
    /** Entradas con posición **y** why resueltos, más el heads-up. */
    annotated: number;
    /** Todo lo que `build` exige completar: una unidad por entrada más el heads-up. */
    total: number;
    /**
     * La rama que este walkthrough anota — la de `HEAD`, que es el rango que
     * `init` y `build` resuelven. Es **cómo se llama la fila** en el panel.
     * Ausente con `HEAD` detached, que es el único caso en que la CLI omite el
     * campo: ahí el archivo y los dos verbos siguen andando y lo único sin
     * respuesta es el nombre.
     */
    branch?: string;
}

export interface ConfigPorcelainResult {
    config: EffectiveConfig;
    /** En el orden de `git for-each-ref` (lexicográfico); duplicados (misma rama, dos orígenes) esperados, nunca fusionados. */
    candidates: CandidateBranch[];
    /**
     * Remotos del repositorio (`remote-candidate`), en el orden de `git remote`.
     * Vacío cuando no hay remotes; ausente del resultado no — siempre array.
     */
    remotes: CandidateRemote[];
    /**
     * Sólo cuando la invocación nombró una rama Y hay al menos un tip reviewed
     * previo (FR-015). Cero, una o dos filas — remote y local son ejes disjuntos.
     */
    deltas?: DeltaRecord[];
    /**
     * Formas de lectura viables para el tip/rango del contexto (flags de
     * origen/rango). Ausente cuando la CLI no emitió ninguna (pre-008 o tip
     * no resoluble en soft-skip).
     */
    offers?: ReadingOffer[];
    /**
     * Borradores sueltos del working tree, en el orden estable de la CLI. Se
     * emiten con y sin argumento de rama: un borrador es un hecho del working
     * tree, no de la rama consultada. Siempre array; vacío cuando no hay
     * ninguno, que es también lo que reporta una CLI que no conoce el registro.
     */
    drafts: DraftRecord[];
    /**
     * Las dos guías de autoría, SIEMPRE las dos y en el orden de la CLI (team,
     * own), exista o no cada archivo. La ausencia se reporta y no se implica con
     * el silencio: sin la fila, el panel no podría ofrecer crear la que falta sin
     * rearmar su path, que es justo lo que la regla del path reportado impide.
     *
     * Array vacío cuando la CLI no conoce el registro (una versión anterior), que
     * es la misma degradación que `drafts`.
     */
    guides: GuideRecord[];
    /**
     * El walkthrough del autor para la rama que está puesta. Presente o ausente,
     * la CLI emite la fila igual —misma regla que las guías, y por el mismo
     * motivo—, así que `undefined` acá significa una sola cosa: una CLI anterior
     * al registro. El panel dibuja el bloque sólo cuando hay fila.
     */
    walkthrough?: WalkthroughRecord;
}

function parseGuideKind(raw: string | undefined): GuideKind | undefined {
    return raw === "team" || raw === "own" ? raw : undefined;
}

function parseGuideState(raw: string | undefined): GuideState | undefined {
    return raw === "in-force" || raw === "empty" || raw === "absent" ? raw : undefined;
}

/**
 * Un registro `guide` desde sus campos, o `undefined` si está malformado —
 * ignorarlo entero, como cualquier registro: media fila de guía ofrecería crear
 * una que ya está, o abrir una que no.
 *
 * Exportada porque el registro llega por DOS verbos: `config --porcelain` fuera
 * de una review y `status --porcelain` adentro. Un parser por tokenizador sería
 * la misma regla escrita dos veces, y la segunda se enteraría tarde de cualquier
 * campo nuevo.
 */
export function parseGuideRecord(fields: readonly (string | undefined)[]): GuideRecord | undefined {
    const kind = parseGuideKind(fields[1]);
    const path = fields[2];
    const state = parseGuideState(fields[3]);
    if (kind === undefined || path === undefined || path.length === 0 || state === undefined) {
        return undefined;
    }
    return {kind, path, state};
}

function parseWalkthroughState(raw: string | undefined): WalkthroughState | undefined {
    return raw === "in-sync" ||
        raw === "stale" ||
        raw === "superseded" ||
        raw === "unknown" ||
        raw === "absent"
        ? raw
        : undefined;
}

/**
 * Un registro `walkthrough` desde sus campos, o `undefined` si está malformado.
 *
 * El par annotated/total cae a 0/0 cuando no es un número, en vez de tirar la
 * fila entera: el estado es lo que decide qué ofrece el bloque, y perderlo por
 * un contador ilegible dejaría al autor sin la única superficie que le dice que
 * su orden de lectura quedó atrás. Un estado que no se reconoce sí tira la fila
 * — dibujar un badge inventado es peor que no dibujar el bloque.
 */
function parseWalkthroughRecord(
    fields: readonly (string | undefined)[],
): WalkthroughRecord | undefined {
    const state = parseWalkthroughState(fields[1]);
    const path = fields[2];
    if (state === undefined || path === undefined || path.length === 0) {
        return undefined;
    }
    const branch = fields[5];
    return {
        path,
        state,
        annotated: toCount(fields[3]),
        total: toCount(fields[4]),
        ...(branch !== undefined && branch.length > 0 ? {branch} : {}),
    };
}

function toCount(field: string | undefined): number {
    if (field === undefined || !/^\d+$/.test(field)) {
        return 0;
    }
    return Number(field);
}

function toBool(field: string | undefined): boolean {
    return field === "1";
}

function parseOfferId(raw: string | undefined): OfferId | undefined {
    if (
        raw === "walk" ||
        raw === "keys" ||
        raw === "draft" ||
        raw === "draft-resume" ||
        raw === "draft-update" ||
        raw === "step" ||
        raw === "whole"
    ) {
        return raw;
    }
    return undefined;
}

function parseDraftSource(raw: string | undefined): DraftSource {
    if (raw === "remote" || raw === "local" || raw === "offline") {
        return raw;
    }
    // Incluye el `unknown` que la CLI emite cuando el bloque no está, y
    // cualquier valor que una CLI más nueva agregue: en los dos casos el cliente
    // no puede replicar los flags, que es exactamente lo que `unknown` significa.
    return "unknown";
}

/**
 * El estado de un borrador. Todo lo que no sea exactamente `reviewed` es
 * `fresh`, incluido el campo ausente: una CLI anterior a este registro no lo
 * emite, y ahí el panel tiene que comportarse como se comportaba —el borrador
 * en el bloque de siempre, con sus cuatro controles— y no esconder filas por
 * un dato que nadie le dio.
 */
function parseDraftState(raw: string | undefined): DraftState {
    return raw === "reviewed" ? "reviewed" : "fresh";
}

function parseDraftRange(raw: string | undefined): DraftRange {
    if (raw === "full" || raw === "delta") {
        return raw;
    }
    return "unknown";
}

/** Entero no negativo, o undefined: un campo malformado invalida el registro. */
function parseCount(raw: string | undefined): number | undefined {
    if (raw === undefined || !/^\d+$/.test(raw)) {
        return undefined;
    }
    return Number(raw);
}

function parseOfferRank(raw: string | undefined): OfferRank | undefined {
    if (raw === "recommended" || raw === "available") {
        return raw;
    }
    return undefined;
}

/**
 * Parsea `config`, `candidate`, `delta` y `offer`. `remote` cae a "origin" sólo
 * como último recurso defensivo: el contrato lo emite siempre.
 */
export function parseConfigPorcelain(stdout: string): ConfigPorcelainResult {
    let base: string | undefined;
    let remote: string | undefined;
    const candidates: CandidateBranch[] = [];
    const remotes: CandidateRemote[] = [];
    const deltas: DeltaRecord[] = [];
    const offers: ReadingOffer[] = [];
    const drafts: DraftRecord[] = [];
    const guides: GuideRecord[] = [];
    let walkthrough: WalkthroughRecord | undefined;

    for (const line of stdout.split(/\r?\n/)) {
        if (line.length === 0) {
            continue;
        }
        const fields = line.split("\t");
        switch (fields[0]) {
            case "config": {
                const key = fields[1];
                const value = fields[2];
                if (value === undefined) {
                    break;
                }
                if (key === "base") {
                    base = value;
                } else if (key === "remote") {
                    remote = value;
                }
                break;
            }
            case "remote-candidate": {
                const name = fields[1];
                if (name === undefined || name.length === 0) {
                    break;
                }
                remotes.push({name, current: toBool(fields[2])});
                break;
            }
            case "candidate": {
                const name = fields[1];
                const origin = fields[2];
                if (name === undefined || (origin !== "remote" && origin !== "local")) {
                    break;
                }
                candidates.push({name, origin, current: toBool(fields[3])});
                break;
            }
            case "delta": {
                const name = fields[1];
                const tip = fields[2];
                const origin = fields[3];
                if (
                    name !== undefined &&
                    tip !== undefined &&
                    (origin === "remote" || origin === "local")
                ) {
                    deltas.push({name, tip, origin});
                }
                break;
            }
            case "draft": {
                const src = fields[1];
                const path = fields[2];
                const annotated = parseCount(fields[3]);
                const total = parseCount(fields[4]);
                // Un registro malformado se ignora entero, como cualquier otro
                // desconocido: media fila de progreso sería peor que ninguna.
                if (
                    src === undefined ||
                    src.length === 0 ||
                    path === undefined ||
                    path.length === 0 ||
                    annotated === undefined ||
                    total === undefined
                ) {
                    break;
                }
                drafts.push({
                    src,
                    path,
                    annotated,
                    total,
                    source: parseDraftSource(fields[5]),
                    range: parseDraftRange(fields[6]),
                    state: parseDraftState(fields[7]),
                });
                break;
            }
            case "guide": {
                const guide = parseGuideRecord(fields);
                if (guide !== undefined) {
                    guides.push(guide);
                }
                break;
            }
            case "walkthrough": {
                // Una sola fila por invocación. Si llegaran dos, gana la primera:
                // la segunda sería una CLI contradiciéndose, y elegir la última
                // haría depender el panel del orden de emisión.
                const record = parseWalkthroughRecord(fields);
                if (record !== undefined && walkthrough === undefined) {
                    walkthrough = record;
                }
                break;
            }
            case "offer": {
                const id = parseOfferId(fields[1]);
                const rank = parseOfferRank(fields[2]);
                if (id !== undefined && rank !== undefined) {
                    offers.push({id, rank});
                }
                break;
            }
            default:
                // Etiqueta desconocida: se ignora (FR-003).
                break;
        }
    }

    const config: EffectiveConfig = {remote: remote ?? "origin"};
    if (base !== undefined) {
        config.base = base;
    }
    const result: ConfigPorcelainResult = {config, candidates, remotes, drafts, guides};
    if (walkthrough !== undefined) {
        result.walkthrough = walkthrough;
    }
    if (deltas.length > 0) {
        result.deltas = deltas;
    }
    if (offers.length > 0) {
        result.offers = offers;
    }
    return result;
}

/**
 * Marker `--delta` usable para un source de start: remote → fila remote;
 * local y offline → fila local (mismo marker en la CLI).
 */
export function deltaForSource(
    deltas: readonly DeltaRecord[] | undefined,
    source: "remote" | "local" | "offline"
): DeltaRecord | undefined {
    if (deltas === undefined || deltas.length === 0) {
        return undefined;
    }
    const origin: DeltaOrigin = source === "remote" ? "remote" : "local";
    return deltas.find((d) => d.origin === origin);
}
