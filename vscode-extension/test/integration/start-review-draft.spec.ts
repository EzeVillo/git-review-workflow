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
        assert.strictEqual(draftItem?.label, "Walkthrough — draft one");
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

    it("Continue con el borrador lleno arranca la review sobre ese orden", async () => {
        // El camino feliz entero, que hasta acá sólo estaba cubierto por partes:
        // crear → llenar → Continue → --build en verde → recorrido → start. Lo
        // que se afirma al final es la review que quedó viva y lo que el panel
        // muestra de ella, no un paso intermedio.
        //
        // El borrador se llena **por el buffer del editor y sin guardar**, que es
        // lo que hace el revisor: VS Code no autoguarda por defecto. Escribirlo
        // con fs.writeFileSync esquivaba el único paso que puede fallar acá —el
        // `--build` lee del disco— y dejaba en verde un camino que en el editor
        // real terminaba en "unfilled entries remain" con el texto a la vista.
        const branch = "us2-draft-happy";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n", "src/b.ts": "b\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const draft = draftPath(repo.dir, branch);
        let waitPrompts = 0;
        let keysAsked = 0;
        // El estado del borrador en el momento de apretar Continue: sin guardar en
        // el editor, y con el esqueleto todavía en disco. Es lo que hace que este
        // test pruebe el guardado y no lo suponga.
        let dirtyAtContinue: boolean | undefined;
        let onDiskAtContinue = "";

        const originalQuickPick = vscode.window.showQuickPick;
        const originalInfo = vscode.window.showInformationMessage;
        const originalWarning = vscode.window.showWarningMessage;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
            items: readonly (WizardItem & { keysOnly?: boolean })[]
        ) => {
            // El paso de recorrido completo vs sólo esenciales: sólo aparece
            // porque el borrador de abajo marca una entrada con "> key".
            if (items[0]?.keysOnly !== undefined) {
                keysAsked++;
                return items.find((item) => item.keysOnly === false);
            }
            if (isLayoutStep(items)) {
                return items.find((item) => item.draft === "create");
            }
            if (items[0]?.source !== undefined) {
                return items.find((item) => item.label === "Remote");
            }
            return pickCurrent(items);
        };
        (vscode.window as unknown as {
            showInformationMessage: unknown
        }).showInformationMessage = async (
            _message: string,
            ...actions: string[]
        ) => {
            if (!actions.includes("Continue")) {
                return undefined;
            }
            waitPrompts++;
            // Lo que hace el revisor mientras el aviso está a la vista: llenar el
            // borrador que la CLI acaba de escribir, en un orden propio — acá el
            // inverso del diff, para que cuál de los dos manda sea observable.
            // El documento ya está abierto (el asistente lo abrió): esto edita ese
            // buffer y lo deja sucio, sin tocar el disco.
            const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(draft));
            const whole = new vscode.Range(
                new vscode.Position(0, 0),
                doc.lineAt(doc.lineCount - 1).range.end
            );
            const edit = new vscode.WorkspaceEdit();
            edit.replace(
                doc.uri,
                whole,
                "# Walkthrough\n\n## 2. src/a.ts\nthen a\n\n## 1. src/b.ts\n> key\nstart here\n"
            );
            assert.ok(await vscode.workspace.applyEdit(edit), "no se pudo editar el borrador");
            dirtyAtContinue = doc.isDirty;
            onDiskAtContinue = fs.readFileSync(draft, "utf8");
            return "Continue";
        };
        (vscode.window as unknown as {
            showWarningMessage: unknown
        }).showWarningMessage = async () =>
            "Start the review";
        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {
                showQuickPick: unknown
            }).showQuickPick = originalQuickPick;
            (vscode.window as unknown as {
                showInformationMessage: unknown
            }).showInformationMessage =
                originalInfo;
            (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage =
                originalWarning;
        }

        assert.strictEqual(waitPrompts, 1, "el aviso de espera se mostro una vez");
        assert.strictEqual(keysAsked, 1, "el borrador marca una entrada key: se pregunta el recorrido");
        // Las dos mitades de la premisa: al apretar Continue el orden estaba
        // escrito sólo en el buffer, y en disco seguía el esqueleto sin llenar.
        // Sin esto, el test volvería a pasar por el camino que no es el del
        // revisor en cuanto alguien cambie cómo se llena el borrador.
        assert.strictEqual(dirtyAtContinue, true, "el borrador tenia que quedar sin guardar");
        assert.ok(
            onDiskAtContinue.includes("## ?. src/a.ts"),
            `en disco tenia que seguir el esqueleto: ${onDiskAtContinue}`
        );

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "walk");
        assert.strictEqual(state.draft, true, "la review lee el borrador, no el PR");
        assert.strictEqual(
            git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim(),
            `review/${branch}`
        );

        // El panel: la primera entrada es la que el revisor puso primera, y el
        // badge de borrador está puesto.
        const model = await api.getPanelModel();
        assert.strictEqual(model.draft, true);
        assert.strictEqual(model.position, 1);
        assert.strictEqual(model.total, 2);
        assert.strictEqual(model.current?.display, "src/b.ts");
        assert.strictEqual(model.current?.essential, true);

        // --build reescribió el borrador renumerando 1..N.
        assert.ok(
            fs.readFileSync(draft, "utf8").includes("## 1. src/b.ts"),
            "el borrador quedo validado y renumerado"
        );
        // Y lo que la review dejó staged es el diff del PR y nada más: el
        // borrador vive fuera del working tree, así que no puede colarse entre
        // los cambios que después extrae finish.
        const staged = git(["diff", "--cached", "--name-only"], repo.dir).trim().split("\n").sort();
        assert.deepStrictEqual(staged, ["src/a.ts", "src/b.ts"]);

        fs.rmSync(draft, {force: true});
    });

    it("descartar el aviso no cancela; Cancel vuelve atras y conserva el borrador", async () => {
        const branch = "us2-draft-cancel";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const cleanBefore = git(["status", "--porcelain"], repo.dir);
        const layoutSteps: WizardItem[][] = [];
        let waitPrompts = 0;

        const originalQuickPick = vscode.window.showQuickPick;
        const originalInfo = vscode.window.showInformationMessage;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (
            items: readonly WizardItem[]
        ) => {
            if (isLayoutStep(items)) {
                layoutSteps.push([...items]);
                // Primera vuelta: armarlo. Segunda: cortar el asistente.
                return layoutSteps.length === 1
                    ? items.find((item) => item.draft === "create")
                    : undefined;
            }
            if (items[0]?.source !== undefined) {
                return items.find((item) => item.label === "Remote");
            }
            return pickCurrent(items);
        };
        (vscode.window as unknown as {
            showInformationMessage: unknown
        }).showInformationMessage = async (
            _message: string,
            ...actions: string[]
        ) => {
            // Sólo el aviso de espera lleva acciones; las notas de la CLI no.
            if (actions.includes("Continue")) {
                waitPrompts++;
                // La primera vez se descarta la notificación (la X, o "clear all
                // notifications") sin elegir nada: eso NO es Cancel — es lo más
                // fácil de hacer sin querer mientras se edita el borrador, que es
                // justo lo que el aviso pide hacer. El aviso tiene que volver.
                return waitPrompts === 1 ? undefined : "Cancel";
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
            }).showInformationMessage =
                originalInfo;
        }

        assert.strictEqual(
            waitPrompts,
            2,
            "descartar el aviso lo vuelve a mostrar; solo Cancel sale del bucle"
        );
        const draft = draftPath(repo.dir, branch);
        assert.ok(fs.existsSync(draft), `el borrador no quedo en ${draft}`);
        assert.ok(
            fs.readFileSync(draft, "utf8").includes("src/a.ts"),
            "el esqueleto lista los archivos del rango"
        );
        // FR-003: el borrador no toca el working tree.
        assert.strictEqual(git(["status", "--porcelain"], repo.dir), cleanBefore);
        // FR-018a: Cancel devuelve al paso de forma de lectura, con el borrador
        // vivo y la oferta convertida en continuarlo.
        assert.strictEqual(layoutSteps.length, 2, "volvio al paso de forma de lectura");
        const second = layoutSteps[1];
        assert.ok(
            second.some((item) => item.draft === "resume"),
            `la segunda vuelta debe ofrecer continuarlo: ${second.map((i) => i.label).join(", ")}`
        );
        assert.ok(
            !second.some((item) => item.draft === "create"),
            "con borrador empezado no se ofrece armar otro"
        );
        // El asistente se cancelo: sin review.
        assert.strictEqual((await api.refresh()).situation, "no-review");

        fs.rmSync(draft, {force: true});
    });
});
