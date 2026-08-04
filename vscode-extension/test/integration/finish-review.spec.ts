import * as assert from "node:assert";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    createBranchWithChanges,
    git,
    gitReviewOrThrow,
    sharedFixtureRepo,
    startReview,
    writeFile,
} from "./helpers/fixture";

/**
 * `gitReview.finishReview` abre un `QuickPick` de ubicación (finishReview.ts):
 * el host de test no tiene quién le haga click, así que se sustituye
 * `showQuickPick` por una respuesta fija — misma técnica que
 * start-review.spec.ts/abort-review.spec.ts — y además se capturan los
 * mensajes que el comando muestra, para afirmar T050/FR-019 ("sin ediciones"
 * se informa como resultado normal, nunca como error).
 */
async function withScriptedPick<T>(
    pickLabel: string | undefined,
    fn: () => Thenable<T>
): Promise<{ result: T; infos: string[]; errors: string[] }> {
    const originalPick = vscode.window.showQuickPick;
    const originalInfo = vscode.window.showInformationMessage;
    const originalError = vscode.window.showErrorMessage;
    const infos: string[] = [];
    const errors: string[] = [];
    (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick =
        async (items: readonly { label: string }[]) =>
            pickLabel === undefined ? undefined : items.find((item) => item.label === pickLabel);
    (vscode.window as unknown as { showInformationMessage: unknown }).showInformationMessage =
        async (msg: string) => {
            infos.push(msg);
            return undefined;
        };
    (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = async (msg: string) => {
        errors.push(msg);
        return undefined;
    };
    try {
        const result = await fn();
        return {result, infos, errors};
    } finally {
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = originalPick;
        (vscode.window as unknown as { showInformationMessage: unknown }).showInformationMessage = originalInfo;
        (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = originalError;
    }
}

function reviewBranchExists(repo: { dir: string }, branch: string): boolean {
    return git(["branch", "--list", `review/${branch}`], repo.dir).trim().length > 0;
}

function headBranch(repo: { dir: string }): string {
    return git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim();
}

function listPorcelain(repo: { dir: string }): string {
    return gitReviewOrThrow(["list", "--porcelain"], repo.dir).stdout;
}

const FINISH_TEST_BRANCHES = ["us3-finish-branch", "us3-finish-onto", "us3-finish-no-edits", "us3-finish-dismiss"];

function tryDelete(repo: { dir: string }, ref: string): void {
    try {
        git(["branch", "-D", ref], repo.dir);
    } catch {
        // no existe en esta corrida (p. ej. review-fixes/<x> sólo lo crea la
        // variante "separate branch") — nada que borrar.
    }
}

describe("US3 (005): quedarse con las ediciones al terminar", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        // abortReview() del helper compartido asume que HEAD está en review/*
        // o ya limpio; acá un finish exitoso lo deja en review-fixes/<x> o en
        // la propia rama del PR, ninguno de los dos abortable — así que la
        // limpieza es propia: forzar la vuelta a main (descartando lo que
        // haga falta) ANTES de borrar las ramas que finish deja atrás, para
        // que el repositorio compartido quede sin ningún review/* colgado
        // (otras specs de esta suite —empty-states.spec.ts— asumen que arranca
        // sin ninguno).
        git(["checkout", "-f", "main"], repo.dir);
        for (const b of FINISH_TEST_BRANCHES) {
            tryDelete(repo, `review/${b}`);
            tryDelete(repo, `review-fixes/${b}`);
        }
    });

    it("elegir 'A separate branch' deja las ediciones en review-fixes/<branch>, con un cierre pending onto=0 (T053)", async () => {
        const branch = "us3-finish-branch";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        let state = await api.refresh();
        assert.strictEqual(state.situation, "review");

        writeFile(repo, "src/a.ts", "a\nedited\n");

        const {infos, errors} = await withScriptedPick("A separate branch", () =>
            vscode.commands.executeCommand("gitReview.finishReview")
        );
        assert.deepStrictEqual(errors, [], "un finish que completa no debe mostrar ningun error");
        assert.ok(infos.length > 0, "se informa el resultado");

        assert.strictEqual(headBranch(repo), `review-fixes/${branch}`);
        const staged = git(["diff", "--cached"], repo.dir);
        assert.ok(staged.includes("edited"), "las ediciones quedan staged en review-fixes/<branch>");

        // El mismo efecto que dejaria `git review finish` a mano: review/<src>
        // sigue existiendo con un cierre pending, onto 0 (sin --onto-source).
        const finishLine = listPorcelain(repo)
            .split("\n")
            .find((l) => l.startsWith(`finish\treview/${branch}\t`));
        assert.strictEqual(finishLine, `finish\treview/${branch}\tpending\t0`);

        state = await api.refresh();
        assert.strictEqual(state.situation, "finish-pending");
        const model = await api.getPanelModel();
        assert.deepStrictEqual(model.pendingFinish, {branch: `review/${branch}`, onto: false});
    });

    it("elegir 'Onto the PR branch itself' deja las ediciones sobre la rama del PR, con onto=1 (T053)", async () => {
        const branch = "us3-finish-onto";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        assert.strictEqual((await api.refresh()).situation, "review");

        writeFile(repo, "src/a.ts", "a\nedited-onto\n");

        const {errors} = await withScriptedPick("Onto the PR branch itself", () =>
            vscode.commands.executeCommand("gitReview.finishReview")
        );
        assert.deepStrictEqual(errors, []);

        assert.strictEqual(headBranch(repo), branch, "HEAD queda en la rama del PR, no en review-fixes");
        const staged = git(["diff", "--cached"], repo.dir);
        assert.ok(staged.includes("edited-onto"));

        const finishLine = listPorcelain(repo)
            .split("\n")
            .find((l) => l.startsWith(`finish\treview/${branch}\t`));
        assert.strictEqual(finishLine, `finish\treview/${branch}\tpending\t1`);

        const model = await api.getPanelModel();
        assert.deepStrictEqual(model.pendingFinish, {branch: `review/${branch}`, onto: true});
    });

    it("sin ediciones que extraer, se informa como resultado normal, nunca como error (T050/FR-019)", async () => {
        const branch = "us3-finish-no-edits";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        assert.strictEqual((await api.refresh()).situation, "review");
        // Ninguna edicion sobre el diff que start dejo staged.

        const {infos, errors} = await withScriptedPick("A separate branch", () =>
            vscode.commands.executeCommand("gitReview.finishReview")
        );
        assert.deepStrictEqual(errors, [], "sin ediciones no es un error");
        assert.ok(infos.length > 0, "se informa igual, como resultado normal");

        // Sin ediciones, finish nunca deja un punto de undo (no hay nada que
        // deshacer) y HEAD se queda en review/<branch> — la senal que
        // finishOutcome lee es justamente esta ausencia.
        const finishLine = listPorcelain(repo)
            .split("\n")
            .find((l) => l.startsWith(`finish\treview/${branch}\t`));
        assert.strictEqual(finishLine, undefined, "sin ediciones no queda ningun cierre pendiente");

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review", "la review sigue activa: no hubo nada que cerrar");
    });

    it("descartar el QuickPick de ubicacion no invoca finish (FR-030)", async () => {
        const branch = "us3-finish-dismiss";
        createBranchWithChanges(repo, branch, {"src/b.ts": "b\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        assert.strictEqual((await api.refresh()).situation, "review");
        writeFile(repo, "src/b.ts", "b\nedited\n");

        await withScriptedPick(undefined, () => vscode.commands.executeCommand("gitReview.finishReview"));

        assert.strictEqual(reviewBranchExists(repo, branch), true, "review/<branch> sigue activa");
        assert.strictEqual(headBranch(repo), `review/${branch}`, "HEAD no se movio");
        const finishLine = listPorcelain(repo)
            .split("\n")
            .find((l) => l.startsWith(`finish\treview/${branch}\t`));
        assert.strictEqual(finishLine, undefined, "descartar el picker no deja ningun cierre pendiente");

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
    });
});
