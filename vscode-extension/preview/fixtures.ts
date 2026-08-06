/**
 * Los estados que dibuja el preview del panel (`npm run preview`).
 *
 * Ninguno es un `PanelModel` escrito a mano: los reviews salen de una salida
 * `status --porcelain` de ejemplo pasada por el parser real y por
 * `buildPanelModel`, que es el mismo camino que recorre el estado en la
 * extensión. Un cambio en el formato porcelain o en el modelo se ve acá sin
 * tocar nada, y si cambia la forma de `PanelModel` es la compilación la que
 * avisa — un fixture literal se quedaría mintiendo en silencio.
 *
 * Lo único que se mantiene a mano es *qué* estados vale la pena mirar.
 */
import {parseListPorcelain, parsePorcelain} from "../src/cli/porcelain";
import {buildPanelModel, PanelInputs, PanelModel} from "../src/views/panelModel";
import type {Situation} from "../src/review/situation";
import type {ReviewState} from "../src/review/state";

export interface PreviewPane {
    name: string;
    /** Qué muestra este estado; va debajo del pane en el índice. */
    caption: string;
    model: PanelModel;
}

/** Registros porcelain como filas de campos, para no escribir tabs literales. */
function porcelain(rows: string[][]): string {
    return rows.map((fields) => fields.join("\t")).join("\n") + "\n";
}

function review(rows: string[][], inputs: PanelInputs = {busy: false}): PanelModel {
    const parsed = parsePorcelain(porcelain(rows));
    const state: ReviewState = {
        situation: "review",
        state: parsed.state,
        entries: parsed.entries,
        branches: [],
    };
    // Sólo si el parser los produjo: es lo que hace que un pane sin registros
    // subject/author sea de verdad el panel con una CLI vieja, y no uno con los
    // mapas vacíos.
    if (parsed.subjects) {
        state.subjects = parsed.subjects;
    }
    if (parsed.authors) {
        state.authors = parsed.authors;
    }
    if (parsed.base !== undefined) {
        state.base = parsed.base;
    }
    return buildPanelModel(state, inputs);
}

function empty(situation: Situation, stderr?: string): PanelModel {
    const state: ReviewState = {situation, entries: [], branches: []};
    if (stderr !== undefined) {
        state.stderr = stderr;
    }
    return buildPanelModel(state, {busy: false});
}

/** `no-review` con inventario: las filas van por `list --porcelain` real. */
function inventory(rows: string[][]): PanelModel {
    const state: ReviewState = {
        situation: "no-review",
        entries: [],
        branches: parseListPorcelain(porcelain(rows)),
    };
    return buildPanelModel(state, {busy: false});
}

/**
 * `finish-pending`: HEAD ya no está en `review/*`, el inventario de
 * `list --porcelain` trae una fila `finish … pending` — el mismo camino que
 * `doRefresh` usa para pasar de `no-review` a `finish-pending`.
 */
function finishPending(rows: string[][]): PanelModel {
    const state: ReviewState = {
        situation: "finish-pending",
        entries: [],
        branches: parseListPorcelain(porcelain(rows)),
    };
    return buildPanelModel(state, {busy: false});
}

/**
 * `finish-conflict`: `status --porcelain` de una review activa más el
 * registro `finish conflict` — parser real + `buildPanelModel`, como `review()`.
 */
function finishConflict(rows: string[][]): PanelModel {
    const parsed = parsePorcelain(porcelain(rows));
    const state: ReviewState = {
        situation: "finish-conflict",
        state: parsed.state,
        entries: parsed.entries,
        branches: [],
    };
    if (parsed.subjects) {
        state.subjects = parsed.subjects;
    }
    if (parsed.authors) {
        state.authors = parsed.authors;
    }
    if (parsed.base !== undefined) {
        state.base = parsed.base;
    }
    if (parsed.finish !== undefined) {
        state.finish = parsed.finish;
    }
    return buildPanelModel(state, {busy: false});
}

/**
 * `entry` en walk: posición, path, essential, annotated. Los paths de
 * `unannotated` van al final del orden de lectura con `essential=0`,
 * `annotated=0` — el mismo lugar que les da `walk_reading_order`.
 */
function walkEntries(paths: string[], essential: number[], unannotated: string[] = []): string[][] {
    const all = [...paths, ...unannotated];
    return all.map((path, index) => [
        "entry",
        String(index + 1),
        path,
        essential.includes(index + 1) ? "1" : "0",
        unannotated.includes(path) ? "0" : "1",
    ]);
}

const WALK_PATHS = [
    "src/extension.ts",
    "src/cli/invoke.ts",
    "src/cli/porcelain.ts",
    "src/review/state.ts",
    "src/review/situation.ts",
    "src/views/panelModel.ts",
    "src/views/panelHtml.ts",
    "src/views/walkthroughViewProvider.ts",
    "src/commands/navigate.ts",
    "src/commands/openEntry.ts",
    "test/unit/panelHtml.spec.ts",
    "README.md",
];

/**
 * Un review step de cuatro commits, sin los registros de texto libre: es la
 * salida de una CLI anterior a 003, y el pane `step-legacy-cli` la usa tal cual
 * para mostrar cómo degrada el panel.
 */
const STEP_ROWS: string[][] = [
    ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "step", "none", "1", "4", "4", "a1b2c3d"],
    ["entry", "1", "a1b2c3d", "1"],
    ["entry", "2", "b2c3d4e", "0"],
    ["entry", "3", "c3d4e5f", "0"],
    ["entry", "4", "d4e5f6a", "0"],
];

/**
 * Los registros que 003 agrega. El asunto de la posición 3 es deliberadamente
 * largo: es el que muestra qué hace el panel cuando no entra en el ancho del
 * sidebar (Edge Case del spec).
 */
const STEP_TEXT_ROWS: string[][] = [
    ["subject", "1", "feat: exponer el asunto y el autor en porcelain"],
    ["subject", "2", "test: cubrir los bytes hostiles del asunto y del autor"],
    ["subject", "3", "refactor: mover la derivación de los textos al helper compartido para que el verbo no pague dos procesos por commit"],
    ["subject", "4", "docs: documentar los tres registros nuevos en los dos README"],
    ["author", "1", "Eze Villo <ezevillodev@gmail.com>"],
    ["author", "2", "Eze Villo <ezevillodev@gmail.com>"],
    ["author", "3", "Ana Muñoz <ana@example.com>"],
    ["author", "4", "Eze Villo <ezevillodev@gmail.com>"],
];

const WHY = `El HTML del panel vive aparte del provider y sin dependencia de
\`vscode\`: es lo que permite abrirlo en un navegador con un modelo de ejemplo
y verificar el render, que ninguna de las dos suites puede afirmar.`;

export const PREVIEW_PANES: PreviewPane[] = [
    {
        name: "walk",
        caption: "walk — entrada key, why presente, tres no anotadas al final del orden",
        model: review(
            [
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "walk", "applied", "7", "15", "15", WALK_PATHS[6], "1"],
                ...walkEntries(WALK_PATHS, [1, 7, 12], ["package.json", "esbuild.js", "tsconfig.json"]),
            ],
            {busy: false, why: {state: "present", text: WHY}}
        ),
    },
    {
        name: "walk-uncovered",
        caption: "walk — entrada actual sin anotar, al final del orden de lectura",
        model: review(
            [
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "walk", "applied", "13", "15", "15", "package.json", "0"],
                ...walkEntries(WALK_PATHS, [1, 7, 12], ["package.json", "esbuild.js", "tsconfig.json"]),
            ],
            {busy: false, why: {state: "absent"}}
        ),
    },
    {
        name: "walk-degraded",
        caption: "walk — walkthrough degradado, base movida, why ausente, path citado",
        model: review(
            [
                // El path va citado como lo cita git: el `display` sale del
                // unquote, así que el pane muestra si esa vuelta se rompió.
                ["state", "review/feat/docs", "feat/docs", "9f8e7d6", "walk", "degraded", "2", "5", "4", '"docs/gu\\303\\255a de uso.md"', "0"],
                ["entry", "1", "README.md", "0"],
                ["entry", "2", '"docs/gu\\303\\255a de uso.md"', "0"],
                ["entry", "3", "README.es.md", "1"],
                ["entry", "4", "docs/index.html", "0"],
                ["entry", "5", "CONTRIBUTING.md", "0"],
            ],
            {busy: false, why: {state: "absent"}}
        ),
    },
    {
        name: "step",
        caption: "step — primer commit, con ediciones bancadas, asunto y autor",
        model: review([...STEP_ROWS, ...STEP_TEXT_ROWS], {busy: false}),
    },
    {
        // El mismo review contra una CLI anterior a los registros subject/author.
        // Al lado del pane de arriba es la prueba de que degradar no deja huecos:
        // el SHA vuelve a ser el cuerpo y la línea de autor no existe (FR-003).
        name: "step-legacy-cli",
        caption: "step — misma review con una CLI que no reporta asunto ni autor",
        model: review(STEP_ROWS, {busy: false}),
    },
    {
        // Un asunto vacío es un valor legítimo, y se ve distinto de la ausencia
        // de arriba: ahí el panel no sabe el asunto, acá sabe que no hay.
        name: "step-empty-subject",
        caption: "step — commit sin asunto: la ausencia dicha, no un bloque en blanco",
        model: review(
            [
                // Cursor en 2, que es el commit sin asunto.
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "step", "none", "2", "4", "4", "b2c3d4e"],
                ...STEP_ROWS.slice(1),
                ...STEP_TEXT_ROWS.map((row) => (row[0] === "subject" && row[1] === "2" ? ["subject", "2", ""] : row)),
            ],
            {busy: false}
        ),
    },
    {
        // El pane arranca sin nada dibujado, así que el esqueleto entra de una:
        // el delay de ~120 ms sólo corre cuando hay contenido al que ahorrarle
        // el parpadeo. Dentro del editor eso es lo que se ve al navegar.
        name: "loading",
        caption: "walk — navegando: barra y controles fijos, cuerpo en carga",
        model: review(
            [
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "walk", "applied", "7", "13", "13", WALK_PATHS[6], "1"],
                ...walkEntries(WALK_PATHS, [1, 7, 12], ["package.json"]),
            ],
            {busy: true}
        ),
    },
    {
        // Sin registro `base`: el estado de una review cuyo repositorio no tiene
        // base registrada, y el que dibuja una CLI anterior a 003. En los dos
        // casos el panel no pone nada en su lugar (FR-009). El listado de
        // archivos (004) es el registro `entry`, sin campos extra en whole.
        name: "whole",
        caption: "whole — review sin walkthrough ni base registrada, con dos repos en la ventana",
        model: review(
            [
                ["state", "review/fix/quoting", "fix/quoting", "1a2b3c4", "whole", "none"],
                ["entry", "1", "README.md"],
                ["entry", "2", "src/quoting.ts"],
                ["entry", "3", "tests/quoting.spec.ts"],
            ],
            {busy: false, repoLabel: "git-review-workflow"}
        ),
    },
    {
        // La marca de la última fila abierta, que es lo que el pane de arriba no
        // muestra: en alto contraste el fondo de selección se pierde contra el
        // del panel, y ahí la barra del margen es lo único que queda.
        name: "whole-last-opened",
        caption: "whole — la misma review con la última fila abierta marcada",
        model: review(
            [
                ["state", "review/fix/quoting", "fix/quoting", "1a2b3c4", "whole", "none"],
                ["entry", "1", "README.md"],
                ["entry", "2", "src/quoting.ts"],
                ["entry", "3", "tests/quoting.spec.ts"],
            ],
            {busy: false, lastOpened: "src/quoting.ts"}
        ),
    },
    {
        name: "whole-with-base",
        caption: "whole — la misma review informando contra qué base se armó el rango",
        model: review(
            [
                ["state", "review/fix/quoting", "fix/quoting", "1a2b3c4", "whole", "none"],
                ["entry", "1", "README.md"],
                ["entry", "2", "src/quoting.ts"],
                ["entry", "3", "tests/quoting.spec.ts"],
                ["base", "main"],
            ],
            {busy: false}
        ),
    },
    {
        // Rango vacío (FR-007): cero registros entry, con el mensaje explícito en
        // vez de una lista en blanco.
        name: "whole-empty",
        caption: "whole — un rango que no toca ningún archivo",
        model: review(
            [["state", "review/no-op-merge", "no-op-merge", "9f8e7d6", "whole", "none"]],
            {busy: false}
        ),
    },
    {
        name: "no-review",
        caption: "no-review — el repo no tiene ningún review, activo ni guardado",
        model: empty("no-review"),
    },
    {
        // Las cuatro variantes de fila en un solo pane: activa (sin acción),
        // guardada resumible, guardada bloqueada por su activa gemela, y
        // huérfana. Es el pane donde se ve si el botón se deshabilita por el
        // motivo correcto.
        name: "no-review-inventory",
        caption: "no-review — con reviews abiertas en otras ramas",
        model: inventory([
            ["branch", "review/feature/checkout", "0", "0", "0", "walk", "3", "9"],
            ["branch", "review/fix/quoting", "0", "0", "0", "whole"],
            ["branch", "review/orphan", "0", "1", "1"],
            ["branch", "review-saved/perf/index", "1", "0", "0", "step", "2", "4"],
            ["branch", "review-saved/fix/quoting", "1", "0", "0", "walk", "1", "6"],
        ]),
    },
    {
        // list --porcelain con finish … pending: HEAD no está en review/*,
        // el inventario sigue ahí y el encabezado ofrece deshacer el cierre.
        name: "finish-pending",
        caption: "finish-pending — cierre completo en review-fixes, undo vivo",
        model: finishPending([
            ["branch", "review/feature/shipping", "0", "0", "0", "whole"],
            ["finish", "review/feature/shipping", "pending", "0"],
            ["branch", "review-saved/perf/index", "1", "0", "0", "step", "2", "4"],
        ]),
    },
    {
        // status --porcelain con finish conflict: la review sigue legible
        // (FR-027) pero navigationLocked retira next/prev y el banner ofrece
        // Undo / Continue.
        name: "finish-conflict",
        caption: "finish-conflict — replay detenido, banner sin navegación",
        model: finishConflict([
            ["state", "review/feature/conflict", "feature/conflict", "a1b2c3d", "step", "none", "3", "4", "4", "c3d4e5f"],
            ["finish", "conflict", "0"],
            ["entry", "1", "a1b2c3d", "1"],
            ["entry", "2", "b2c3d4e", "1"],
            ["entry", "3", "c3d4e5f", "0"],
            ["entry", "4", "d4e5f6a", "0"],
            ["subject", "1", "cf-base"],
            ["subject", "2", "cf1-touch-x"],
            ["subject", "3", "cf2-touch-a"],
            ["subject", "4", "cf3-change-x"],
            ["author", "1", "review sandbox <sandbox@example.com>"],
            ["author", "2", "review sandbox <sandbox@example.com>"],
            ["author", "3", "review sandbox <sandbox@example.com>"],
            ["author", "4", "review sandbox <sandbox@example.com>"],
        ]),
    },
    {
        name: "out-of-range",
        caption: "out-of-range — el cursor quedó fuera del rango",
        model: empty("out-of-range", "error: step 5 is out of range (4 commits)"),
    },
    {
        name: "cli-missing",
        caption: "cli-missing — la CLI no está en el PATH",
        model: empty("cli-missing", "git: 'review' is not a git command. See 'git --help'."),
    },
];
