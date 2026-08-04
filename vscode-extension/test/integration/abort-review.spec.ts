import * as assert from "node:assert";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    createBranchWithChanges,
    git,
    sharedFixtureRepo,
    startReview,
    writeFile
} from "./helpers/fixture";

/**
 * `gitReview.abortReview` pide confirmación con un `showWarningMessage` modal
 * (continueReview.ts es el molde): el host de test no tiene quién le haga
 * click, así que se sustituye esa función de `vscode.window` por una
 * respuesta fija mientras corre el comando, igual que start-review.spec.ts.
 */
async function withScriptedConfirm<T>(answer: string | undefined, fn: () => Thenable<T>): Promise<T> {
    const original = vscode.window.showWarningMessage;
    (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage = async () => answer;
    try {
        return await fn();
    } finally {
        (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage = original;
    }
}

function reviewBranchExists(repo: { dir: string }, branch: string): boolean {
    return git(["branch", "--list", `review/${branch}`], repo.dir).trim().length > 0;
}

describe("US2 (005): salir de una review sin dejar rastro", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        abortReview(repo);
    });

    it("confirmar cancela la review y deja el repositorio como antes de start (T031)", async () => {
        const branch = "us2-abort-confirm";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});

        const api = await getTestApi();
        startReview(repo, branch);
        let state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.branch, `review/${branch}`);

        // El `reviewreturn` que la CLI registró al iniciar, leído ANTES de que
        // la rama de review se borre — es contra eso, no contra un valor
        // hardcodeado, que se compara adonde vuelve HEAD.
        const expectedReturn = git(["config", `branch.review/${branch}.reviewreturn`], repo.dir).trim();
        assert.strictEqual(expectedReturn, "main", "precondicion: reviewreturn registrado por start");

        // Ediciones sin commitear sobre el working tree de la review: lo que
        // el diálogo de confirmación advierte que se descarta.
        writeFile(repo, "src/a.ts", "a\nedited without committing\n");

        await withScriptedConfirm("Cancel Review", () =>
            vscode.commands.executeCommand("gitReview.abortReview")
        );

        assert.strictEqual(reviewBranchExists(repo, branch), false, "review/<branch> debe haber sido borrada");
        assert.strictEqual(
            git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim(),
            expectedReturn,
            "HEAD debe volver a la rama registrada en reviewreturn"
        );

        state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
    });

    it("descartar la confirmacion no invoca abort (T032)", async () => {
        const branch = "us2-abort-dismiss";
        createBranchWithChanges(repo, branch, {"src/b.ts": "b\n"});

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");

        // `showWarningMessage` devuelve `undefined`, como cuando el revisor
        // cierra el modal sin elegir nada.
        await withScriptedConfirm(undefined, () =>
            vscode.commands.executeCommand("gitReview.abortReview")
        );

        assert.strictEqual(reviewBranchExists(repo, branch), true, "review/<branch> no debe borrarse si se descarta la confirmacion");
        assert.strictEqual(
            git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim(),
            `review/${branch}`,
            "HEAD no debe moverse si se descarta la confirmacion"
        );

        const afterState = await api.refresh();
        assert.strictEqual(afterState.situation, "review", "la review sigue activa tras descartar");
        // La limpieza real corre en afterEach (abortReview(repo)): este test
        // necesitaba la rama viva hasta acá para afirmar que no se tocó.
    });
});
