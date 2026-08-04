import * as assert from "node:assert";
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
    withoutBaseConfigured,
} from "./helpers/fixture";

/**
 * `gitReview.startReview` es un asistente multi-paso (dos `showQuickPick` más
 * una confirmación modal). El host de test no tiene quién le haga click, así
 * que se sustituyen esas tres funciones de `vscode.window` por respuestas
 * fijas mientras corre el comando — la misma técnica que cualquier extensión
 * usa para probar un flujo interactivo sin un usuario real del otro lado; se
 * restauran siempre, incluso si el comando lanza.
 */
async function withScriptedWizard<T>(
    pickBranch: (items: readonly { label: string; candidate?: { current: boolean } }[]) => unknown,
    layoutLabel: string,
    fn: () => Thenable<T>
): Promise<T> {
    const originalQuickPick = vscode.window.showQuickPick;
    const originalWarning = vscode.window.showWarningMessage;
    let call = 0;
    (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = async (items: readonly { label: string }[]) => {
        call++;
        if (call === 1) {
            return pickBranch(items as readonly { label: string; candidate?: { current: boolean } }[]);
        }
        return items.find((item) => item.label === layoutLabel);
    };
    (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage =
        async () => "Start the review";
    try {
        return await fn();
    } finally {
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = originalQuickPick;
        (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage = originalWarning;
    }
}

const pickCurrent = (items: readonly { candidate?: { current: boolean } }[]) =>
    items.find((item) => item.candidate?.current);

describe("US1: empezar a revisar sin escribir el comando", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    before(() => addSelfOrigin(repo));
    after(() => removeOrigin(repo));

    afterEach(async () => {
        abortReview(repo);
        withBaseConfigured(repo, "main");
    });

    it("automatico: deja la misma review que start a mano dejaria (whole, sin walkthrough)", async () => {
        const branch = "us1-auto";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        const before_ = await api.refresh();
        assert.strictEqual(before_.situation, "no-review", "precondicion: sin review activa");

        await withScriptedWizard(pickCurrent, "Automatic", () =>
            vscode.commands.executeCommand("gitReview.startReview")
        );

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.source, branch);
        assert.strictEqual(state.state?.mode, "whole", "sin walkthrough, automatico degrada a whole");
        assert.strictEqual(state.state?.branch, `review/${branch}`);
        assert.strictEqual(
            git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim(),
            `review/${branch}`
        );
    });

    it("--step: la review queda en modo step, un commit a la vez", async () => {
        const branch = "us1-step";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        await withScriptedWizard(pickCurrent, "Commit by commit", () =>
            vscode.commands.executeCommand("gitReview.startReview")
        );

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "step");
        assert.strictEqual(state.state?.position, 1);
    });

    it("ignorar el walkthrough (--no-walk): whole aunque el PR traiga uno, a diferencia de automatico", async () => {
        const branch = "us1-no-walk";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        addWalkthrough(repo, branch, [{path: "src/a.ts", why: "explica a"}]);
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        await withScriptedWizard(pickCurrent, "Ignore the walkthrough", () =>
            vscode.commands.executeCommand("gitReview.startReview")
        );

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "whole", "--no-walk fuerza whole aunque haya walkthrough");
    });

    it("el mismo PR sin --no-walk entra en walk (control: prueba que el test anterior de verdad distingue algo)", async () => {
        const branch = "us1-walk-control";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        addWalkthrough(repo, branch, [{path: "src/a.ts", why: "explica a"}]);
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        await withScriptedWizard(pickCurrent, "Automatic", () =>
            vscode.commands.executeCommand("gitReview.startReview")
        );

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "walk");
    });

    it("sin base configurada, el asistente no se abre sin resolverla primero", async () => {
        const branch = "us1-no-base";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);
        withoutBaseConfigured(repo);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");
        assert.strictEqual((await api.getPanelModel()).noBaseConfigured, true);

        // setBase (T025) usa un showQuickPick propio, sin confirmación modal:
        // un solo pick alcanza para toda la secuencia (la base, y despues rama +
        // layout siguen su curso normal).
        const originalQuickPick = vscode.window.showQuickPick;
        const originalWarning = vscode.window.showWarningMessage;
        let call = 0;
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick =
            async (items: readonly { label: string; candidate?: { name: string; current: boolean } }[]) => {
                call++;
                if (call === 1) {
                    // el paso de setBase: elegir "main" como base.
                    return items.find((item) => item.candidate?.name === "main");
                }
                if (call === 2) {
                    return items.find((item) => item.candidate?.current);
                }
                return items.find((item) => item.label === "Automatic");
            };
        (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage =
            async () => "Start the review";

        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = originalQuickPick;
            (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage = originalWarning;
        }

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.source, branch);
        assert.strictEqual(
            git(["config", "--get", "reviewworkflow.base"], repo.dir).trim(),
            "main",
            "el asistente resolvio la base inline, sin bloquear el resto del flujo"
        );
    });
});
