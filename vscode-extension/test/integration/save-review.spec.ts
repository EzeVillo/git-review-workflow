import * as assert from "node:assert";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    createBranchWithChanges,
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
 * `gitReview.saveReview` pide confirmacion con un `showWarningMessage` modal
 * (abortReview.ts es el molde): el host de test no tiene quien le haga click,
 * asi que se sustituye esa funcion de `vscode.window` por una respuesta fija
 * mientras corre el comando, igual que abort-review.spec.ts.
 *
 * Tambien captura `showErrorMessage` para afirmar el diagnostico de la CLI
 * cuando el save se niega (T063).
 */
async function withScriptedConfirm<T>(
    answer: string | undefined,
    fn: () => Thenable<T>
): Promise<{ result: T; errors: string[] }> {
    const originalWarn = vscode.window.showWarningMessage;
    const originalError = vscode.window.showErrorMessage;
    const errors: string[] = [];
    (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage = async () => answer;
    (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = async (msg: string) => {
        errors.push(msg);
        return undefined;
    };
    try {
        const result = await fn();
        return {result, errors};
    } finally {
        (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage = originalWarn;
        (vscode.window as unknown as { showErrorMessage: unknown }).showErrorMessage = originalError;
    }
}

function headBranch(repo: { dir: string }): string {
    return git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim();
}

function branchExists(repo: { dir: string }, name: string): boolean {
    return git(["branch", "--list", name], repo.dir).trim().length > 0;
}

function listPorcelain(repo: { dir: string }): string {
    return gitReviewOrThrow(["list", "--porcelain"], repo.dir).stdout;
}

function savedLine(repo: { dir: string }, source: string): string | undefined {
    return listPorcelain(repo)
        .split("\n")
        .find((l) => l.startsWith(`branch\treview-saved/${source}\t`));
}

function tryDelete(repo: { dir: string }, ref: string): void {
    try {
        git(["branch", "-D", ref], repo.dir);
    } catch {
        // no existe en esta corrida
    }
}

function forceCleanup(repo: FixtureRepo, branch: string): void {
    git(["checkout", "-f", "main"], repo.dir);
    // forget --saved es el camino limpio; si la rama no esta, no molesta
    gitReview(["forget", "--saved", branch], repo.dir);
    tryDelete(repo, `review/${branch}`);
    tryDelete(repo, `review-saved/${branch}`);
    tryDelete(repo, branch);
}

const SAVE_TEST_BRANCHES = [
    "us5-save-whole",
    "us5-save-step",
    "us5-save-dismiss",
    "us5-save-collision",
];

describe("US5 (005): dejar la review a un lado", function () {
    this.timeout(90000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        git(["checkout", "-f", "main"], repo.dir);
        for (const b of SAVE_TEST_BRANCHES) {
            gitReview(["forget", "--saved", b], repo.dir);
            tryDelete(repo, `review/${b}`);
            tryDelete(repo, `review-saved/${b}`);
            // abort tolerante por si HEAD quedo en review/*
            abortReview(repo);
            tryDelete(repo, b);
        }
    });

    it("confirmar en whole pausa la review: review-saved existe, HEAD vuelve, list la reporta saved (T062)", async () => {
        const branch = "us5-save-whole";
        // createBranchWithChanges deja HEAD en main: start desde ahi registra
        // reviewreturn=main (igual que abort-review.spec.ts).
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});

        const api = await getTestApi();
        startReview(repo, branch);
        let state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "whole");

        const expectedReturn = git(["config", `branch.review/${branch}.reviewreturn`], repo.dir).trim();
        assert.strictEqual(expectedReturn, "main", "precondicion: reviewreturn registrado por start");

        writeFile(repo, "src/a.ts", "a\nWHOLE-EDIT\n");

        const {errors} = await withScriptedConfirm("Save for Later", () =>
            vscode.commands.executeCommand("gitReview.saveReview")
        );
        assert.deepStrictEqual(errors, [], "un save que completa no debe mostrar ningun error");

        assert.strictEqual(
            branchExists(repo, `review/${branch}`),
            false,
            "review/<branch> debe haber sido renombrada a review-saved"
        );
        assert.strictEqual(
            branchExists(repo, `review-saved/${branch}`),
            true,
            "review-saved/<branch> tiene que existir"
        );
        assert.strictEqual(headBranch(repo), expectedReturn, "HEAD debe volver a la rama de origen");

        const line = savedLine(repo, branch);
        assert.ok(line !== undefined, "list --porcelain tiene que reportar la guardada");
        // branch\treview-saved/<src>\t1\t0\t0\twhole  (saved=1, current=0, orphan=0)
        assert.strictEqual(line, `branch\treview-saved/${branch}\t1\t0\t0\twhole`);

        state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        assert.ok(
            state.branches.some((b) => b.name === `review-saved/${branch}` && b.saved === true && b.mode === "whole"),
            "el inventario del host ve la review pausada"
        );
    });

    it("confirmar en step con ediciones en varios pasos y retomar no pierde ninguna (T062)", async () => {
        const branch = "us5-save-step";
        createBranchWithCommits(repo, branch, [
            {file: "src/s1.ts", content: "s1\n", message: "step-1"},
            {file: "src/s2.ts", content: "s2\n", message: "step-2"},
            {file: "src/s3.ts", content: "s3\n", message: "step-3"},
        ]);

        const api = await getTestApi();
        startReview(repo, branch, ["--step"]);
        let state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "step");
        assert.strictEqual(state.state?.position, 1);

        // Edicion en el paso 1, avanzar, edicion en el paso 2 — dos pasos con trabajo.
        writeFile(repo, "src/s1.ts", "s1\nFIX-STEP-1\n");
        gitReviewOrThrow(["next"], repo.dir);
        writeFile(repo, "src/s2.ts", "s2\nFIX-STEP-2\n");

        state = await api.refresh();
        assert.strictEqual(state.state?.position, 2);

        await withScriptedConfirm("Save for Later", () =>
            vscode.commands.executeCommand("gitReview.saveReview")
        );

        assert.strictEqual(branchExists(repo, `review-saved/${branch}`), true);
        assert.strictEqual(headBranch(repo), "main");

        const line = savedLine(repo, branch);
        assert.ok(line !== undefined);
        // step en posicion 2 de 3
        assert.strictEqual(line, `branch\treview-saved/${branch}\t1\t0\t0\tstep\t2\t3`);

        // Retomar con el comando que ya existe desde 002: el inventario tiene
        // una sola fila (la guardada), indice 0.
        state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        const savedIndex = state.branches.findIndex((b) => b.name === `review-saved/${branch}` && b.saved);
        assert.ok(savedIndex >= 0, "precondicion: la guardada esta en el inventario");

        await withScriptedConfirm("Continue", () =>
            vscode.commands.executeCommand("gitReview.continueReview", savedIndex)
        );

        state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "step");
        assert.strictEqual(state.state?.position, 2, "retoma en el mismo paso");
        assert.strictEqual(headBranch(repo), `review/${branch}`);

        // Edicion del paso actual (2) vuelve al working tree.
        const diff = git(["diff", "HEAD"], repo.dir);
        assert.ok(diff.includes("FIX-STEP-2"), "la edicion del paso actual tiene que volver");

        // Edicion del paso 1 sigue banqueada (no se perdio al pausar).
        assert.strictEqual(
            state.entries[0]?.banked,
            true,
            "la edicion del paso 1 tiene que seguir banqueada tras retomar"
        );
        assert.strictEqual(
            branchExists(repo, `review-saved/${branch}`),
            false,
            "continue consume la guardada"
        );
    });

    it("descartar la confirmacion no invoca save (T062/FR-030)", async () => {
        const branch = "us5-save-dismiss";
        createBranchWithChanges(repo, branch, {"src/b.ts": "b\n"});

        const api = await getTestApi();
        startReview(repo, branch);
        assert.strictEqual((await api.refresh()).situation, "review");
        writeFile(repo, "src/b.ts", "b\nedited\n");

        await withScriptedConfirm(undefined, () =>
            vscode.commands.executeCommand("gitReview.saveReview")
        );

        assert.strictEqual(
            branchExists(repo, `review/${branch}`),
            true,
            "review/<branch> no debe tocarse si se descarta la confirmacion"
        );
        assert.strictEqual(
            branchExists(repo, `review-saved/${branch}`),
            false,
            "review-saved/<branch> no debe crearse si se descarta"
        );
        assert.strictEqual(headBranch(repo), `review/${branch}`);

        const after = await api.refresh();
        assert.strictEqual(after.situation, "review", "la review sigue activa tras descartar");
    });

    it("si review-saved ya existe para el source, save falla y la review activa sigue intacta (T063)", async () => {
        const branch = "us5-save-collision";
        createBranchWithChanges(repo, branch, {"src/c.ts": "c\n"});

        const api = await getTestApi();
        startReview(repo, branch);
        assert.strictEqual((await api.refresh()).situation, "review");
        writeFile(repo, "src/c.ts", "c\nKEEP-ME\n");

        // Plantar un review-saved/<src> a mano: start se niega a crear uno si
        // ya hay guardada, y save se niega a pisarla — es el choque que T063
        // protege. El ref vacio alcanza: save solo chequea que exista.
        git(["branch", `review-saved/${branch}`, "main"], repo.dir);
        assert.strictEqual(branchExists(repo, `review-saved/${branch}`), true);

        const beforeHead = headBranch(repo);
        const beforeDiff = git(["diff", "HEAD"], repo.dir);

        const {errors} = await withScriptedConfirm("Save for Later", () =>
            vscode.commands.executeCommand("gitReview.saveReview")
        );

        assert.ok(errors.length > 0, "tiene que mostrar el diagnostico de la CLI");
        assert.ok(
            errors.some((e) => e.includes("already exists") || e.includes("review-saved")),
            `el toast tiene que traer el diagnostico de la CLI; got: ${JSON.stringify(errors)}`
        );

        // La review activa original sigue existiendo intacta — no solo que el
        // comando devolvio error: HEAD, rama y ediciones no se tocaron.
        assert.strictEqual(headBranch(repo), beforeHead);
        assert.strictEqual(branchExists(repo, `review/${branch}`), true);
        assert.strictEqual(
            git(["diff", "HEAD"], repo.dir),
            beforeDiff,
            "las ediciones del working tree no se tocaron"
        );

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.branch, `review/${branch}`);

        // Limpieza del ref plantado (afterEach tambien lo cubre).
        forceCleanup(repo, branch);
    });
});
