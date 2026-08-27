import * as assert from "node:assert";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
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
    (vscode.window as unknown as {
        showErrorMessage: unknown
    }).showErrorMessage = async (msg: string) => {
        errors.push(msg);
        return undefined;
    };
    try {
        const result = await fn();
        return {result, infos, errors};
    } finally {
        (vscode.window as unknown as { showQuickPick: unknown }).showQuickPick = originalPick;
        (vscode.window as unknown as {
            showInformationMessage: unknown
        }).showInformationMessage = originalInfo;
        (vscode.window as unknown as {
            showErrorMessage: unknown
        }).showErrorMessage = originalError;
    }
}

/**
 * `undoFinish`/`resumeFinish` usan `showWarningMessage` (uno o dos, si hay
 * trabajo nuevo y se ofrece `--force`). Las respuestas se consumen en orden.
 */
async function withScriptedConfirms<T>(
    answers: Array<string | undefined>,
    fn: () => Thenable<T>
): Promise<{ result: T; infos: string[]; errors: string[]; warnings: string[] }> {
    const originalWarn = vscode.window.showWarningMessage;
    const originalInfo = vscode.window.showInformationMessage;
    const originalError = vscode.window.showErrorMessage;
    const infos: string[] = [];
    const errors: string[] = [];
    const warnings: string[] = [];
    let i = 0;
    (vscode.window as unknown as { showWarningMessage: unknown }).showWarningMessage =
        async (msg: string) => {
            warnings.push(msg);
            return answers[i++];
        };
    (vscode.window as unknown as { showInformationMessage: unknown }).showInformationMessage =
        async (msg: string) => {
            infos.push(msg);
            return undefined;
        };
    (vscode.window as unknown as {
        showErrorMessage: unknown
    }).showErrorMessage = async (msg: string) => {
        errors.push(msg);
        return undefined;
    };
    try {
        const result = await fn();
        return {result, infos, errors, warnings};
    } finally {
        (vscode.window as unknown as {
            showWarningMessage: unknown
        }).showWarningMessage = originalWarn;
        (vscode.window as unknown as {
            showInformationMessage: unknown
        }).showInformationMessage = originalInfo;
        (vscode.window as unknown as {
            showErrorMessage: unknown
        }).showErrorMessage = originalError;
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

function statusPorcelain(repo: { dir: string }): string {
    return gitReview(["status", "--porcelain"], repo.dir).stdout;
}

/** `git config --get` sale 1 cuando la clave no existe; eso no es un error del test. */
function configGet(repo: { dir: string }, key: string): string {
    try {
        return git(["config", "--get", key], repo.dir).trim();
    } catch {
        return "";
    }
}

const FINISH_TEST_BRANCHES = [
    "us3-finish-branch",
    "us3-finish-onto",
    "us3-finish-no-edits",
    "us3-finish-dismiss",
    "us4-undo-clean",
    "us4-undo-force",
    "us4-undo-dismiss-force",
    "us4-undo-from-main",
    "us4-clean-on-fixes",
    "us4-clean-from-main",
    "us4-resume-nav",
    "us4-resume-resolve",
    "us4-resume-onto",
];

/** Sale de review-fixes/* (con edits staged) a main, como el sandbox / CLI. */
function switchAwayToMain(repo: FixtureRepo): void {
    try {
        git(["switch", "--quiet", "--discard-changes", "main"], repo.dir);
    } catch {
        git(["reset", "--quiet", "--hard"], repo.dir);
        git(["clean", "--quiet", "-fd"], repo.dir);
        git(["switch", "--quiet", "main"], repo.dir);
    }
    git(["reset", "--quiet", "--hard"], repo.dir);
    git(["clean", "--quiet", "-fd"], repo.dir);
    assert.strictEqual(headBranch(repo), "main");
}

function finishLineFor(repo: FixtureRepo, branch: string): string | undefined {
    return listPorcelain(repo)
        .split("\n")
        .find((l) => l.startsWith(`finish\treview/${branch}\t`));
}

function branchExists(repo: { dir: string }, name: string): boolean {
    return git(["branch", "--list", name], repo.dir).trim().length > 0;
}

function tryDelete(repo: { dir: string }, ref: string): void {
    try {
        git(["branch", "-D", ref], repo.dir);
    } catch {
        // no existe en esta corrida (p. ej. review-fixes/<x> solo lo crea la
        // variante "separate branch") — nada que borrar.
    }
}

/**
 * Mismo mecanismo que finish-conflict-actions.spec.ts / tests/finish-state.bats:
 * cf1 toca x.txt y cf3 lo vuelve a cambiar, asi el edit banqueado del paso 2
 * choca al reaplicar sobre el tip. Deja review/<branch> en conflict con
 * reviewresume=conflict. `finishArgs` permite pasar `--onto-source`.
 */
function buildConflictFixture(repo: FixtureRepo, branch: string, finishArgs: string[] = []): void {
    createBranchWithCommits(repo, branch, [
        {file: "x.txt", content: "X0\n", message: "cf-base"},
        {file: "x.txt", content: "X0\nX1\n", message: "cf1-touch-x"},
        {file: "cfa.txt", content: "A0\nA1\n", message: "cf2-touch-a"},
        {file: "x.txt", content: "X0\nX1-CHANGED\n", message: "cf3-change-x"},
    ]);
    startReview(repo, branch, ["--step"]);
    gitReviewOrThrow(["next"], repo.dir);
    writeFile(repo, "x.txt", "X0\nX1-EDITED\n");
    gitReviewOrThrow(["next"], repo.dir);
    writeFile(repo, "cfa.txt", "A0\nA1-EDITED\n");

    const finish = gitReview(["finish", ...finishArgs], repo.dir);
    assert.notStrictEqual(finish.status, 0, "el fixture de conflicto tiene que dejar finish trabado");
    assert.strictEqual(
        git(["config", `branch.review/${branch}.reviewresume`], repo.dir).trim(),
        "conflict",
        "precondicion: el fixture realmente quedo mid-conflict"
    );
}

function forceCleanup(repo: FixtureRepo, branch: string): void {
    git(["checkout", "-f", "main"], repo.dir);
    tryDelete(repo, `review/${branch}`);
    tryDelete(repo, `review-fixes/${branch}`);
    tryDelete(repo, branch);
}

describe("US3 (005): quedarse con las ediciones al terminar", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        // abortReview() del helper compartido asume que HEAD esta en review/*
        // o ya limpio; aca un finish exitoso lo deja en review-fixes/<x> o en
        // la propia rama del PR, ninguno de los dos abortable — asi que la
        // limpieza es propia: forzar la vuelta a main (descartando lo que
        // haga falta) ANTES de borrar las ramas que finish deja atras, para
        // que el repositorio compartido quede sin ningun review/* colgado
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
        assert.ok(
            infos.some(
                (m) => m.includes(`review-fixes/${branch}`) && m.includes("ready") && m.includes("Undo")
            ),
            `toast de pending con destino y undo; got: ${JSON.stringify(infos)}`
        );

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
        // Pantalla de post-cierre: sin inventario ni empty-state Start/base.
        assert.deepStrictEqual(model.reviews, []);
        assert.strictEqual(model.noBaseConfigured, false);
        assert.strictEqual(model.configuredBase, undefined);
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

    it("sin ediciones que extraer, se informa como resultado normal y cierra la sesion (T050/FR-019)", async () => {
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
        // Extract vacio tambien deja finish pending (undo vivo): mismo toast
        // de destino listo + undo, nunca un error.
        assert.ok(
            infos.some(
                (m) => m.includes(`review-fixes/${branch}`) && m.includes("ready")
            ),
            `toast de exito sobre el destino; got: ${JSON.stringify(infos)}`
        );

        // Extract vacio: review-fixes en el tip, sin staged, con undo pending —
        // el panel deja de ofrecer Next/Finish de la review activa.
        assert.strictEqual(headBranch(repo), `review-fixes/${branch}`);
        const staged = git(["diff", "--cached"], repo.dir);
        assert.strictEqual(staged.trim(), "", "nada staged en el extract vacio");

        const finishLine = listPorcelain(repo)
            .split("\n")
            .find((l) => l.startsWith(`finish\treview/${branch}\t`));
        assert.strictEqual(finishLine, `finish\treview/${branch}\tpending\t0`);

        const state = await api.refresh();
        assert.strictEqual(state.situation, "finish-pending");
        const model = await api.getPanelModel();
        assert.deepStrictEqual(model.pendingFinish, {branch: `review/${branch}`, onto: false});
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

describe("US4 (005): deshacer un cierre o destrabar uno a mitad", function () {
    this.timeout(90000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        git(["checkout", "-f", "main"], repo.dir);
        for (const b of FINISH_TEST_BRANCHES) {
            tryDelete(repo, `review/${b}`);
            tryDelete(repo, `review-fixes/${b}`);
            // onto-source puede haber tocado la rama del PR misma
            if (b.startsWith("us4-")) {
                try {
                    // no borrar main; las ramas de PR de los fixtures us4 si
                    if (b !== "main") {
                        tryDelete(repo, b);
                    }
                } catch {
                    // ignore
                }
            }
        }
    });

    // ── T055: undoFinish / clean desde finish-pending (cualquier HEAD) ────

    it("undoFinish sobre un pending sin tocar restaura review/<src> con las ediciones intactas (T055)", async () => {
        const branch = "us4-undo-clean";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        assert.strictEqual((await api.refresh()).situation, "review");
        writeFile(repo, "src/a.ts", "a\nedited-for-undo\n");

        // Finish via CLI so the scenario no depende del QuickPick de US3.
        gitReviewOrThrow(["finish"], repo.dir);
        assert.strictEqual(headBranch(repo), `review-fixes/${branch}`);
        assert.strictEqual((await api.refresh()).situation, "finish-pending");

        await withScriptedConfirms(["Undo Finish"], () =>
            vscode.commands.executeCommand("gitReview.undoFinish")
        );

        assert.strictEqual(
            reviewBranchExists(repo, branch),
            true,
            "review/<branch> tiene que seguir (y volver a ser HEAD)"
        );
        assert.strictEqual(headBranch(repo), `review/${branch}`);

        // Las ediciones vuelven al working tree de la review (diff contra el tip).
        const diff = git(["diff", "HEAD"], repo.dir);
        assert.ok(diff.includes("edited-for-undo"), "las ediciones tienen que estar intactas tras deshacer");

        const finishLine = listPorcelain(repo)
            .split("\n")
            .find((l) => l.startsWith(`finish\treview/${branch}\t`));
        assert.strictEqual(finishLine, undefined, "el registro finish tiene que desaparecer");

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
    });

    it("undoFinish con un commit nuevo encima falla, y solo --force tras segunda confirmacion lo completa (T055)", async () => {
        const branch = "us4-undo-force";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        writeFile(repo, "src/a.ts", "a\nedited\n");
        gitReviewOrThrow(["finish"], repo.dir);
        assert.strictEqual(headBranch(repo), `review-fixes/${branch}`);

        // Trabajo nuevo encima del cierre: lo que --abort sin --force se niega a tirar.
        writeFile(repo, "src/a.ts", "a\nedited\nREFINED\n");
        git(["add", "src/a.ts"], repo.dir);
        git(["commit", "-m", "my review commit"], repo.dir);
        const commitSha = git(["rev-parse", "HEAD"], repo.dir).trim();

        assert.strictEqual((await api.refresh()).situation, "finish-pending");

        // Primera confirmacion aceptada: --abort debe fallar y dejar el commit.
        // Segunda: "Discard Work and Undo" acepta el --force.
        const {warnings} = await withScriptedConfirms(
            ["Undo Finish", "Discard Work and Undo"],
            () => vscode.commands.executeCommand("gitReview.undoFinish")
        );
        assert.ok(warnings.length >= 2, "tiene que haber habido dos confirmaciones (simple y force)");
        // La segunda muestra el stderr de la CLI (nombra el trabajo que se pierde).
        assert.ok(
            warnings.some((w) => w.includes("has changes since the finish") || w.includes("--force")),
            `la segunda confirmacion tiene que mostrar el rechazo de la CLI; got: ${JSON.stringify(warnings)}`
        );

        assert.strictEqual(headBranch(repo), `review/${branch}`, "tras --force, HEAD vuelve a la review");
        try {
            git(["rev-parse", "--verify", `refs/heads/review-fixes/${branch}`], repo.dir);
            assert.fail("review-fixes/<branch> tiene que haber sido borrada por --force");
        } catch {
            // esperado: la rama ya no existe
        }
        // El commit nuevo no tiene que sobrevivir en review-fixes (ya no hay rama).
        void commitSha;

        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
    });

    it("descartar la segunda confirmacion de --force deja el commit nuevo intacto (T055/FR-030)", async () => {
        const branch = "us4-undo-dismiss-force";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        writeFile(repo, "src/a.ts", "a\nedited\n");
        gitReviewOrThrow(["finish"], repo.dir);

        writeFile(repo, "src/a.ts", "a\nedited\nKEEPME\n");
        git(["add", "src/a.ts"], repo.dir);
        git(["commit", "-m", "must survive dismiss"], repo.dir);
        const keptSha = git(["rev-parse", "HEAD"], repo.dir).trim();

        assert.strictEqual((await api.refresh()).situation, "finish-pending");

        // Primera si, segunda no: el --force no se invoca.
        await withScriptedConfirms(["Undo Finish", undefined], () =>
            vscode.commands.executeCommand("gitReview.undoFinish")
        );

        assert.strictEqual(
            headBranch(repo),
            `review-fixes/${branch}`,
            "HEAD se queda en la rama de arreglos si se descarta el force"
        );
        assert.strictEqual(
            git(["rev-parse", `refs/heads/review-fixes/${branch}`], repo.dir).trim(),
            keptSha,
            "el commit nuevo tiene que seguir intacto"
        );
        assert.strictEqual(
            git(["log", "-1", "--format=%s", `review-fixes/${branch}`], repo.dir).trim(),
            "must survive dismiss"
        );

        // El punto de undo sigue vivo: el cierre pending no se resolvio.
        assert.strictEqual(finishLineFor(repo, branch), `finish\treview/${branch}\tpending\t0`);
    });

    it("undoFinish desde main (fuera de review-fixes) restaura la review (T055)", async () => {
        // El pending es del repo: Clean/Undo no dependen de estar en review-fixes.
        const branch = "us4-undo-from-main";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        writeFile(repo, "src/a.ts", "a\nedited-off-branch\n");
        gitReviewOrThrow(["finish"], repo.dir);
        assert.strictEqual(headBranch(repo), `review-fixes/${branch}`);
        assert.strictEqual((await api.refresh()).situation, "finish-pending");

        switchAwayToMain(repo);
        // HEAD ya no es review-fixes; situation sigue finish-pending (list).
        let state = await api.refresh();
        assert.strictEqual(state.situation, "finish-pending");
        assert.strictEqual(headBranch(repo), "main");
        const model = await api.getPanelModel();
        assert.deepStrictEqual(model.pendingFinish, {branch: `review/${branch}`, onto: false});
        assert.deepStrictEqual(model.reviews, [], "sin inventario en finish-pending");

        await withScriptedConfirms(["Undo Finish"], () =>
            vscode.commands.executeCommand("gitReview.undoFinish")
        );

        assert.strictEqual(headBranch(repo), `review/${branch}`);
        const diff = git(["diff", "HEAD"], repo.dir);
        assert.ok(diff.includes("edited-off-branch"), "edits restauradas tras abort desde main");
        assert.strictEqual(finishLineFor(repo, branch), undefined, "finish pending se fue");
        assert.strictEqual(branchExists(repo, `review-fixes/${branch}`), false);

        state = await api.refresh();
        assert.strictEqual(state.situation, "review");
    });

    it("clean desde finish-pending en review-fixes usa --keep-fixes y deja no-review (T055)", async () => {
        // clean --keep-fixes: se va review/ + undo; quedan staged en review-fixes.
        const branch = "us4-clean-on-fixes";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        writeFile(repo, "src/a.ts", "a\nclean-keeps-staged\n");
        gitReviewOrThrow(["finish"], repo.dir);
        assert.strictEqual(headBranch(repo), `review-fixes/${branch}`);
        assert.strictEqual((await api.refresh()).situation, "finish-pending");

        const deltaKey = `reviewworkflow.${branch}.reviewed`;
        const deltaBefore = configGet(repo, deltaKey);

        await withScriptedConfirms(["Done"], () =>
            vscode.commands.executeCommand("gitReview.cleanReview")
        );

        assert.strictEqual(headBranch(repo), `review-fixes/${branch}`, "sigue en el entregable");
        assert.strictEqual(
            reviewBranchExists(repo, branch),
            false,
            "review/<src> (undo) tiene que borrarse"
        );
        assert.strictEqual(
            branchExists(repo, `review-fixes/${branch}`),
            true,
            "--keep-fixes deja review-fixes"
        );
        const staged = git(["diff", "--cached"], repo.dir);
        assert.ok(staged.includes("clean-keeps-staged"), "edits staged tienen que sobrevivir");
        assert.strictEqual(finishLineFor(repo, branch), undefined, "finish pending se fue");
        assert.strictEqual(
            configGet(repo, deltaKey),
            deltaBefore,
            "clean no toca el marcador --delta"
        );

        const state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        const model = await api.getPanelModel();
        assert.strictEqual(model.pendingFinish, undefined);
        assert.strictEqual(model.situation, "no-review");
    });

    it("clean desde finish-pending en main usa --keep-fixes: borra review, conserva review-fixes (T055)", async () => {
        // Independiente de HEAD: el panel siempre invoca clean --keep-fixes.
        const branch = "us4-clean-from-main";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        git(["checkout", branch], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        writeFile(repo, "src/a.ts", "a\nmust-survive-clean\n");
        gitReviewOrThrow(["finish"], repo.dir);
        assert.strictEqual((await api.refresh()).situation, "finish-pending");

        git(["add", "-A"], repo.dir);
        git(["commit", "-m", "fixes commit before clean"], repo.dir);
        const fixesSha = git(["rev-parse", "HEAD"], repo.dir).trim();

        switchAwayToMain(repo);
        assert.strictEqual((await api.refresh()).situation, "finish-pending");
        assert.strictEqual(headBranch(repo), "main");
        assert.ok(branchExists(repo, `review-fixes/${branch}`));
        assert.ok(reviewBranchExists(repo, branch));

        await withScriptedConfirms(["Done"], () =>
            vscode.commands.executeCommand("gitReview.cleanReview")
        );

        assert.strictEqual(headBranch(repo), "main");
        assert.strictEqual(reviewBranchExists(repo, branch), false, "review/ borrada");
        assert.strictEqual(
            branchExists(repo, `review-fixes/${branch}`),
            true,
            "review-fixes/ se conserva con --keep-fixes aunque no sea HEAD"
        );
        assert.strictEqual(
            git(["rev-parse", `refs/heads/review-fixes/${branch}`], repo.dir).trim(),
            fixesSha,
            "el commit de fixes tiene que seguir en review-fixes"
        );
        assert.strictEqual(
            git(["log", "-1", "--format=%s", `review-fixes/${branch}`], repo.dir).trim(),
            "fixes commit before clean"
        );

        assert.strictEqual(finishLineFor(repo, branch), undefined);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        assert.strictEqual((await api.getPanelModel()).pendingFinish, undefined);
    });

    // ── T056: resumeFinish + navigationLocked + onto ──────────────────────

    it("finish-conflict bloquea next/prev y resumeFinish completa el cierre al resolver (T056)", async () => {
        const branch = "us4-resume-resolve";
        buildConflictFixture(repo, branch);

        try {
            const api = await getTestApi();
            const state = await api.refresh();
            assert.strictEqual(state.situation, "finish-conflict", "precondicion del fixture");

            const model = await api.getPanelModel();
            assert.strictEqual(model.navigationLocked, true);

            // FR-027: next/prev no deben mutar el porcelain (efecto, no excepcion).
            const before = statusPorcelain(repo);
            await vscode.commands.executeCommand("gitReview.next");
            await vscode.commands.executeCommand("gitReview.prev");
            const after = statusPorcelain(repo);
            assert.strictEqual(after, before, "next/prev no tienen que cambiar el porcelain en finish-conflict");

            // Resolver los marcadores en el working tree y continuar.
            writeFile(repo, "x.txt", "X0\nX1-RESOLVED\n");
            git(["add", "x.txt"], repo.dir);

            await vscode.commands.executeCommand("gitReview.resumeFinish");

            // El cierre se completa: HEAD en review-fixes, registro conflict se
            // va; queda un pending (cierre completo con punto de undo).
            assert.strictEqual(headBranch(repo), `review-fixes/${branch}`);
            assert.strictEqual(
                configGet(repo, `branch.review/${branch}.reviewresume`),
                "",
                "reviewresume=conflict tiene que haberse limpiado"
            );
            const finishLine = listPorcelain(repo)
                .split("\n")
                .find((l) => l.startsWith(`finish\treview/${branch}\t`));
            assert.strictEqual(
                finishLine,
                `finish\treview/${branch}\tpending\t0`,
                "tras resume el cierre queda pending, no conflict"
            );

            const afterState = await api.refresh();
            assert.strictEqual(afterState.situation, "finish-pending");
        } finally {
            forceCleanup(repo, branch);
        }
    });

    it("resumeFinish con onto del registro finish (no de memoria) deja las ediciones sobre la rama del PR (T056)", async () => {
        // El caso que motiva exponer onto: el cierre arranco con --onto-source
        // via CLI (como si el editor se hubiera reiniciado y no quedara
        // ninguna memoria en proceso del comando de finish), y resumeFinish
        // tiene que leer onto del porcelain, no de una variable de sesion.
        const branch = "us4-resume-onto";
        buildConflictFixture(repo, branch, ["--onto-source"]);

        try {
            const api = await getTestApi();
            const state = await api.refresh();
            assert.strictEqual(state.situation, "finish-conflict");
            assert.strictEqual(state.finish?.onto, true, "precondicion: el registro finish trae onto=1");

            writeFile(repo, "x.txt", "X0\nX1-RESOLVED-ONTO\n");
            git(["add", "x.txt"], repo.dir);

            // Sin memoria en proceso: nunca se invoco finishReview en esta sesion.
            await vscode.commands.executeCommand("gitReview.resumeFinish");

            assert.strictEqual(
                headBranch(repo),
                branch,
                "con onto=1 las ediciones tienen que terminar sobre la rama del PR, no review-fixes"
            );
            try {
                git(["rev-parse", "--verify", `refs/heads/review-fixes/${branch}`], repo.dir);
                assert.fail("no tiene que crearse review-fixes/<branch> cuando onto viene del registro");
            } catch {
                // esperado
            }

            const finishLine = listPorcelain(repo)
                .split("\n")
                .find((l) => l.startsWith(`finish\treview/${branch}\t`));
            assert.strictEqual(finishLine, `finish\treview/${branch}\tpending\t1`);

            const after = await api.refresh();
            assert.strictEqual(after.situation, "finish-pending");
            const model = await api.getPanelModel();
            assert.deepStrictEqual(model.pendingFinish, {branch: `review/${branch}`, onto: true});
        } finally {
            forceCleanup(repo, branch);
        }
    });

    it("undoFinish desde finish-conflict vuelve a editar sin resolver marcadores (T058)", async () => {
        const branch = "us4-resume-nav";
        buildConflictFixture(repo, branch);

        try {
            const api = await getTestApi();
            assert.strictEqual((await api.refresh()).situation, "finish-conflict");

            await withScriptedConfirms(["Undo Finish"], () =>
                vscode.commands.executeCommand("gitReview.undoFinish")
            );

            assert.strictEqual(headBranch(repo), `review/${branch}`);
            assert.strictEqual(
                configGet(repo, `branch.review/${branch}.reviewresume`),
                "",
                "abort limpia el marcador de conflicto"
            );
            const state = await api.refresh();
            assert.strictEqual(state.situation, "review");
            assert.strictEqual(state.finish, undefined);
        } finally {
            forceCleanup(repo, branch);
        }
    });
});
