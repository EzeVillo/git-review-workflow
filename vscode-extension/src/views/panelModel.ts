import {BranchRecord, EntryRecord, ReviewMode, sourceOf} from "../cli/porcelain";
import type {PathRef} from "../cli/unquote";
import type {Situation} from "../review/situation";
import type {ReviewState} from "../review/state";

/**
 * Los cuatro estados del *why*, no dos: `loading` existe porque el panel se
 * dibuja con el `status --porcelain` y la explicación llega después, y `absent`
 * (exit 0, cuerpo vacío) tiene que verse distinto de `failed` (FR-018).
 */
export type WhyState = "loading" | "present" | "absent" | "failed";

export interface PanelWhy {
    state: WhyState;
    /** Sólo con `state === "present"`. */
    text?: string;
}

export interface PanelEntry {
    position: number;
    /** `PathRef.display` en walk, SHA corto en step. El `raw` NO cruza al webview. */
    display: string;
    essential: boolean;
    /**
     * Sólo tiene sentido en walk (`PanelModel.mode === "walk"`); en step vale
     * siempre `true` por ausencia de campo en el registro, y se ignora.
     */
    annotated: boolean;
    banked: boolean;
    /**
     * Sólo en step, y sólo si la CLI los reportó. Ausentes = "esta CLI no los
     * provee", y el panel dibuja exactamente lo que dibujaba antes de que
     * existieran (FR-003). `subject` vacío es otra cosa: un commit sin asunto,
     * que sí se muestra como tal (FR-004).
     */
    subject?: string;
    author?: string;
}

/**
 * Una fila del inventario del estado vacío (`no-review`). El `source` no cruza
 * al webview: el host lo re-deriva del índice cuando le toca invocar
 * `continue`, así que nada de lo que vuelve del panel llega a un proceso
 * (contracts/extension-surface.md § Protocolo).
 */
export interface PanelReview {
    /** Nombre de la rama tal cual lo emitió la CLI (`review/x`, `review-saved/x`). */
    name: string;
    saved: boolean;
    current: boolean;
    orphan: boolean;
    mode?: ReviewMode;
    position?: number;
    total?: number;
    /**
     * Si corresponde ofrecer `Continue`. Es la lectura de los dos modos de
     * fallo del verbo que el propio inventario deja ver —huérfana, o con una
     * review activa para el mismo source—, no una regla nueva: quien decide si
     * se puede resumir sigue siendo `git review continue`. El working tree
     * sucio, su tercer modo de fallo, no se ve desde acá y se deja fallar.
     */
    resumable: boolean;
}

/**
 * `PanelModel` (data-model.md) — la proyección plana y serializable que es lo
 * único que cruza hacia el webview, y el punto donde afirman los tests.
 *
 * No agrega información: decide qué de lo que ya reportó la CLI es visible.
 * Deliberadamente sin `import` de `vscode` (sólo tipos, que la compilación
 * borra), para que se construya y se pruebe sin un editor.
 */
export interface PanelModel {
    situation: Situation;
    busy: boolean;
    /** Sólo con más de un repositorio en la ventana (FR-029). */
    repoLabel?: string;
    /**
     * Inventario del repositorio, en el orden de la CLI. Sólo se puebla con
     * `situation === "no-review"`; en cualquier otra es un array vacío.
     */
    reviews: PanelReview[];
    /** De acá para abajo, sólo con `situation === "review"`. */
    mode?: ReviewMode;
    branch?: string;
    /**
     * Origen de la review (el PR) y punto sobre el que quedó fijada. Los dos ya
     * venían en `state` desde `001` y el panel no los dibujaba: son la mitad de
     * la Historia 2 que no necesitó contrato nuevo (research.md Decisión 0).
     * El `tip` viaja completo, como lo emite la CLI; abreviarlo es presentación
     * y ocurre al dibujar, no acá.
     */
    source?: string;
    tip?: string;
    /**
     * Base contra la que se armó el rango. Sólo en whole y sólo si la CLI la
     * reportó: sin ella el panel no muestra nada en su lugar (FR-009).
     */
    base?: string;
    /** Sólo en step/walk. */
    position?: number;
    total?: number;
    /**
     * `total < recorded`: la base se movió pero el cursor sigue en rango
     * (FR-011). No `total !== recorded`: en walk, `recorded` de un review
     * abierto antes de que los archivos no anotados entraran a la secuencia
     * queda por debajo del `total` recién derivado, y eso no es la base
     * moviéndose — es la secuencia creciendo, algo que no hay que avisar.
     */
    baseMoved: boolean;
    /**
     * Extremos de la secuencia, para que el panel no ofrezca un control que ya
     * no puede mover nada. No duplican la regla de la CLI —quien decide si el
     * cursor se mueve sigue siendo el verbo (FR-016)—: son la lectura de la
     * `position`/`total` que la CLI *ya* reportó, la misma que el panel dibuja
     * en la barra. Fuera de step/walk son `false`: sin cursor no hay extremo.
     */
    atFirst: boolean;
    atLast: boolean;
    /** `walkthrough === "degraded"` (FR-010). */
    degraded: boolean;
    /** La entrada actual, elegida por `position` y nunca por `id`. */
    current?: PanelEntry;
    entryCount: number;
    /**
     * Los archivos del rango en modo whole (FR-010): un inventario, no una
     * secuencia — sin cursor, sin `essential`/`annotated`/`banked` con
     * significado (siempre `false`/`true`/`false` por ausencia de campo, como
     * en cualquier `PanelEntry` de un modo que no los reporta). Vacío (nunca
     * ausente) fuera de whole, donde la colección se recorre con el cursor.
     */
    files: PanelEntry[];
    /**
     * `PanelEntry.display` de la última entrada que el revisor abrió en whole,
     * para marcarla en la lista. Sólo en whole y sólo si sigue estando en el
     * rango: una marca que no corresponde a ninguna fila no se emite, así que un
     * archivo que salió del PR no deja un recuerdo apuntando a la nada.
     *
     * No es estado del review y la CLI no lo conoce (la lista de whole no tiene
     * cursor): es del lado del editor, que es el único que sabe qué se abrió
     * desde el panel. Se lleva por `display` y no por posición porque las
     * posiciones se corren cuando el rango cambia, y ahí la marca señalaría otro
     * archivo en silencio.
     */
    lastOpened?: string;
    /** Sólo en walk: el modo step no tiene explicaciones. */
    why?: PanelWhy;
    /** stderr de la CLI, preservado tal cual (FR-024). */
    stderr?: string;
}

export interface PanelInputs {
    busy: boolean;
    repoLabel?: string;
    /** Ausente = todavía en vuelo; el modelo lo refleja como `loading`. */
    why?: PanelWhy;
    /** Lo que el host recuerda de esta review; ver `PanelModel.lastOpened`. */
    lastOpened?: string;
}

function displayOf(id: string | PathRef): string {
    return typeof id === "string" ? id : id.display;
}

function toPanelEntry(
    entry: EntryRecord,
    subjects?: Map<number, string>,
    authors?: Map<number, string>
): PanelEntry {
    const panelEntry: PanelEntry = {
        position: entry.position,
        display: displayOf(entry.id),
        essential: entry.essential === true,
        // Ausente (step) o `true` (walk) es "sí anotada"; sólo `false` explícito
        // (walk) marca un archivo que el walkthrough no anota.
        annotated: entry.annotated !== false,
        banked: entry.banked === true,
    };
    // Por `position` y nunca por orden: es lo que el contrato exige, y lo que
    // hace que un registro faltante quede ausente en vez de correr los demás.
    const subject = subjects?.get(entry.position);
    if (subject !== undefined) {
        panelEntry.subject = subject;
    }
    const author = authors?.get(entry.position);
    if (author !== undefined) {
        panelEntry.author = author;
    }
    return panelEntry;
}

export interface PickLabel {
    label: string;
    /** Marcas de la entrada, separadas por `·`; vacío si no tiene ninguna. */
    description: string;
}

function pad(position: number): string {
    return position < 10 ? `0${position}` : String(position);
}

/**
 * Texto de una entrada en el `QuickPick` de la secuencia. Vive acá, sin
 * `vscode`, porque es lo que hace visible la posición actual y las marcas
 * (FR-006, FR-007, FR-027) — o sea, lo que puede romperse en silencio.
 */
export function entryPickLabel(
    entry: EntryRecord,
    position: number | undefined,
    subject?: string
): PickLabel {
    const marks: string[] = [];
    if (entry.position === position) {
        marks.push("current");
    }
    // `key` es el marcador del walkthrough (`> key`), igual que en el panel.
    if (entry.essential) {
        marks.push("key");
    }
    // `annotated` sólo viene en walk; ausente (step) nunca dispara esta marca.
    if (entry.annotated === false) {
        marks.push("uncovered");
    }
    if (entry.banked) {
        marks.push("banked edits");
    }
    // El asunto acompaña al identificador, no lo reemplaza: nadie reconoce un
    // commit por siete caracteres hexadecimales, pero el SHA es lo que se pega
    // en una terminal (FR-007). Un asunto vacío no agrega nada que mostrar.
    const id = displayOf(entry.id);
    return {
        label: subject !== undefined && subject.length > 0
            ? `${pad(entry.position)}  ${id}  ${subject}`
            : `${pad(entry.position)}  ${id}`,
        description: marks.join(" · "),
    };
}

/** Sólo la entrada cuya `position` coincide con el cursor; si ninguna, ninguna. */
export function currentEntry(entries: EntryRecord[], position: number | undefined): EntryRecord | undefined {
    if (position === undefined) {
        return undefined;
    }
    return entries.find((entry) => entry.position === position);
}

/**
 * Proyecta el inventario de `list --porcelain`. `resumable` necesita ver la
 * lista entera y no sólo la fila: una guardada deja de poder resumirse cuando
 * existe además una activa para el mismo source, que es lo que el verbo
 * rechaza con "is already active" (`bin/git-review-verbs/continue:80`).
 */
function toPanelReviews(branches: BranchRecord[]): PanelReview[] {
    const active = new Set(branches.filter((b) => !b.saved).map(sourceOf));
    return branches.map((branch) => {
        const review: PanelReview = {
            name: branch.name,
            saved: branch.saved,
            current: branch.current,
            orphan: branch.orphan,
            resumable: branch.saved && !branch.orphan && !active.has(sourceOf(branch)),
        };
        if (branch.mode !== undefined) {
            review.mode = branch.mode;
        }
        if (branch.position !== undefined && branch.total !== undefined) {
            review.position = branch.position;
            review.total = branch.total;
        }
        return review;
    });
}

/**
 * El *source* de la fila `index` del inventario, sólo si esa fila puede
 * resumirse. Es el punto donde el índice que llega del webview se convierte en
 * el argumento de `continue`: valida que sea un entero en rango contra el
 * inventario que tiene el host, así que lo que termina en la CLI sale del
 * estado del host y no del panel. Cualquier índice que no resuelva es
 * `undefined`, y el comando no hace nada.
 */
export function resumableSourceAt(branches: BranchRecord[], index: unknown): string | undefined {
    if (typeof index !== "number" || !Number.isInteger(index)) {
        return undefined;
    }
    const branch = branches[index];
    const review = toPanelReviews(branches)[index];
    if (!branch || !review || !review.resumable) {
        return undefined;
    }
    return sourceOf(branch);
}

export function buildPanelModel(state: ReviewState, inputs: PanelInputs): PanelModel {
    const base: PanelModel = {
        situation: state.situation,
        busy: inputs.busy,
        reviews: toPanelReviews(state.branches),
        baseMoved: false,
        atFirst: false,
        atLast: false,
        degraded: false,
        entryCount: 0,
        files: [],
    };
    if (inputs.repoLabel !== undefined) {
        base.repoLabel = inputs.repoLabel;
    }
    if (state.stderr !== undefined && state.stderr.trim().length > 0) {
        base.stderr = state.stderr;
    }

    const review = state.state;
    if (state.situation !== "review" || !review) {
        return base;
    }

    base.mode = review.mode;
    base.branch = review.branch;
    base.source = review.source;
    base.tip = review.tip;
    base.degraded = review.walkthrough === "degraded";
    base.entryCount = state.entries.length;

    if (review.mode === "whole") {
        // La CLI sólo emite el registro en whole, pero el modelo no se apoya en
        // eso: lo proyecta donde tiene sentido mostrarlo y en ningún otro lado.
        if (state.base !== undefined) {
            base.base = state.base;
        }
        base.files = state.entries.map((entry) => toPanelEntry(entry, state.subjects, state.authors));
        // Se valida contra la lista, no se copia: lo que el host recuerda puede
        // ser un archivo que el PR ya no toca, y ahí no hay fila que marcar.
        if (inputs.lastOpened !== undefined && base.files.some((file) => file.display === inputs.lastOpened)) {
            base.lastOpened = inputs.lastOpened;
        }
        return base;
    }

    base.position = review.position;
    base.total = review.total;
    base.baseMoved = review.recorded !== undefined && review.total !== undefined && review.total < review.recorded;
    // `>=` / `<=` y no `===`: con la base movida el cursor puede quedar afuera
    // del rango re-derivado, y ahí tampoco hay a dónde seguir.
    base.atFirst = review.position !== undefined && review.position <= 1;
    base.atLast = review.position !== undefined && review.total !== undefined && review.position >= review.total;

    const current = currentEntry(state.entries, review.position);
    if (current) {
        base.current = toPanelEntry(current, state.subjects, state.authors);
    }

    if (review.mode === "walk" && current) {
        base.why = inputs.why ?? {state: "loading"};
    }

    return base;
}
