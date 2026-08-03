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
import {parsePorcelain} from "../src/cli/porcelain";
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
        uncovered: parsed.uncovered,
    };
    return buildPanelModel(state, inputs);
}

function empty(situation: Situation, stderr?: string): PanelModel {
    const state: ReviewState = {situation, entries: [], uncovered: []};
    if (stderr !== undefined) {
        state.stderr = stderr;
    }
    return buildPanelModel(state, {busy: false});
}

/** `entry` en walk: posición, path, essential. */
function walkEntries(paths: string[], essential: number[]): string[][] {
    return paths.map((path, index) => [
        "entry",
        String(index + 1),
        path,
        essential.includes(index + 1) ? "1" : "0",
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

const WHY = `El HTML del panel vive aparte del provider y sin dependencia de
\`vscode\`: es lo que permite abrirlo en un navegador con un modelo de ejemplo
y verificar el render, que ninguna de las dos suites puede afirmar.`;

export const PREVIEW_PANES: PreviewPane[] = [
    {
        name: "walk",
        caption: "walk — entrada key, why presente, uncovered en el pie",
        model: review(
            [
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "walk", "applied", "7", "12", "12", WALK_PATHS[6], "1"],
                ...walkEntries(WALK_PATHS, [1, 7, 12]),
                ["uncovered", "package.json"],
                ["uncovered", "esbuild.js"],
                ["uncovered", "tsconfig.json"],
            ],
            {busy: false, why: {state: "present", text: WHY}}
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
        caption: "step — primer commit, con ediciones bancadas",
        model: review(
            [
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "step", "none", "1", "4", "4", "a1b2c3d"],
                ["entry", "1", "a1b2c3d", "1"],
                ["entry", "2", "b2c3d4e", "0"],
                ["entry", "3", "c3d4e5f", "0"],
                ["entry", "4", "d4e5f6a", "0"],
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
                ["state", "review/feat/panel", "feat/panel", "a1b2c3d", "walk", "applied", "7", "12", "12", WALK_PATHS[6], "1"],
                ...walkEntries(WALK_PATHS, [1, 7, 12]),
                ["uncovered", "package.json"],
            ],
            {busy: true}
        ),
    },
    {
        name: "whole",
        caption: "whole — review sin walkthrough, con dos repos en la ventana",
        model: review(
            [["state", "review/fix/quoting", "fix/quoting", "1a2b3c4", "whole", "none"]],
            {busy: false, repoLabel: "git-review-workflow"}
        ),
    },
    {
        name: "no-review",
        caption: "no-review — el repo no tiene un review activo",
        model: empty("no-review"),
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
