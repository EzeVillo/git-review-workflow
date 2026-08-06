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
 * Ítem de QuickPick del asistente, con los discriminadores que `startReview.ts`
 * cuelga en cada paso (layout / source / range / candidate).
 */
interface WizardItem {
    label: string;
    candidate?: {name?: string; current?: boolean};
    layout?: string;
    source?: string;
    range?: string;
}

/**
 * `gitReview.startReview` es un asistente multi-paso (rama → forma de lectura →
 * origen → rango si hay delta, más confirmación modal). El host de test no tiene
 * quién le haga click, así que se sustituyen `showQuickPick` /
 * `showWarningMessage` por respuestas fijas mientras corre el comando; se
 * restauran siempre, incluso si el comando lanza.
 *
 * Cada paso se reconoce por la forma del ítem (no por el orden de llamadas): el
 * origen se elige **siempre**, y el rango sólo aparece cuando la CLI reporta
 * delta — un contador de llamadas se rompería en cuanto haya o no haya ese paso.
 */
async function withScriptedWizard<T>(
    pickBranch: (items: readonly WizardItem[]) => unknown,
    layoutLabel: string,
    fn: () => Thenable<T>,
    opts: {sourceLabel?: string; rangeLabel?: string} = {}
): Promise<T> {
    const sourceLabel = opts.sourceLabel ?? "Remote";
    const rangeLabel = opts.rangeLabel ?? "Full range";
    const originalQuickPick = vscode.window.showQuickPick;
    const originalWarning = vscode.window.showWarningMessage;
    (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = async (
        items: readonly WizardItem[]
    ) => {
        const sample = items[0];
        if (sample?.layout !== undefined) {
            return items.find((item) => item.label === layoutLabel);
        }
        if (sample?.source !== undefined) {
            return items.find((item) => item.label === sourceLabel);
        }
        if (sample?.range !== undefined) {
            return items.find((item) => item.label === rangeLabel);
        }
        return pickBranch(items);
    };
    (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = async () =>
        "Start the review";
    try {
        return await fn();
    } finally {
        (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = originalQuickPick;
        (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage =
            originalWarning;
    }
}

const pickCurrent = (items: readonly WizardItem[]) =>
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

    it("el asistente pide origen despues del layout (no hay More options ni re-pregunta de layout)", async () => {
        const branch = "us1-source-step";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");

        const originalQuickPick = vscode.window.showQuickPick;
        const originalWarning = vscode.window.showWarningMessage;
        const stepKinds: string[] = [];
        (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = async (
            items: readonly WizardItem[]
        ) => {
            const sample = items[0];
            if (sample?.layout !== undefined) {
                stepKinds.push("layout");
                assert.ok(
                    !items.some((item) => item.label.startsWith("More options")),
                    "More options no debe aparecer en el paso de layout"
                );
                return items.find((item) => item.label === "Automatic");
            }
            if (sample?.source !== undefined) {
                stepKinds.push("source");
                return items.find((item) => item.label === "Local");
            }
            if (sample?.range !== undefined) {
                stepKinds.push("range");
                return items.find((item) => item.label === "Full range");
            }
            stepKinds.push("branch");
            return pickCurrent(items);
        };
        (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = async () =>
            "Start the review";

        try {
            await vscode.commands.executeCommand("gitReview.startReview");
        } finally {
            (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = originalQuickPick;
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage =
                originalWarning;
        }

        assert.deepStrictEqual(
            stepKinds.filter((k) => k === "layout"),
            ["layout"],
            "layout se elige una sola vez"
        );
        assert.ok(stepKinds.includes("source"), "origen se pide siempre, no detras de More options");
        // Sin review previa de esta rama no hay registro delta: el rango no se ofrece.
        assert.ok(!stepKinds.includes("range"), "sin delta no se ofrece el paso de rango");

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.source, branch);
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
        // se reconoce por candidate sin layout/source/range; el primer pick de
        // ese tipo es la base, el segundo la rama a revisar.
        let basePicked = false;
        await withScriptedWizard(
            (items) => {
                if (!basePicked) {
                    basePicked = true;
                    return items.find((item) => item.candidate?.name === "main");
                }
                return items.find((item) => item.candidate?.current);
            },
            "Automatic",
            () => vscode.commands.executeCommand("gitReview.startReview")
        );

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
