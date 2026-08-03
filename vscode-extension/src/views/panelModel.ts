import type {EntryRecord, ReviewMode} from "../cli/porcelain";
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
    banked: boolean;
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
    /** De acá para abajo, sólo con `situation === "review"`. */
    mode?: ReviewMode;
    branch?: string;
    /** Sólo en step/walk. */
    position?: number;
    total?: number;
    /** `total ≠ recorded`: la base se movió pero el cursor sigue en rango (FR-011). */
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
    uncoveredCount: number;
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
}

function displayOf(id: string | PathRef): string {
    return typeof id === "string" ? id : id.display;
}

function toPanelEntry(entry: EntryRecord): PanelEntry {
    return {
        position: entry.position,
        display: displayOf(entry.id),
        essential: entry.essential === true,
        banked: entry.banked === true,
    };
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
export function entryPickLabel(entry: EntryRecord, position: number | undefined): PickLabel {
    const marks: string[] = [];
    if (entry.position === position) {
        marks.push("actual");
    }
    if (entry.essential) {
        marks.push("esencial");
    }
    if (entry.banked) {
        marks.push("con ediciones guardadas");
    }
    return {
        label: `${pad(entry.position)}  ${displayOf(entry.id)}`,
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

export function buildPanelModel(state: ReviewState, inputs: PanelInputs): PanelModel {
    const base: PanelModel = {
        situation: state.situation,
        busy: inputs.busy,
        baseMoved: false,
        atFirst: false,
        atLast: false,
        degraded: false,
        entryCount: 0,
        uncoveredCount: 0,
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
    base.degraded = review.walkthrough === "degraded";
    base.entryCount = state.entries.length;
    base.uncoveredCount = state.uncovered.length;

    if (review.mode === "whole") {
        return base;
    }

    base.position = review.position;
    base.total = review.total;
    base.baseMoved = review.recorded !== undefined && review.total !== review.recorded;
    // `>=` / `<=` y no `===`: con la base movida el cursor puede quedar afuera
    // del rango re-derivado, y ahí tampoco hay a dónde seguir.
    base.atFirst = review.position !== undefined && review.position <= 1;
    base.atLast = review.position !== undefined && review.total !== undefined && review.position >= review.total;

    const current = currentEntry(state.entries, review.position);
    if (current) {
        base.current = toPanelEntry(current);
    }

    if (review.mode === "walk" && current) {
        base.why = inputs.why ?? {state: "loading"};
    }

    return base;
}
