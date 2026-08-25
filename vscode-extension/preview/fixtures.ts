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
import {parseConfigPorcelain} from "../src/cli/configPorcelain";
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
        files: parsed.files,
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
    // Las guías llegan por el MISMO reporte dentro de una review: `status
    // --porcelain` emite los registros `guide` igual que `config --porcelain`.
    if (parsed.guides !== undefined) {
        state.guides = parsed.guides;
    }
    if (parsed.keysOnly) {
        state.keysOnly = true;
    }
    if (parsed.draft) {
        state.draft = true;
    }
    return buildPanelModel(state, inputs);
}

function empty(situation: Situation, stderr?: string): PanelModel {
    const state: ReviewState = {situation, entries: [], files: [], branches: []};
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
        files: [],
        branches: parseListPorcelain(porcelain(rows)),
    };
    return buildPanelModel(state, {busy: false});
}

/**
 * `no-review` con borradores empezados: las filas salen de los registros
 * `draft` de `config --porcelain`, por el parser real, como todo lo demás acá.
 * `rows` de inventario opcional, porque el bloque no reemplaza el cuerpo: se
 * dibuja arriba y el resto sigue entero debajo.
 */
function drafts(draftRows: string[][], inventoryRows: string[][] = []): PanelModel {
    const parsed = parseConfigPorcelain(porcelain(draftRows));
    const state: ReviewState = {
        situation: "no-review",
        entries: [],
        files: [],
        branches: parseListPorcelain(porcelain(inventoryRows)),
        config: parsed.config,
        candidates: parsed.candidates,
        remotes: parsed.remotes,
        drafts: parsed.drafts,
        guides: parsed.guides,
        ...(parsed.walkthrough !== undefined ? {walkthrough: parsed.walkthrough} : {}),
    };
    return buildPanelModel(state, {busy: false});
}

/**
 * `finish-pending`: HEAD ya no está en `review/*`, `list --porcelain` trae
 * una fila `finish … pending` — el mismo camino que `doRefresh` usa para
 * pasar de `no-review` a `finish-pending`. El panel no proyecta inventario.
 */
function finishPending(rows: string[][]): PanelModel {
    const state: ReviewState = {
        situation: "finish-pending",
        entries: [],
        files: [],
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

/** Inventario `file` del commit bajo el cursor (posición 1 en STEP_ROWS). */
const STEP_FILE_ROWS: string[][] = [
    ["file", "1", "src/cli/porcelain.ts"],
    ["file", "2", "src/views/panelModel.ts"],
    ["file", "3", "README.md"],
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
        name: "walk-draft",
        caption: "walk — el orden de lectura es el borrador del revisor, no el del PR",
        model: review(
            [
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "walk", "applied", "3", "15", "15", WALK_PATHS[2], "0"],
                ...walkEntries(WALK_PATHS, [1, 7, 12], ["package.json", "esbuild.js", "tsconfig.json"]),
                // Registro de presencia, sin campos: la única fuente del badge.
                ["draft"],
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
        caption: "step — primer commit, con ediciones bancadas, asunto, autor y archivos",
        model: review([...STEP_ROWS, ...STEP_TEXT_ROWS, ...STEP_FILE_ROWS], {
            busy: false,
            lastOpened: "src/views/panelModel.ts",
        }),
    },
    {
        // El mismo review contra una CLI anterior a los registros subject/author.
        // Al lado del pane de arriba es la prueba de que degradar no deja huecos:
        // el SHA vuelve a ser el cuerpo y la línea de autor no existe (FR-003).
        // Sin file lines: CLI que no emite el inventario de paths del commit.
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
        // Variantes de fila: activa en otra rama (hint "Still active…"),
        // guardada resumible, guardada bloqueada por su activa gemela, y
        // huérfana con Discard. Es el pane donde se ve la fila de acciones
        // debajo de la meta y el ? cuando no hay verbo.
        name: "no-review-inventory",
        caption: "no-review — inventario: acciones / hint / discard",
        model: inventory([
            ["branch", "review/feature/checkout", "0", "0", "0", "walk", "3", "9"],
            ["branch", "review/fix/quoting", "0", "0", "0", "whole"],
            ["branch", "review/orphan", "0", "1", "1"],
            ["branch", "review-saved/perf/index", "1", "0", "0", "step", "2", "4"],
            ["branch", "review-saved/fix/quoting", "1", "0", "0", "walk", "1", "6"],
        ]),
    },
    {
        // Un solo borrador empezado, sin inventario: el bloque arriba y el
        // "Start a review" de siempre debajo.
        name: "no-review-draft",
        caption: "no-review — un orden de lectura empezado (0/5)",
        model: drafts([
            ["config", "base", "develop"],
            ["config", "remote", "origin"],
            ["draft", "feature/pagos", "/repo/.git/review-walkthrough/feature/pagos.md", "0", "5", "remote", "full"],
        ]),
    },
    {
        // Tres borradores con avances distintos, más el inventario debajo: es
        // el estado donde se ve que el bloque NO reemplaza el cuerpo. La
        // segunda fila no ofrece "Validate and start" — su bloque de
        // instrucciones se borró a mano y la CLI reporta unknown, así que los
        // flags no se pueden replicar. Y la tercera está completa (1/1), que es
        // donde el énfasis pasa de "Copy for agent" a "Validate and start".
        name: "no-review-drafts",
        caption: "no-review — tres borradores (uno sin flags conocidos, uno completo) + inventario",
        model: drafts(
            [
                ["config", "base", "develop"],
                ["config", "remote", "origin"],
                ["draft", "feature/telemetry", "/repo/.git/review-walkthrough/feature/telemetry.md", "3", "9", "local", "delta"],
                ["draft", "feature/pagos", "/repo/.git/review-walkthrough/feature/pagos.md", "0", "5", "unknown", "unknown"],
                ["draft", "feature/legacy", "/repo/.git/review-walkthrough/feature/legacy.md", "1", "1", "remote", "full"],
            ],
            [["branch", "review-saved/perf/index", "1", "0", "0", "step", "2", "4"]]
        ),
    },
    {
        // Uno con su review por delante y otro con la review ya cerrada. El
        // segundo sale del bloque de arriba y baja a la sección plegada del
        // pie, con los dos iconos y sin el par con etiqueta: escribir el orden
        // y arrancar la review ya pasaron las dos.
        name: "no-review-spent-draft",
        caption: "no-review — un borrador fresco arriba y uno gastado en su sección",
        model: drafts([
            ["config", "base", "develop"],
            ["config", "remote", "origin"],
            ["draft", "feature/telemetry", "/repo/.git/review-walkthrough/feature/telemetry.md", "3", "9", "local", "delta", "fresh"],
            ["draft", "feature/pagos", "/repo/.git/review-walkthrough/feature/pagos.md", "6", "6", "remote", "full", "reviewed"],
        ]),
    },
    {
        // Dentro de una review las guías siguen estando: `walkthrough draft` se
        // corre desde adentro. Es la única sección plegable que una review tiene.
        name: "review-walk-guides",
        caption: "review walk — sección Walkthrough plegada con las dos guías",
        model: review(
            [
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "walk", "applied", "7", "15", "15", WALK_PATHS[6], "1"],
                ...walkEntries(WALK_PATHS, [1, 7, 12]),
                ["guide", "team", "/repo/.review/walkthrough-guide.md", "in-force"],
                ["guide", "own", "/repo/.git/review-walkthrough-guide.md", "absent"],
            ],
            {busy: false, why: {state: "present", text: WHY}}
        ),
    },
    {
        // Las dos guías de autoría en la sección Walkthrough del pie, cada una en
        // un estado distinto: la compartida en vigor (Open sí, Create no) y la
        // propia ausente (Create sí, Open y Discard no). Es el estado donde se ve
        // que las dos filas están siempre y sólo cambia el enabled.
        name: "no-review-guides",
        caption: "no-review — guías de autoría: la compartida en vigor, la propia sin crear",
        model: drafts([
            ["config", "base", "develop"],
            ["config", "remote", "origin"],
            ["guide", "team", "/repo/.review/walkthrough-guide.md", "in-force"],
            ["guide", "own", "/repo/.git/review-walkthrough-guide.md", "absent"],
        ]),
    },
    {
        // La otra mitad: la propia creada y todavía vacía (Open y Discard sí,
        // Create no), y la compartida que el repositorio no tiene.
        name: "no-review-guide-empty",
        caption: "no-review — guía propia creada y vacía, sin guía del repositorio",
        model: drafts([
            ["config", "base", "develop"],
            ["config", "remote", "origin"],
            ["guide", "team", "/repo/.review/walkthrough-guide.md", "absent"],
            ["guide", "own", "/repo/.git/review-walkthrough-guide.md", "empty"],
        ]),
    },
    {
        // La fila del walkthrough del autor, en el estado para el que existe: el
        // PR estaba terminado y anotado, se le siguió agregando, y dos archivos
        // nuevos todavía no tienen número. El badge sugiere mirar, no dictamina.
        name: "no-review-walkthrough-stale",
        caption: "no-review — el walkthrough puede haber quedado atrás (4/6)",
        model: drafts([
            ["config", "base", "develop"],
            ["config", "remote", "origin"],
            ["walkthrough", "stale", "/repo/.review/walkthrough.md", "4", "6"],
            ["guide", "team", "/repo/.review/walkthrough-guide.md", "absent"],
            ["guide", "own", "/repo/.git/review-walkthrough-guide.md", "absent"],
        ]),
    },
    {
        // Sin walkthrough: los dos controles de la fila apagados, y el botón de
        // la sección diciendo Init en vez de Update.
        name: "no-review-walkthrough-absent",
        caption: "no-review — la rama no tiene walkthrough todavía",
        model: drafts([
            ["config", "base", "develop"],
            ["config", "remote", "origin"],
            ["walkthrough", "absent", "/repo/.review/walkthrough.md", "0", "0"],
            ["guide", "team", "/repo/.review/walkthrough-guide.md", "absent"],
            ["guide", "own", "/repo/.git/review-walkthrough-guide.md", "absent"],
        ]),
    },
    {
        // El walkthrough de un PR que ya se mergeó: viajó a la base con el merge,
        // así que no es el orden de lectura de este PR. No quedó atrás — es de
        // otro rango — y el botón dice lo que va a pasar: empezar de cero.
        name: "no-review-walkthrough-superseded",
        caption: "no-review — el walkthrough vino con un merge, es de otro PR",
        model: drafts([
            ["config", "base", "develop"],
            ["config", "remote", "origin"],
            ["walkthrough", "superseded", "/repo/.review/walkthrough.md", "3", "3"],
            ["guide", "team", "/repo/.review/walkthrough-guide.md", "absent"],
            ["guide", "own", "/repo/.git/review-walkthrough-guide.md", "absent"],
        ]),
    },
    {
        // list --porcelain con finish … pending: pantalla de post-cierre
        // (staged edits + Clean / Undo finish), sin empty state ni inventario.
        name: "finish-pending",
        caption: "finish-pending — edits staged, Clean / Undo finish",
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
        model: empty("out-of-range", "error: HEAD has moved off this review's base — the walkthrough cursor is at entry 5 but only 4 of 9 entries remain in range. Undo them with 'git reset --soft' to restage the diff, or 'git review abort' to discard the review, then retry."),
    },
    {
        name: "cli-missing",
        caption: "cli-missing — la CLI no está en el PATH",
        model: empty("cli-missing", "git: 'review' is not a git command. See 'git --help'."),
    },
];
