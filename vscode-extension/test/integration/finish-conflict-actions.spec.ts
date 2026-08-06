import * as assert from "node:assert";
import * as vscode from "vscode";
import {closeAllEditors, waitForActiveTab} from "./helpers/editors";
import {getTestApi} from "./helpers/extensionApi";
import {
    createBranchWithCommits,
    FixtureRepo,
    git,
    gitReview,
    gitReviewOrThrow,
    sharedFixtureRepo,
    startReview,
    writeFile,
} from "./helpers/fixture";

/**
 * I1 (revisión de la Fase 5, fix round 1): con `situation === "finish-conflict"`
 * la review sigue legible (mode/branch/entrada; Diff y demás controles de
 * entrada en el webview) y Cancel/Finish viven como iconos de view/title, pero
 * antes de este fix los comandos (`gitReview.abortReview`,
 * `gitReview.openChange`) se negaban en silencio por un guard que sólo
 * aceptaba `"review"` — un control visible y clickeable que no hacía nada.
 * Estos tests reconstruyen el fixture de conflicto de
 * `tests/finish-state.bats`/`tests/status-porcelain.bats` (el mismo mecanismo,
 * `bin/git-review-verbs/finish:395-426`) y confirman que los dos comandos
 * ahora actúan de verdad en ese estado.
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

function reviewBranchExists(repo: FixtureRepo, branch: string): boolean {
    return git(["branch", "--list", `review/${branch}`], repo.dir).trim().length > 0;
}

/**
 * cf1 toca x.txt y una commit más tarde (cf3) vuelve a cambiarlo: el edit
 * banqueado en el paso 2 no puede reaplicarse sobre el tip una vez que finish
 * reboba todos los pasos al final, así que finish se detiene en conflicto.
 * cf2 (cfa.txt) es un edit sin superposición, para que quede algo banqueado
 * limpio además del que conflictua. Deja la review en review/<branch>, paso 3,
 * con el edit de cfa.txt vivo en el working tree y reviewresume=conflict.
 */
function buildConflictFixture(repo: FixtureRepo, branch: string): void {
    createBranchWithCommits(repo, branch, [
        {file: "x.txt", content: "X0\n", message: "cf-base"},
        {file: "x.txt", content: "X0\nX1\n", message: "cf1-touch-x"},
        {file: "cfa.txt", content: "A0\nA1\n", message: "cf2-touch-a"},
        {file: "x.txt", content: "X0\nX1-CHANGED\n", message: "cf3-change-x"},
    ]);
    // Sin checkout previo a la rama del PR: createBranchWithCommits ya deja
    // HEAD en main, y start toma "branch" como argumento explícito — igual
    // que step-mode.spec.ts. Si HEAD estuviera en la propia rama del PR al
    // correr start, reviewreturn quedaría apuntando ahí en vez de a main, y
    // el abort de más abajo "volvería" al lugar equivocado.
    startReview(repo, branch, ["--step"]);
    gitReviewOrThrow(["next"], repo.dir); // paso 2 (cf1, x.txt = X0\nX1)
    writeFile(repo, "x.txt", "X0\nX1-EDITED\n");
    gitReviewOrThrow(["next"], repo.dir); // bancea paso 2, ahora paso 3 (cf2)
    writeFile(repo, "cfa.txt", "A0\nA1-EDITED\n");

    const finish = gitReview(["finish"], repo.dir);
    assert.notStrictEqual(finish.status, 0, "el fixture de conflicto tiene que dejar finish trabado");
    assert.strictEqual(
        git(["config", `branch.review/${branch}.reviewresume`], repo.dir).trim(),
        "conflict",
        "precondicion: el fixture realmente quedo mid-conflict"
    );
}

function forceCleanup(repo: FixtureRepo, branch: string): void {
    git(["checkout", "-f", "main"], repo.dir);
    try {
        git(["branch", "-D", `review/${branch}`], repo.dir);
    } catch {
        // ya la borro abortReview, o el test nunca llego a crearla
    }
}

describe("I1 (fix round 1, 005 US3): finish-conflict deja de dejar controles mudos", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        await closeAllEditors();
    });

    it("'Cancel review' (gitReview.abortReview) tira la review entera, uno de los tres caminos del contrato", async () => {
        const branch = "i1-fix-abort";
        buildConflictFixture(repo, branch);

        try {
            const api = await getTestApi();
            const state = await api.refresh();
            assert.strictEqual(state.situation, "finish-conflict", "precondicion del fixture");

            const model = await api.getPanelModel();
            assert.strictEqual(model.navigationLocked, true, "precondicion: la navegacion sigue bloqueada");

            await withScriptedConfirm("Cancel Review", () =>
                vscode.commands.executeCommand("gitReview.abortReview")
            );

            // Antes del fix esto no invocaba nada: el guard rechazaba
            // finish-conflict y la rama sobrevivia intacta.
            assert.strictEqual(
                reviewBranchExists(repo, branch),
                false,
                "abortReview tiene que borrar review/<branch> de verdad, no quedarse mudo"
            );
            assert.strictEqual(
                git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim(),
                "main"
            );

            const after = await api.refresh();
            assert.strictEqual(after.situation, "no-review");
        } finally {
            forceCleanup(repo, branch);
        }
    });

    it("'Diff' (gitReview.openChange) abre el cambio del commit actual, no se queda mudo", async () => {
        const branch = "i1-fix-openchange";
        buildConflictFixture(repo, branch);

        try {
            const api = await getTestApi();
            const state = await api.refresh();
            assert.strictEqual(state.situation, "finish-conflict", "precondicion del fixture");

            await closeAllEditors();
            // Forma exacta con la que el panel lo dispara: sin argumento
            // (resolveEntryArg cae en la entrada de state.position).
            await vscode.commands.executeCommand("gitReview.openChange");
            const tab = await waitForActiveTab();
            assert.ok(
                tab,
                "gitReview.openChange tiene que abrir un tab en finish-conflict, no quedarse sin hacer nada"
            );
        } finally {
            forceCleanup(repo, branch);
        }
    });
});
