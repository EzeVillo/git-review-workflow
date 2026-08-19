import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    addSelfOrigin,
    addWalkthrough,
    createBranchWithChanges,
    git,
    removeOrigin,
    sharedFixtureRepo,
    withBaseConfigured,
} from "./helpers/fixture";

/**
 * US2 (011): el asistente ofrece armarse el orden de lectura cuando el PR no
 * trae uno, y **no** lo ofrece cuando sí — reemplazar el walkthrough del autor
 * no es algo que el asistente proponga.
 *
 * Lo que se afirma es la superficie que el revisor ve (los ítems del paso de
 * forma de lectura) y el efecto real sobre el disco (el borrador escrito bajo
 * el gitdir, fuera del working tree). La viabilidad la decide la CLI: acá se
 * verifica que llega y que el bucle la usa.
 */
interface WizardItem {
    label: string;
    candidate?: { name?: string; current?: boolean };
    layout?: string;
    draft?: string;
    source?: string;
    range?: string;
}

/** Los ítems del paso de forma de lectura, tal como los ve el revisor. */
function isLayoutStep(items: readonly WizardItem[]): boolean {
    return items[0]?.layout !== undefined;
}

const pickCurrent = (items: readonly WizardItem[]) =>
    items.find((item) => item.candidate?.current);

function draftPath(repoDir: string, branch: string): string {
    return path.join(repoDir, ".git", "review-walkthrough", `${branch}.md`);
}

describe("US2: el asistente ofrece armar el orden de lectura", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    before(() => addSelfOrigin(repo));
    after(() => removeOrigin(repo));

    afterEach(async () => {
        abortReview(repo);
        withBaseConfigured(repo, "main");
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    });

    it("sobre un PR sin walkthrough ofrece armar el borrador", async () => {
        const branch = "us2-draft-offered";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const layoutSteps: WizardItem[][] = [];
        const originalQuickPick = vscode.window.showQuickPick;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
            items: readonly WizardItem[]
        ) => {
            if (isLayoutStep(items)) {
                layoutSteps.push([...items]);
                return undefined; // cancela el asistente: nada que deshacer
            }
            if (items[0]?.source !== undefined) {
                return items.find((item) => item.label === "Remote");
            }
            return pickCurrent(items);
        };
        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {
                showQuickPick: unknown
            }).showQuickPick = originalQuickPick;
        }

        assert.strictEqual(layoutSteps.length, 1, "el asistente llego al paso de forma de lectura");
        const offered = layoutSteps[0];
        const draftItem = offered.find((item) => item.draft === "create");
        assert.ok(draftItem, `no se ofrecio armar el borrador: ${offered.map((i) => i.label).join(", ")}`);
        assert.strictEqual(draftItem?.label, "Build a reading order first");
        assert.ok(
            !offered.some((item) => item.draft === "resume"),
            "sin borrador empezado no hay nada que continuar"
        );
        // El asistente cancelado no deja nada: ni review, ni borrador.
        assert.strictEqual((await api.refresh()).situation, "no-review");
        assert.strictEqual(fs.existsSync(draftPath(repo.dir, branch)), false);
    });

    it("sobre un PR con walkthrough del autor no ofrece reemplazarlo", async () => {
        const branch = "us2-draft-not-offered";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        addWalkthrough(repo, branch, [{path: "src/a.ts", why: "explica a"}]);
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const layoutSteps: WizardItem[][] = [];
        const originalQuickPick = vscode.window.showQuickPick;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
            items: readonly WizardItem[]
        ) => {
            if (isLayoutStep(items)) {
                layoutSteps.push([...items]);
                return undefined;
            }
            if (items[0]?.source !== undefined) {
                return items.find((item) => item.label === "Remote");
            }
            return pickCurrent(items);
        };
        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {
                showQuickPick: unknown
            }).showQuickPick = originalQuickPick;
        }

        assert.strictEqual(layoutSteps.length, 1);
        const offered = layoutSteps[0];
        assert.ok(
            offered.some((item) => item.layout === "walk" && item.draft === undefined),
            "el walkthrough del autor sigue ofreciendose"
        );
        assert.ok(
            !offered.some((item) => item.draft !== undefined),
            `no debe ofrecer armar ni continuar un borrador: ${offered.map((i) => i.label).join(", ")}`
        );
    });

    it("elegir armar el orden lo crea y CIERRA el asistente, sin dejar ningun aviso", async () => {
        // US4 / SC-010. Lo que reemplaza al bucle de espera de 011: el
        // asistente crea el borrador y termina. No abre el archivo (en ese
        // instante todavia no hay registro `draft` que traiga su ruta, y
        // armarla es justo lo que esta feature retira), no arranca ninguna
        // review, y no deja una notificacion esperando a que alguien la
        // conteste. La continuacion vive en el panel.
        const branch = "us4-wizard-ends";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n", "src/b.ts": "b\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const cleanBefore = git(["status", "--porcelain"], repo.dir);
        const layoutSteps: WizardItem[][] = [];
        // Cualquier mensaje CON acciones es un aviso que espera una respuesta:
        // es exactamente lo que ya no puede haber.
        let promptsWithActions = 0;
        let keysAsked = 0;

        const originalQuickPick = vscode.window.showQuickPick;
        const originalInfo = vscode.window.showInformationMessage;
        const originalWarning = vscode.window.showWarningMessage;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
            items: readonly (WizardItem & { keysOnly?: boolean })[]
        ) => {
            if (items[0]?.keysOnly !== undefined) {
                keysAsked++;
                return items.find((item) => item.keysOnly === false);
            }
            if (isLayoutStep(items)) {
                layoutSteps.push([...items]);
                return items.find((item) => item.draft === "create");
            }
            if (items[0]?.source !== undefined) {
                return items.find((item) => item.label === "Remote");
            }
            return pickCurrent(items);
        };
        (vscode.window as unknown as {
            showInformationMessage: unknown
        }).showInformationMessage = async (_message: string, ...actions: string[]) => {
            if (actions.length > 0) {
                promptsWithActions++;
            }
            return undefined;
        };
        (vscode.window as unknown as {
            showWarningMessage: unknown
        }).showWarningMessage = async (_message: string, ...rest: unknown[]) => {
            // Un modal de confirmacion tambien seria una espera: el asistente ya
            // no llega a confirmar nada.
            if (rest.length > 0) {
                promptsWithActions++;
            }
            return undefined;
        };
        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {
                showQuickPick: unknown
            }).showQuickPick = originalQuickPick;
            (vscode.window as unknown as {
                showInformationMessage: unknown
            }).showInformationMessage = originalInfo;
            (vscode.window as unknown as {
                showWarningMessage: unknown
            }).showWarningMessage = originalWarning;
        }

        // El asistente paso una sola vez por la forma de lectura y no volvio.
        assert.strictEqual(layoutSteps.length, 1);
        assert.strictEqual(promptsWithActions, 0, "no puede quedar ningun aviso esperando");
        assert.strictEqual(keysAsked, 0, "el recorrido se elige en el panel, no aca");

        // El borrador quedo escrito, fuera del working tree.
        const draft = draftPath(repo.dir, branch);
        assert.ok(fs.existsSync(draft), `el borrador no quedo en ${draft}`);
        assert.ok(fs.readFileSync(draft, "utf8").includes("src/a.ts"));
        assert.strictEqual(git(["status", "--porcelain"], repo.dir), cleanBefore);

        // Y no se arranco ninguna review.
        const state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        assert.strictEqual(
            git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim(),
            branch
        );

        // El asistente tampoco lo abrio: la ruta llega por el refresco, y el
        // revisor abre desde el panel con Open.
        assert.ok(
            !vscode.window.visibleTextEditors.some((editor) =>
                editor.document.uri.fsPath.includes("review-walkthrough")
            ),
            "el asistente no abre el borrador"
        );

        fs.rmSync(draft, {force: true});
    });

    it("con el borrador ya empezado, draft-resume no lo recrea ni pisa nada", async () => {
        // FR-018a: volver al asistente con un borrador a medio escribir ofrece
        // continuarlo, y elegir esa oferta no vuelve a crear el archivo — eso
        // borraria lo escrito, que es lo que --force existe para pedir a mano.
        const branch = "us4-draft-resume";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const draft = draftPath(repo.dir, branch);
        const layoutSteps: WizardItem[][] = [];
        const originalQuickPick = vscode.window.showQuickPick;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
            items: readonly WizardItem[]
        ) => {
            if (isLayoutStep(items)) {
                layoutSteps.push([...items]);
                const wanted = layoutSteps.length === 1 ? "create" : "resume";
                return items.find((item) => item.draft === wanted);
            }
            if (items[0]?.source !== undefined) {
                return items.find((item) => item.label === "Remote");
            }
            return pickCurrent(items);
        };
        try {
            await vscode.commands.executeCommand("gitReview.startReview");
            assert.ok(fs.existsSync(draft));
            // Lo que el revisor escribio, que la segunda vuelta no puede tocar.
            fs.writeFileSync(draft, "# Walkthrough\n\n## 1. src/a.ts\nmine\n", "utf8");
            await api.refresh();
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {
                showQuickPick: unknown
            }).showQuickPick = originalQuickPick;
        }

        assert.strictEqual(layoutSteps.length, 2);
        assert.ok(
            layoutSteps[1].some((item) => item.draft === "resume"),
            `la segunda vuelta ofrece continuarlo: ${layoutSteps[1].map((i) => i.label).join(", ")}`
        );
        assert.ok(
            !layoutSteps[1].some((item) => item.draft === "create"),
            "con borrador empezado no se ofrece armar otro"
        );
        assert.strictEqual(
            fs.readFileSync(draft, "utf8"),
            "# Walkthrough\n\n## 1. src/a.ts\nmine\n",
            "resume no puede recrear el borrador"
        );
        assert.strictEqual((await api.refresh()).situation, "no-review");

        fs.rmSync(draft, {force: true});
    });

    it("si la creacion falla vuelve al paso de forma de lectura, sin rehacer la rama", async () => {
        // US4 escenario 3. El fallo se fuerza dejando el nombre del borrador
        // ocupado por un DIRECTORIO: la CLI no puede escribir el archivo ahi, y
        // el asistente tiene que decir por que y volver, no cortarse.
        const branch = "us4-create-fails";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const draft = draftPath(repo.dir, branch);
        fs.mkdirSync(draft, {recursive: true});

        const layoutSteps: WizardItem[][] = [];
        const branchSteps: WizardItem[][] = [];
        const errors: string[] = [];
        const originalQuickPick = vscode.window.showQuickPick;
        const originalError = vscode.window.showErrorMessage;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
            items: readonly WizardItem[]
        ) => {
            if (isLayoutStep(items)) {
                layoutSteps.push([...items]);
                // Primera vuelta: intentar armarlo. Segunda: salir.
                return layoutSteps.length === 1
                    ? items.find((item) => item.draft === "create")
                    : undefined;
            }
            if (items[0]?.source !== undefined) {
                return items.find((item) => item.label === "Remote");
            }
            branchSteps.push([...items]);
            return pickCurrent(items);
        };
        (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = async (
            message: string
        ) => {
            errors.push(message);
            return undefined;
        };
        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {
                showQuickPick: unknown
            }).showQuickPick = originalQuickPick;
            (vscode.window as unknown as {
                showErrorMessage: unknown
            }).showErrorMessage = originalError;
        }

        assert.strictEqual(errors.length, 1, `un error, con el motivo de la CLI: ${errors.join(" | ")}`);
        assert.ok(errors[0].length > 0);
        // Volvio a la forma de lectura, no al principio: la rama se eligio una vez.
        assert.strictEqual(layoutSteps.length, 2, "volvio al paso de forma de lectura");
        assert.strictEqual(branchSteps.length, 1, "la eleccion de rama no se rehizo");
        assert.strictEqual((await api.refresh()).situation, "no-review");

        fs.rmSync(draft, {recursive: true, force: true});
    });
});
