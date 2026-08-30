import type {
    DraftRecord,
    GuideKind,
    GuideRecord,
    GuideState,
    WalkthroughRecord,
    WalkthroughState,
} from "../cli/configPorcelain";
import {BranchRecord, EntryRecord, FixesState, ReviewMode, sourceOf} from "../cli/porcelain";
import type {PathRef} from "../cli/unquote";
import type {Situation} from "../review/situation";
import type {ReviewState} from "../review/state";

/**
 * Los cuatro estados del *why*, no dos: `loading` existe porque el panel se
 * dibuja con `status --porcelain` y la explicación llega después; `absent`
 * (exit 0, cuerpo vacío) tiene que verse distinto de `failed`.
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
     * provee", y el panel dibuja lo mismo que dibujaba antes de que existieran.
     * `subject` vacío es otra cosa: un commit sin asunto, que sí se muestra así.
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
     * Si corresponde ofrecer `Continue`: la lectura de los dos modos de fallo
     * que el propio inventario ya deja ver —huérfana, o con una review activa
     * para el mismo source—, no una regla nueva; quien decide si se puede
     * resumir sigue siendo `git review continue`. El tercer modo de fallo,
     * working tree sucio, no se ve desde acá y se deja fallar.
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
 * Una fila de la sección "Edits you extracted": una rama `review-fixes/*` que
 * dejó un `finish` (registro `fixes` de `list --porcelain`).
 *
 * Proyección plana, sin una sola derivación: cuánto cuesta tirarla lo contesta
 * la CLI, que es la que puede preguntarle a git. Lo que vuelve del panel es el
 * índice, como en `PanelReview`, y el host re-resuelve la fila antes de
 * invocar nada.
 */
export interface PanelFixes {
    /** Nombre de la rama tal cual lo emitió la CLI (`review-fixes/x`). */
    name: string;
    /** La rama en la que estás parado: `clean` la saltea, así que no se ofrece. */
    current: boolean;
    /** `review/<x>` sigue existiendo; lo dice la confirmación, no el argv. */
    session: boolean;
    state: FixesState;
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
     * Si *Validate and start* se puede **invocar**: sólo cuando la CLI sabe con
     * qué origen y rango se generó el borrador. Con `unknown` (bloque de
     * instrucciones borrado a mano) invocar con los defaults fallaría siempre
     * por deriva. El control se dibuja igual pero apagado, y dice por qué en el
     * title — así la fila conserva sus cuatro celdas sin cambiar de forma.
     */
    startable: boolean;
    /**
     * Si su review ya terminó. Un borrador sobrevive a la review para la que
     * se escribió —`clean` no toca prosa escrita a mano— pero deja de ser
     * trabajo en curso, así que sale del bloque de arriba y baja a una sección
     * plegada con los dos controles que siguen teniendo sentido: abrirlo y
     * descartarlo. Lo decide la CLI; acá no se infiere.
     */
    spent: boolean;
}

/**
 * La fila del walkthrough del autor: en qué estado está, cuánto tiene escrito y
 * qué se puede hacer con él sin salir del panel. Existe porque un walkthrough se
 * escribe una vez, cuando el PR está terminado, y el PR sigue moviéndose después
 * — es la única superficie que lo recuerda, y por eso el badge es deliberadamente
 * cauto ("may be out of date", no "out of date"); la respuesta exacta es de
 * `build`. `label`, `badge` y `actionLabel` son copy del panel derivada acá;
 * `path` llega de la CLI y el cliente **lo abre, nunca lo arma**.
 */
export interface PanelWalkthrough {
    /**
     * Cómo se llama la fila: **la rama** que este walkthrough anota, tal como la
     * reportó la CLI. Cae a "Walkthrough" sólo cuando el registro omitió el
     * campo, que es lo que pasa con `HEAD` detached.
     */
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

/**
 * Una fila del bloque de guías de autoría: prosa sobre el CONTENIDO del
 * walkthrough, no sobre su formato. Las dos filas están siempre, exista o no
 * cada archivo; lo que cambia con el estado es el enabled de los controles,
 * nunca su presencia (misma regla que las filas de borrador: dos botoneras
 * distintas no se alinean entre sí). `label` y `badge` son copy del panel
 * derivada acá; `path` llega de la CLI y el cliente **lo abre, nunca lo arma**.
 */
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
    /** Sólo con más de un repositorio en la ventana. */
    repoLabel?: string;
    /**
     * Inventario del repositorio, en el orden de la CLI. Sólo con
     * `situation === "no-review"` (`state.branches`) y array vacío en cualquier
     * otra: en `finish-pending` el panel no dibuja inventario (pantalla de
     * post-cierre) y el host resuelve el source del clean/undo desde
     * `state.branches` + `pendingFinish`.
     */
    reviews: PanelReview[];
    /**
     * Órdenes de lectura empezados y no pausados, en el orden de la CLI. Mismo
     * alcance que `reviews`; una review en curso siempre pesa más que el
     * borrador de otra rama, así que no le compite el cuerpo del panel.
     */
    drafts: PanelDraft[];
    /** Las dos guías de autoría, en el orden de la CLI (compartida, tuya). Mismo alcance que `reviews`. */
    guides: PanelGuide[];
    /** Las ramas de ediciones que dejó un `finish`, en el orden de la CLI. Mismo alcance que `reviews`. */
    fixes: PanelFixes[];
    /**
     * El walkthrough del autor. **Siempre presente** en `no-review`: los dos
     * verbos que actúan sobre el archivo son la botonera de esta fila, así que
     * una fila condicional los dejaría sin superficie. Cuando el registro no se
     * pudo leer, la fila llega en `unknown` — literalmente "no se puede saber"
     * — y no inventa ni un estado ni una ruta.
     */
    walkthrough?: PanelWalkthrough;
    /**
     * Cierre completo con undo vivo, sólo con `situation === "finish-pending"`
     * (contracts/finish-state.md): la fila `finish … pending` que sacó al
     * estado de `"no-review"`. El panel nombra el destino de las edits y
     * ofrece `finish --abort` / `clean <src>`. Ausente en cualquier otra
     * situación.
     */
    pendingFinish?: { branch: string; onto: boolean };
    /**
     * `true` cuando el empty state está en **modo setup**: `no-review` y el
     * reporte de `git review config --porcelain` llegó sin `base`. Ahí sólo
     * se ofrece configurar base (obligatoria) y remote (opcional); sin Start,
     * inventario ni footer. `false` en cualquier otra situación, incluido
     * cuando el reporte de config nunca llegó.
     */
    noBaseConfigured: boolean;
    /**
     * La base configurada para arrancar una review nueva — distinta de `base`
     * de acá abajo, que es la de una review YA activa (whole). Sólo presente
     * en el empty state con `base` configurada; ausente si el reporte nunca
     * llegó o llegó sin base (ahí es `noBaseConfigured`).
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
     * Origen de la review (el PR) y el punto sobre el que quedó fijada. El
     * `tip` viaja completo, como lo emite la CLI; abreviarlo es presentación
     * y ocurre al dibujar, no acá.
     */
    source?: string;
    tip?: string;
    /**
     * Base contra la que se armó el rango. Sólo en whole y sólo si la CLI la
     * reportó: sin ella el panel no muestra nada en su lugar.
     */
    base?: string;
    /** Sólo en step/walk. */
    position?: number;
    total?: number;
    /**
     * `total < recorded`: la base se movió pero el cursor sigue en rango. No
     * `total !== recorded`: en walk, un review abierto antes de que los
     * archivos no anotados entraran a la secuencia deja `recorded` por debajo
     * del `total` recién derivado — eso es la secuencia creciendo, no la base
     * moviéndose, y no hay que avisarlo.
     */
    baseMoved: boolean;
    /**
     * Extremos de la secuencia, para no ofrecer un control que ya no puede
     * mover nada. No duplican la regla de la CLI —quien decide si el cursor se
     * mueve sigue siendo el verbo—: son la lectura de `position`/`total` que la
     * CLI *ya* reportó, la misma que dibuja la barra. Fuera de step/walk son
     * `false`: sin cursor no hay extremo.
     */
    atFirst: boolean;
    atLast: boolean;
    /**
     * `true` sólo con `situation === "finish-conflict"` (contracts/finish-
     * state.md): la review sigue siendo legible —`mode`, `branch`, `current`,
     * etc. se proyectan igual que en una review normal—, pero moverse por la
     * secuencia con un cierre a medio aplicar no corresponde. Se refleja
     * forzando `atFirst`/`atLast` en `false`, no ocultando el resto.
     */
    navigationLocked: boolean;
    /** `walkthrough === "degraded"`. */
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
     * PR (`status --porcelain` → registro `draft`). Siempre booleano, y
     * **nunca** inferido: sólo refleja el registro.
     */
    draft: boolean;
    /** La entrada actual, elegida por `position` y nunca por `id`. */
    current?: PanelEntry;
    entryCount: number;
    /**
     * Inventario de archivos seleccionables: en whole, los del rango (desde
     * `entry`); en step, los del commit actual (registros `file`). Sin cursor
     * propio. Vacío (nunca ausente) en walk o cuando no hay paths.
     */
    files: PanelEntry[];
    /**
     * `PanelEntry.display` de la última fila de archivo que el revisor abrió
     * (whole o step), para marcarla en la lista. Sólo si sigue en `files`: un
     * path que salió del rango o del commit actual no deja una marca huérfana.
     * No es estado del review —es del lado del editor, y la CLI no lo conoce—
     * y se lleva por `display` y no por posición porque las posiciones se
     * corren cuando el rango/commit cambia.
     */
    lastOpened?: string;
    /** Sólo en walk: el modo step no tiene explicaciones. */
    why?: PanelWhy;
    /** stderr de la CLI, preservado tal cual. */
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
 * `vscode`, para poder probarse sin un editor: es lo que hace visible la
 * posición actual y las marcas, o sea lo que puede romperse en silencio.
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
        marks.push("not covered");
    }
    if (entry.banked) {
        marks.push("saved edits");
    }
    // El asunto acompaña al identificador, no lo reemplaza: nadie reconoce un
    // commit por siete caracteres hexadecimales, pero el SHA es lo que se pega
    // en una terminal. Un asunto vacío no agrega nada que mostrar.
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
 * rechaza con "is already active" (`bin/git-review-verbs/continue`).
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
        spent: draft.state === "reviewed",
    }));
}

/**
 * El badge de cada estado: dos son los valores de la CLI; `absent` se dice
 * "none", porque "empty" y "absent" se leen como sinonimos de un vistazo y no lo
 * son -- `empty` es "el archivo esta, no dice nada" y `absent` es "no hay
 * archivo", que es lo que decide si el boton de al lado abre o crea.
 */
const GUIDE_BADGE: Record<GuideState, string> = {
    "in-force": "in force",
    empty: "empty",
    absent: "none",
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
function toPanelGuides(guides: readonly GuideRecord[]): PanelGuide[] {
    return guides.map((guide) => ({
        kind: guide.kind,
        label: GUIDE_LABEL[guide.kind],
        path: guide.path,
        state: guide.state,
        badge: GUIDE_BADGE[guide.state],
        exists: guide.state !== "absent",
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
 * Proyecta el registro `walkthrough`. Una sola fila, **siempre**: los dos verbos
 * que actúan sobre el archivo (`init` y `build`) son su botonera, así que
 * dibujarla sólo a veces sería dejarlos sin superficie a veces. Sin registro
 * —malformado, o una CLI que no lo emite y que el cliente ya rechazó por
 * versión— la fila llega en `unknown`, que es el estado que la CLI define como
 * "la pregunta no tiene respuesta": no inventa ni un badge ni una ruta.
 *
 * El nombre de la fila es la RAMA que anota, no la palabra "Walkthrough": la
 * sección ya se llama así, y decirlo dos veces no agregaba un dato.
 *
 * Todo lo que decide qué se puede apretar sale del estado que reportó la CLI.
 * En particular `updatable`, que NO es `stale`: reconciliar un walkthrough con
 * lo que el PR cambia hoy tiene sentido igual cuando el estado es `unknown` (el
 * bloque de instrucciones se borró a mano y nadie puede decir si quedó atrás),
 * y con `absent` el mismo verbo es lo que lo crea. Lo único que no se puede es
 * copiar el puntero a un archivo que no existe.
 */
function toPanelWalkthrough(record: WalkthroughRecord | undefined): PanelWalkthrough {
    // Sin registro no hay ni ruta ni estado, y ninguno de los dos se inventa:
    // `unknown` ya significa "no se puede saber" del lado de la CLI, y una ruta
    // vacía apaga los dos controles que necesitan el archivo.
    const state: WalkthroughState = record?.state ?? "unknown";
    return {
        label: record?.branch ?? "Walkthrough",
        path: record?.path ?? "",
        state,
        badge: WALKTHROUGH_BADGE[state],
        annotated: record?.annotated ?? 0,
        total: record?.total ?? 0,
        exists: record !== undefined && state !== "absent",
        // El verbo es el mismo (`walkthrough init`) y hace las dos cosas; lo que
        // cambia es cómo se llama en el panel, porque "Create" sobre un archivo
        // lleno de prosa es una promesa que la CLI no cumple -- y no debería.
        // Tres etiquetas para un solo verbo. `superseded` no es una variante de
        // "quedó atrás": el archivo es de un PR que ya se mergeó, y lo que la CLI
        // hace ahí es empezar de cero por su cuenta -- el botón dice lo que va a
        // pasar en vez de prometer una reconciliación que no ocurre.
        // Sin registro no se sabe nada del archivo, así que el botón se queda
        // con el nombre por defecto del verbo: "Update" prometería reconciliar
        // algo que nadie puede decir que está.
        actionLabel:
            record === undefined || state === "absent"
                ? "Create"
                : state === "superseded"
                  ? "Start over"
                  : "Update",
    };
}

/**
 * La fila `index` del bloque de guías, o `undefined`. El índice que llega del
 * webview se valida acá contra el estado del host (entero en rango), así que
 * lo que termina en la CLI nunca sale directamente del panel. Mismo papel que
 * `draftAt` y `resumableSourceAt`.
 */
export function guideAt(guides: readonly GuideRecord[], index: unknown): GuideRecord | undefined {
    if (typeof index !== "number" || !Number.isInteger(index)) {
        return undefined;
    }
    return guides[index];
}

/** La fila `index` del bloque de borradores, o `undefined`. Mismo papel que `guideAt`. */
export function draftAt(drafts: readonly DraftRecord[], index: unknown): DraftRecord | undefined {
    if (typeof index !== "number" || !Number.isInteger(index)) {
        return undefined;
    }
    return drafts[index];
}

/**
 * El *source* de la fila `index` del inventario, sólo si esa fila puede
 * resumirse — es el argumento que espera `continue`. Mismo papel que
 * `guideAt`, y además exige que la fila sea `resumable`. Índice fuera de rango
 * o fila no resumible: `undefined`, y el comando no hace nada.
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
        // Sólo llegan por `config --porcelain`, o sea sólo fuera de una review:
        // el pie es donde se dibujan y una review no tiene pie.
        guides: state.guides !== undefined ? toPanelGuides(state.guides) : [],
        // Sólo en `no-review`, como el resto del pie. Uno a uno y en el orden de
        // la CLI: acá no se filtra ni se reordena nada, ni siquiera la fila
        // `current` — es la única que no se puede borrar, y esconderla dejaría
        // una rama que existe sin ninguna superficie que la nombre, que es
        // justo lo que esta sección vino a arreglar.
        fixes:
            state.situation === "no-review" && state.fixes !== undefined
                ? state.fixes.map((record) => ({
                    name: record.name,
                    current: record.current,
                    session: record.session,
                    state: record.state,
                }))
                : [],
        // Sólo en `no-review`: es donde vive la sección — una review no tiene
        // pie. La fila se construye aunque el registro falte -- ver
        // toPanelWalkthrough.
        ...(state.situation === "no-review"
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
