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
    gitReview,
    gitReviewOrThrow,
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

    it("sin reviews en el repositorio el inventario esta vacio", async () => {
        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        assert.deepStrictEqual(state.branches, [], "el repo compartido arranca sin reviews");
        assert.deepStrictEqual((await api.getPanelModel()).reviews, []);
    });

    it("una review guardada llega al inventario y se ofrece resumirla", async () => {
        const branch = "us5-inventory";
        createBranchWithChanges(repo, branch, {"src/inv.ts": "inv\n"});
        startReview(repo, branch);
        // Pausarla la manda a review-saved/<branch> y devuelve HEAD a main: el
        // estado exacto donde el panel tiene algo que inventariar.
        gitReviewOrThrow(["save"], repo.dir);

        try {
            const api = await getTestApi();
            const state = await api.refresh();
            assert.strictEqual(state.situation, "no-review");
            assert.deepStrictEqual(
                state.branches.map((b) => b.name),
                [`review-saved/${branch}`],
                "la guardada es la unica review del repositorio"
            );
            assert.strictEqual(state.branches[0].saved, true);
            assert.strictEqual(state.branches[0].orphan, false);

            const model = await api.getPanelModel();
            assert.strictEqual(model.reviews.length, 1);
            assert.strictEqual(model.reviews[0].name, `review-saved/${branch}`);
            assert.strictEqual(model.reviews[0].resumable, true);
        } finally {
            gitReviewOrThrow(["forget", "--saved", branch], repo.dir);
        }
    });

    it("una review activa en otra rama se lista, pero no se ofrece resumirla", async () => {
        const branch = "us5-active-elsewhere";
        createBranchWithChanges(repo, branch, {"src/act.ts": "act\n"});
        startReview(repo, branch);
        // El review queda activo en review/<branch>; parado en main no hay
        // review, y es justo ahi donde el inventario tiene que mostrarlo.
        git(["checkout", "main"], repo.dir);

        try {
            const api = await getTestApi();
            const state = await api.refresh();
            assert.strictEqual(state.situation, "no-review");
            assert.deepStrictEqual(state.branches.map((b) => b.name), [`review/${branch}`]);

            const model = await api.getPanelModel();
            assert.strictEqual(model.reviews[0].saved, false);
            assert.strictEqual(
                model.reviews[0].resumable,
                false,
                "para volver a una activa no hay verbo: es un checkout"
            );
        } finally {
            git(["checkout", `review/${branch}`], repo.dir);
            gitReview(["abort"], repo.dir);
        }
    });

    it("continueReview con un indice que no resuelve no hace nada", async () => {
        // El camino feliz del comando no se puede afirmar acá: abre un modal de
        // confirmación y en el host de test nadie lo cierra. Lo que sí se puede
        // —y es lo que protege de invocar la CLI con basura— es que un índice
        // que no resuelve retorne ANTES del modal, sin tocar el repositorio.
        const api = await getTestApi();
        const before = await api.refresh();
        assert.strictEqual(before.situation, "no-review");

        for (const index of [0, -1, 7, "review-saved/whatever", undefined]) {
            await vscode.commands.executeCommand("gitReview.continueReview", index);
        }

        const after = await api.refresh();
        assert.strictEqual(after.situation, "no-review");
        assert.strictEqual(
            git(["symbolic-ref", "--quiet", "--short", "HEAD"], repo.dir).trim(),
            "main",
            "ningun indice invalido puede haber cambiado de rama"
        );
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
        // El stub tiene que ser ejecutable por la misma vía que usaría la CLI
        // real. En Windows, un script POSIX sin extensión sólo corre si `sh`
        // está en el PATH (invoke.ts se lo delega), así que desde una shell sin
        // Git Bash el test fallaba con `cli-missing` — entorno, no regresión, y
        // el síntoma apuntaba justo a la lógica de detección. Un `.cmd` cae por
        // la rama nativa de invoke.ts, que es la forma real en Windows.
        const isWindows = process.platform === "win32";
        const fakeCliPath = path.join(
            fs.realpathSync(os.tmpdir()),
            `fake-git-review-${Date.now()}${isWindows ? ".cmd" : ""}`
        );
        fs.writeFileSync(
            fakeCliPath,
            isWindows
                ? "@echo off\r\nif \"%~1\"==\"--version\" (\r\n  echo 0.1.0\r\n  exit /b 0\r\n)\r\necho error: fake old cli 1>&2\r\nexit /b 1\r\n"
                : "#!/usr/bin/env sh\ncase \"$1\" in\n--version) echo 0.1.0 ;;\n*) echo 'error: fake old cli' >&2; exit 1 ;;\nesac\n",
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
