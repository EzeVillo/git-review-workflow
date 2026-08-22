import type {
    DraftRecord,
    GuideKind,
    GuideRecord,
    GuideState,
    WalkthroughRecord,
    WalkthroughState,
} from "../cli/configPorcelain";
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
    /**
     * Cierre sin resolver de esta fila (`list --porcelain` → `finish`), si lo
     * hay. El panel lo usa para el title del badge `?` cuando no hay verbo en
     * la fila; no cruza a ninguna invocación.
     */
    finish?: {
        state: "pending" | "conflict";
        onto: boolean;
    };
}

/**
 * Una fila del bloque de borradores del estado vacío: un orden de lectura que
 * el revisor empezó y no pausó (registro `draft` de `config --porcelain`).
 *
 * Proyección plana, sin una sola derivación: el progreso lo cuenta la CLI y la
 * ruta la resuelve la CLI. `path` cruza al webview porque las cuatro acciones
 * salen de la fila, pero lo que vuelve del panel es el índice, como en
 * `PanelReview` — el host re-resuelve la fila antes de invocar nada.
 */
export interface PanelDraft {
    /** La rama del borrador, verbatim (`feature/checkout`). */
    branch: string;
    /** Ruta absoluta reportada por la CLI. El cliente la abre; nunca la arma. */
    path: string;
    annotated: number;
    total: number;
    /**
     * Si *Validate and start* se puede **invocar** para esta fila: sólo cuando
     * la CLI sabe con qué origen y rango se generó el borrador. Con `unknown`
     * (bloque de instrucciones borrado a mano) invocar con los defaults
     * fallaría siempre por deriva.
     *
     * El control se dibuja igual, apagado: apagado no adivina los flags más que
     * ausente —sigue sin poder invocarse— y encima dice por qué en el title,
     * que un control que no está no puede decir. Y la fila conserva sus cuatro
     * celdas, así que no cambia de forma con su estado.
     */
    startable: boolean;
}

/**
 * Una fila del bloque de guías de autoría: prosa sobre el CONTENIDO del
 * walkthrough, no sobre su formato.
 *
 * Las dos filas están siempre, exista o no cada archivo, y lo que cambia con el
 * estado es el enabled de los controles, nunca su presencia — misma regla que
 * las filas de borrador, y por el mismo motivo: dos filas con botoneras
 * distintas no se alinean una con la otra.
 *
 * `label` y `badge` se derivan acá porque son copy del panel; `path` llega de la
 * CLI, y el cliente **lo abre, nunca lo arma**.
 */
/**
 * La fila del walkthrough del autor: en qué estado está, cuánto de él está
 * escrito y qué se puede hacer con él sin salir del panel.
 *
 * Existe porque un walkthrough se escribe una vez, cuando el PR está terminado,
 * y después el PR sigue moviéndose. La fila es la única superficie que lo dice
 * sin que nadie se acuerde de preguntar, y por eso el badge es deliberadamente
 * cauto: "may be out of date" y no "out of date". La respuesta exacta es de
 * `build`, que es lo que corre el botón de al lado.
 *
 * `label`, `badge` y `actionLabel` son copy del panel y se derivan acá; `path`
 * llega de la CLI, y el cliente **lo abre, nunca lo arma**.
 */
export interface PanelWalkthrough {
    label: string;
    /** Ruta absoluta reportada por la CLI. Existe en disco sólo si `state !== "absent"`. */
    path: string;
    state: WalkthroughState;
    /** Texto del badge: el estado de la CLI, en prosa. */
    badge: string;
    /** Entradas completas, y todo lo que `build` exige (entradas más el heads-up). */
    annotated: number;
    total: number;
    /** El archivo está ahí: se puede abrir, y hay algo que copiarle a un agente. */
    exists: boolean;
    /** Cómo se llama el control que invoca `walkthrough init`, que crea y actualiza. */
    actionLabel: string;
}

export interface PanelGuide {
    kind: GuideKind;
    /** El nombre de la fila: la compartida y committeada, o la tuya fuera del árbol. */
    label: string;
    /** Ruta absoluta reportada por la CLI. Sólo existe en disco si `state !== "absent"`. */
    path: string;
    state: GuideState;
    /** Texto del badge: el estado que reportó la CLI, en prosa. */
    badge: string;
    /** El archivo está ahí (en vigor o vacío): se puede abrir y, si es la tuya, descartar. */
    exists: boolean;
    /**
     * Si *Create* se puede **invocar**. No es `!exists`: adentro de una review la
     * compartida no se puede crear, porque es un archivo del working tree y la
     * extracción de `finish` (`git add -A`) se lo llevaría al PR de otra persona.
     * La CLI lo niega; el control se dibuja igual, apagado y diciendo por qué.
     */
    creatable: boolean;
    /**
     * Sólo la tuya. La compartida es un archivo trackeado, así que borrarla es
     * `git rm` más un commit: una decisión sobre qué entra al PR, que no es de
     * este botón. La CLI dice lo mismo del otro lado negando `--delete --team`.
     */
    discardable: boolean;
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
     * Inventario del repositorio, en el orden de la CLI. Sólo con
     * `situation === "no-review"` (`state.branches`); en `finish-pending` el
     * panel no dibuja inventario (pantalla de post-cierre) y el host resuelve
     * el source del clean/undo desde `state.branches` + `pendingFinish`.
     * En cualquier otra situación es un array vacío.
     */
    reviews: PanelReview[];
    /**
     * Órdenes de lectura empezados y no pausados, en el orden de la CLI. Misma
     * regla que `reviews`: sólo con `situation === "no-review"`, array vacío en
     * cualquier otra. Una review en curso es siempre lo más importante que el
     * panel tiene para decir, y el borrador de otra rama no le compite el cuerpo.
     */
    drafts: PanelDraft[];
    /**
     * Las dos guías de autoría, en el orden de la CLI (compartida, tuya). Misma
     * regla que `drafts`: sólo con `situation === "no-review"`, array vacío en
     * cualquier otra — dentro de una review el panel tiene cosas más urgentes que
     * decir, y crear la compartida ahí la CLI lo niega igual.
     */
    guides: PanelGuide[];
    /**
     * El walkthrough del autor, cuando la CLI reportó su fila. Ausente con una
     * CLI anterior al registro, y entonces el bloque no se dibuja.
     */
    walkthrough?: PanelWalkthrough;
    /**
     * Cierre completo con undo vivo, sólo con `situation === "finish-pending"`
     * (contracts/finish-state.md): la fila `finish … pending` que hizo que el
     * estado dejara de ser `"no-review"`. El panel nombra el destino de las
     * edits y ofrece `finish --abort` / `clean <src>`. Ausente en cualquier
     * otra situación, y también si el inventario no trae ninguna fila
     * `pending` (no debería ocurrir: es la misma fila que decidió la
     * situación).
     */
    pendingFinish?: { branch: string; onto: boolean };
    /**
     * `true` cuando el empty state está en **modo setup**: `no-review` y el
     * reporte de `git review config --porcelain` llegó sin `base`. El panel
     * entonces solo ofrece configurar base (obligatoria) y remote (opcional);
     * sin Start, inventario ni footer de Other actions. `false` en cualquier
     * otra situación (incluido `finish-pending`), y también si el reporte de
     * config nunca llegó.
     */
    noBaseConfigured: boolean;
    /**
     * La base configurada para arrancar una review nueva — distinta de
     * `base` de acá abajo, que es la de una review YA activa (whole). Sólo
     * presente en el empty state (`no-review`) y el reporte de config con
     * `base` (FR-010/US1 escenario 6). Ausente si el reporte nunca llegó o
     * si llegó sin base — ahí es `noBaseConfigured` (setup).
     */
    configuredBase?: string;
    /**
     * Remoto efectivo (`origin` por default de la CLI). Presente en
     * `no-review` cuando el reporte de config llegó, con o sin base — setup
     * y Settings lo muestran. Ausente si el reporte nunca llegó o fuera de
     * `no-review`.
     */
    configuredRemote?: string;
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
    /**
     * `true` sólo con `situation === "finish-conflict"` (FR-027,
     * contracts/finish-state.md): la review sigue siendo legible —`mode`,
     * `branch`, `current`, etc. se proyectan igual que en una review normal—,
     * pero moverse por la secuencia con un cierre a medio aplicar no
     * corresponde. Se refleja forzando `atFirst`/`atLast` en `false` sin
     * importar dónde esté el cursor, no ocultando el resto de la review.
     */
    navigationLocked: boolean;
    /** `walkthrough === "degraded"` (FR-010). */
    degraded: boolean;
    /**
     * Compare de solo lectura: `finish` no aplica. Siempre booleano en el
     * modelo (el panel no distingue "CLI vieja" de "start normal": ambos son
     * "no es readonly").
     */
    readonly: boolean;
    /**
     * Walk keys-only (`status --porcelain` → registro `keys`). Siempre
     * booleano en el modelo (ausencia en porcelain = false).
     */
    keysOnly: boolean;
    /**
     * El orden de lectura es el borrador del revisor y no el walkthrough del
     * PR (`status --porcelain` → registro `draft`, 011). Siempre booleano en el
     * modelo, y **nunca** inferido: sólo refleja el registro.
     */
    draft: boolean;
    /** La entrada actual, elegida por `position` y nunca por `id`. */
    current?: PanelEntry;
    entryCount: number;
    /**
     * Inventario de archivos seleccionables:
     * - whole: los del rango (FR-010), desde `entry`;
     * - step: los del commit actual, desde registros `file`.
     * Sin cursor propio. Vacío (nunca ausente) en walk o cuando no hay paths.
     */
    files: PanelEntry[];
    /**
     * `PanelEntry.display` de la última fila de archivo que el revisor abrió
     * (whole o step), para marcarla en la lista. Sólo si sigue en `files`: un
     * path que salió del rango o del commit actual no deja una marca huérfana.
     *
     * No es estado del review y la CLI no lo conoce: es del lado del editor.
     * Se lleva por `display` y no por posición porque las posiciones se corren
     * cuando el rango/commit cambia.
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
        if (branch.finish !== undefined) {
            review.finish = {state: branch.finish.state, onto: branch.finish.onto};
        }
        return review;
    });
}

/**
 * Proyecta los registros `draft` de `config --porcelain`. Uno a uno, sin
 * reordenar ni filtrar: el orden es el de la CLI, y un borrador de una review
 * pausada no llega hasta acá porque la CLI no lo reporta (su archivo está en el
 * namespace archivado) — SC-012 se cumple aguas arriba, sin regla en el cliente.
 */
function toPanelDrafts(drafts: readonly DraftRecord[]): PanelDraft[] {
    return drafts.map((draft) => ({
        branch: draft.src,
        path: draft.path,
        annotated: draft.annotated,
        total: draft.total,
        startable: draft.source !== "unknown" && draft.range !== "unknown",
    }));
}

/** El badge de cada estado: el valor de la CLI en prosa, sin el guion. */
const GUIDE_BADGE: Record<GuideState, string> = {
    "in-force": "in force",
    empty: "empty",
    absent: "absent",
};

const GUIDE_LABEL: Record<GuideKind, string> = {
    team: "Repository guide",
    own: "Your guide",
};

/**
 * Proyecta los registros `guide`. Uno a uno y en el orden de la CLI, sin
 * completar la que falte: si un registro no llegó, la fila no se dibuja. Con una
 * CLI anterior no llega ninguno y el bloque entero desaparece, que es la misma
 * degradación que tiene el de borradores.
 */
function toPanelGuides(guides: readonly GuideRecord[], situation: Situation): PanelGuide[] {
    // La CLI niega crear la compartida adentro de una review, y por una razón
    // que el panel tiene que repetir en vez de descubrir: la extracción de
    // `finish` es `git add -A`, así que un archivo creado ahora se iría en el
    // `review-fixes/` de otra persona.
    const inReview = situation === "review" || situation === "finish-conflict";
    return guides.map((guide) => ({
        kind: guide.kind,
        label: GUIDE_LABEL[guide.kind],
        path: guide.path,
        state: guide.state,
        badge: GUIDE_BADGE[guide.state],
        exists: guide.state !== "absent",
        creatable: guide.state === "absent" && !(inReview && guide.kind === "team"),
        discardable: guide.kind === "own" && guide.state !== "absent",
    }));
}

/** El badge de cada estado del walkthrough: el valor de la CLI en prosa. */
const WALKTHROUGH_BADGE: Record<WalkthroughState, string> = {
    "in-sync": "up to date",
    stale: "may be out of date",
    superseded: "from a merged PR",
    unknown: "state unknown",
    absent: "none",
};

/**
 * Proyecta el registro `walkthrough`. Una sola fila, y sólo cuando la CLI la
 * emitió: con una versión anterior no llega, y el bloque entero desaparece —
 * misma degradación que las guías y los borradores.
 *
 * Todo lo que decide qué se puede apretar sale del estado que reportó la CLI.
 * En particular `updatable`, que NO es `stale`: reconciliar un walkthrough con
 * lo que el PR cambia hoy tiene sentido igual cuando el estado es `unknown` (el
 * bloque de instrucciones se borró a mano y nadie puede decir si quedó atrás),
 * y con `absent` el mismo verbo es lo que lo crea. Lo único que no se puede es
 * copiar el puntero a un archivo que no existe.
 */
function toPanelWalkthrough(record: WalkthroughRecord): PanelWalkthrough {
    return {
        label: "Walkthrough",
        path: record.path,
        state: record.state,
        badge: WALKTHROUGH_BADGE[record.state],
        annotated: record.annotated,
        total: record.total,
        exists: record.state !== "absent",
        // El verbo es el mismo (`walkthrough init`) y hace las dos cosas; lo que
        // cambia es cómo se llama en el panel, porque "Create" sobre un archivo
        // lleno de prosa es una promesa que la CLI no cumple -- y no debería.
        // Tres etiquetas para un solo verbo. `superseded` no es una variante de
        // "quedó atrás": el archivo es de un PR que ya se mergeó, y lo que la CLI
        // hace ahí es empezar de cero por su cuenta -- el botón dice lo que va a
        // pasar en vez de prometer una reconciliación que no ocurre.
        actionLabel:
            record.state === "absent"
                ? "Create"
                : record.state === "superseded"
                  ? "Start over"
                  : "Update",
    };
}

/**
 * La fila `index` del bloque de guías, o `undefined`. Mismo papel que
 * `draftAt`: el índice que llega del webview se valida contra el estado del
 * host, así que lo que termina en la CLI no sale del panel.
 */
export function guideAt(guides: readonly GuideRecord[], index: unknown): GuideRecord | undefined {
    if (typeof index !== "number" || !Number.isInteger(index)) {
        return undefined;
    }
    return guides[index];
}

/**
 * La fila `index` del bloque de borradores, o `undefined`. Mismo papel que
 * `resumableSourceAt`: es donde el índice que llega del webview se valida
 * contra el estado del host, así que lo que termina en la CLI no sale del panel.
 */
export function draftAt(drafts: readonly DraftRecord[], index: unknown): DraftRecord | undefined {
    if (typeof index !== "number" || !Number.isInteger(index)) {
        return undefined;
    }
    return drafts[index];
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
        // Inventario sólo en no-review: finish-pending es pantalla de
        // post-cierre (Undo / Clean), no el empty state con Start.
        reviews: state.situation === "no-review" ? toPanelReviews(state.branches) : [],
        drafts:
            state.situation === "no-review" && state.drafts !== undefined
                ? toPanelDrafts(state.drafts)
                : [],
        // A diferencia de `drafts`, las guías se dibujan también DENTRO de una
        // review: `walkthrough draft` se corre desde ahí, que es el momento más
        // probable de querer escribir la tuya. El dato no cuesta una invocación
        // extra — `status --porcelain` emite los mismos registros que `config`.
        guides: state.guides !== undefined ? toPanelGuides(state.guides, state.situation) : [],
        ...(state.walkthrough !== undefined
            ? {walkthrough: toPanelWalkthrough(state.walkthrough)}
            : {}),
        // Ausencia de dato (config nunca llegó) y "config llegó sin base" son
        // distintos, pero ambos se dibujan igual acá: nada que avisar. Sólo
        // "config llegó, y base está ausente" prende el aviso — y sólo en el
        // empty state que ofrece Start.
        noBaseConfigured:
            state.situation === "no-review"
            && state.config !== undefined
            && state.config.base === undefined,
        baseMoved: false,
        atFirst: false,
        atLast: false,
        navigationLocked: state.situation === "finish-conflict",
        degraded: false,
        readonly: false,
        keysOnly: false,
        draft: false,
        entryCount: 0,
        files: [],
    };
    if (inputs.repoLabel !== undefined) {
        base.repoLabel = inputs.repoLabel;
    }
    if (state.situation === "no-review" && state.config !== undefined) {
        base.configuredRemote = state.config.remote;
        if (state.config.base !== undefined) {
            base.configuredBase = state.config.base;
        }
    }
    if (state.stderr !== undefined && state.stderr.trim().length > 0) {
        base.stderr = state.stderr;
    }
    if (state.situation === "finish-pending") {
        const pending = state.branches.find((branch) => branch.finish?.state === "pending");
        if (pending?.finish) {
            base.pendingFinish = {branch: pending.name, onto: pending.finish.onto};
        }
    }

    const review = state.state;
    if ((state.situation !== "review" && state.situation !== "finish-conflict") || !review) {
        return base;
    }

    base.mode = review.mode;
    base.branch = review.branch;
    base.source = review.source;
    base.tip = review.tip;
    base.degraded = review.walkthrough === "degraded";
    base.readonly = state.readonly === true;
    base.keysOnly = state.keysOnly === true;
    base.draft = state.draft === true;
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
    if (base.navigationLocked) {
        // FR-027: un cierre trabado bloquea la navegación entera, sin importar
        // dónde haya quedado el cursor — nunca sólo el extremo en el que
        // casualmente estaba.
        base.atFirst = false;
        base.atLast = false;
    }

    const current = currentEntry(state.entries, review.position);
    if (current) {
        base.current = toPanelEntry(current, state.subjects, state.authors);
    }

    // Step: inventario del commit bajo el cursor (registros `file`), no de la
    // secuencia de commits. Misma marca lastOpened que whole, validada acá.
    if (review.mode === "step") {
        base.files = (state.files ?? []).map((file) => toPanelEntry(file));
        if (inputs.lastOpened !== undefined && base.files.some((file) => file.display === inputs.lastOpened)) {
            base.lastOpened = inputs.lastOpened;
        }
    }

    if (review.mode === "walk" && current) {
        base.why = inputs.why ?? {state: "loading"};
    }

    return base;
}
