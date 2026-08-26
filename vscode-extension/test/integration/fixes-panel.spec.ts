import * as assert from "node:assert";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    createBranchWithChanges,
    git,
    gitReview,
    gitReviewOrThrow,
    sharedFixtureRepo,
    startReview,
} from "./helpers/fixture";

/**
 * La seccion "Edits you extracted" del estado vacio.
 *
 * Es la superficie de las ramas `review-fixes/` que deja un finish -- el ultimo
 * estado del repositorio que ninguna otra nombraba. Lo que se afirma es el
 * `PanelModel` (el webview corre en su propio contexto) y el efecto real sobre
 * las ramas de git, no el texto impreso.
 */
function branchExists(repoDir: string, ref: string): boolean {
    try {
        git(["rev-parse", "--verify", "--quiet", `refs/heads/${ref}`], repoDir);
        return true;
    } catch {
        return false;
    }
}

function tryDelete(repoDir: string, ref: string): void {
    try {
        git(["branch", "-D", ref], repoDir);
    } catch {
        // absent
    }
}

const BRANCH = "fx-extracted";

describe("la seccion de ramas de ediciones", function () {
    this.timeout(90000);
    const repo = sharedFixtureRepo();

    afterEach(() => {
        git(["checkout", "-f", "main"], repo.dir);
        gitReview(["clean", BRANCH], repo.dir);
        tryDelete(repo.dir, `review/${BRANCH}`);
        tryDelete(repo.dir, `review-fixes/${BRANCH}`);
        tryDelete(repo.dir, BRANCH);
    });

    it("lista la rama que dejo un finish, con su estado y su sesion", async () => {
        createBranchWithChanges(repo, BRANCH, {"src/fx-a.ts": "a\n"});
        const api = await getTestApi();
        startReview(repo, BRANCH);
        gitReviewOrThrow(["finish"], repo.dir);
        // finish deja HEAD en review-fixes/<branch> y un undo pendiente, o sea la
        // situacion finish-pending, que tiene su propio banner. La seccion es del
        // estado vacio, al que se llega soltando ese undo -- que es el paso que la
        // pantalla de post-cierre ofrece con Clean.
        git(["checkout", "-f", "main"], repo.dir);
        gitReviewOrThrow(["clean", "--keep-fixes", BRANCH], repo.dir);

        assert.ok(branchExists(repo.dir, `review-fixes/${BRANCH}`), "precondicion");
        const state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        const model = await api.getPanelModel();
        const row = model.fixes.find((f) => f.name === `review-fixes/${BRANCH}`);
        assert.ok(row, `la fila no llego: ${JSON.stringify(model.fixes)}`);
        // Nada commiteado encima: finish STAGEA las ediciones, no las commitea.
        assert.strictEqual(row.state, "empty");
        assert.strictEqual(row.current, false);
        assert.strictEqual(row.session, false);
    });

    it("Discard pide confirmacion y se lleva SOLO la rama de ediciones", async () => {
        createBranchWithChanges(repo, BRANCH, {"src/fx-b.ts": "b\n"});
        const api = await getTestApi();
        startReview(repo, BRANCH);
        gitReviewOrThrow(["finish"], repo.dir);
        git(["checkout", "-f", "main"], repo.dir);
        gitReviewOrThrow(["clean", "--keep-fixes", BRANCH], repo.dir);
        // Una review viva de la misma rama: es lo que hace que borrar la fila
        // TENGA que ser --fixes-only, porque un clean <branch> se la llevaria.
        git(["branch", `review/${BRANCH}`, "main"], repo.dir);

        await api.refresh();
        let model = await api.getPanelModel();
        const index = model.fixes.findIndex((f) => f.name === `review-fixes/${BRANCH}`);
        assert.ok(index >= 0);

        const original = vscode.window.showWarningMessage;
        let asked = 0;
        // Sin confirmar no se borra nada.
        (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage =
            async (message: string) => {
                asked++;
                assert.ok(message.includes(`review-fixes/${BRANCH}`), message);
                return undefined;
            };
        try {
            api.sendPanelMessage("discardFixes", index);
            for (let i = 0; i < 60 && asked === 0; i++) {
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
            await new Promise((resolve) => setTimeout(resolve, 300));
        } finally {
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = original;
        }
        assert.strictEqual(asked, 1, "se pide confirmacion");
        assert.ok(branchExists(repo.dir, `review-fixes/${BRANCH}`), "sin confirmar no se borra");

        let confirmed = 0;
        (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage =
            async () => {
                confirmed++;
                return "Discard";
            };
        try {
            api.sendPanelMessage("discardFixes", index);
            for (let i = 0; i < 100 && branchExists(repo.dir, `review-fixes/${BRANCH}`); i++) {
                await new Promise((resolve) => setTimeout(resolve, 50));
            }
        } finally {
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = original;
        }
        assert.strictEqual(confirmed, 1);
        assert.strictEqual(
            branchExists(repo.dir, `review-fixes/${BRANCH}`),
            false,
            "la rama de ediciones se borro"
        );
        // Y la sesion sigue en pie: --fixes-only no la toca, asi que el finish
        // todavia se puede deshacer.
        assert.ok(branchExists(repo.dir, `review/${BRANCH}`), "la review sigue");
        assert.ok(
            gitReviewOrThrow(["list", "--porcelain"], repo.dir).stdout.includes(`review/${BRANCH}`),
            "la review sigue en el inventario"
        );

        await api.refresh();
        model = await api.getPanelModel();
        assert.ok(!model.fixes.some((f) => f.name === `review-fixes/${BRANCH}`));
    });
});
