import * as assert from "node:assert";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";
import {GitReviewTestApi} from "../../src/extension";
import {Situation} from "../../src/review/state";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    addWalkthrough,
    createBranchWithChanges,
    git,
    sharedFixtureRepo,
    startReview
} from "./helpers/fixture";

async function setGitReviewPath(value: string): Promise<void> {
    await vscode.workspace.getConfiguration("gitReview").update("path", value, vscode.ConfigurationTarget.Workspace);
}

/**
 * `gitReview.path` cambia por un `onDidChangeConfiguration` asíncrono (ver
 * extension.ts): el evento puede llegar después de que el `update()` ya
 * resolvió. Sondea en vez de asumir que un solo `refresh()` ya lo vio.
 */
async function waitForSituation(api: GitReviewTestApi, expected: Situation, timeoutMs = 8000) {
    const start = Date.now();
    let state = await api.refresh();
    while (state.situation !== expected && Date.now() - start < timeoutMs) {
        await new Promise((resolve) => setTimeout(resolve, 150));
        state = await api.refresh();
    }
    return state;
}

describe("US5: entender por qué no hay nada que mostrar", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        await setGitReviewPath("");
        abortReview(repo);
    });

    it("sin review: no se presenta como error", async () => {
        // El repo compartido arranca en main, sin review activa.
        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
    });

    it("cursor fuera de rango: HEAD se movió de la base", async () => {
        const branch = "us5-out-of-range";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n", "src/b.ts": "b\n"});
        addWalkthrough(repo, branch, [
            {path: "src/a.ts", why: "a"},
            {path: "src/b.ts", why: "b"},
        ]);
        startReview(repo, branch);

        const api = await getTestApi();
        let state = await api.refresh();
        assert.strictEqual(state.situation, "review");

        await vscode.commands.executeCommand("gitReview.next"); // cursor: 1 -> 2 (la última)

        // Walk mode mantiene HEAD en la base; un commit que iguala src/b.ts al
        // contenido del tip lo saca del diff HEAD..tip — el total re-derivado
        // baja a 1, y el cursor (2) queda fuera de ese rango.
        fs.writeFileSync(path.join(repo.dir, "src", "b.ts"), "b\n");
        git(["add", "src/b.ts"], repo.dir);
        git(["commit", "-m", "converge b.ts with tip"], repo.dir);

        state = await api.refresh();
        assert.strictEqual(state.situation, "out-of-range");
    });

    it("error: metadata ausente en una rama review/* creada a mano", async () => {
        git(["checkout", "-b", "review/hand-made"], repo.dir);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "error");
        assert.ok(state.stderr && state.stderr.length > 0, "el error tendría que traer el stderr de la CLI");

        // El diagnóstico de la CLI llega al panel tal cual (FR-024), y el panel
        // no muestra nada de una review que no existe.
        const model = await api.getPanelModel();
        assert.strictEqual(model.situation, "error");
        assert.strictEqual(model.stderr, state.stderr);
        assert.strictEqual(model.mode, undefined);
        assert.strictEqual(model.current, undefined);
        assert.strictEqual(model.entryCount, 0);

        git(["checkout", "main"], repo.dir);
        git(["branch", "-D", "review/hand-made"], repo.dir);
    });

    it("CLI ausente: gitReview.path apunta a algo que no existe", async () => {
        const bogusPath = path.join(os.tmpdir(), "definitely-does-not-exist-git-review");
        const api = await getTestApi();
        await setGitReviewPath(bogusPath);
        api.invalidateVersionCheck();

        const state = await waitForSituation(api, "cli-missing");
        assert.strictEqual(state.situation, "cli-missing");
    });

    it("CLI vieja: --version reporta menos de 0.3.0", async () => {
        const fakeCliPath = path.join(fs.realpathSync(os.tmpdir()), `fake-git-review-${Date.now()}`);
        fs.writeFileSync(
            fakeCliPath,
            "#!/usr/bin/env sh\ncase \"$1\" in\n--version) echo 0.1.0 ;;\n*) echo 'error: fake old cli' >&2; exit 1 ;;\nesac\n",
            {mode: 0o755}
        );
        const api = await getTestApi();
        await setGitReviewPath(fakeCliPath);
        api.invalidateVersionCheck();

        try {
            const state = await waitForSituation(api, "cli-outdated");
            assert.strictEqual(state.situation, "cli-outdated");
        } finally {
            fs.rmSync(fakeCliPath, {force: true});
        }
    });
});
