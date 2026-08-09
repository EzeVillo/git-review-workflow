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
    candidate?: {name?: string; current?: boolean};
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
        (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = async (
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
            (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = originalQuickPick;
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
        (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = async (
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
            (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = originalQuickPick;
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

    it("elegir armarlo crea el borrador fuera del working tree, y Cancel lo conserva", async () => {
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
        (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = async (
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
        (vscode.window as unknown as {showInformationMessage: unknown}).showInformationMessage = async (
            _message: string,
            ...actions: string[]
        ) => {
            // Sólo el aviso de espera lleva acciones; las notas de la CLI no.
            if (actions.includes("Continue")) {
                waitPrompts++;
                return "Cancel";
            }
            return undefined;
        };
        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = originalQuickPick;
            (vscode.window as unknown as {showInformationMessage: unknown}).showInformationMessage =
                originalInfo;
        }

        assert.strictEqual(waitPrompts, 1, "el aviso de espera se mostro una vez");
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
