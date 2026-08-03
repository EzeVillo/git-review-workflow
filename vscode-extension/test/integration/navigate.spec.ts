import * as assert from "node:assert";
import * as path from "node:path";
import * as vscode from "vscode";
import {PathRef} from "../../src/cli/unquote";
import {GitReviewTestApi} from "../../src/extension";
import {ReviewState} from "../../src/review/state";
import {closeAllEditors, waitForActiveTab} from "./helpers/editors";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    addWalkthrough,
    createBranchWithChanges,
    gitReview,
    sharedFixtureRepo,
    startReview
} from "./helpers/fixture";

function displayOf(id: string | PathRef): string {
    return typeof id === "string" ? id : id.display;
}

async function waitUntil(predicate: (state: ReviewState) => boolean, api: GitReviewTestApi, timeoutMs = 8000): Promise<ReviewState> {
    const start = Date.now();
    let state = api.getState();
    while (Date.now() - start < timeoutMs) {
        if (predicate(state)) {
            return state;
        }
        await new Promise((resolve) => setTimeout(resolve, 150));
        state = await api.refresh();
    }
    return state;
}

describe("US4: avanzar y retroceder en la secuencia", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        abortReview(repo);
        await closeAllEditors();
    });

    it("next/prev actualizan el panel y coinciden con status --porcelain (AC1)", async () => {
        const branch = "us4-next-prev";
        createBranchWithChanges(repo, branch, {
            "src/a.ts": "a\n",
            "src/b.ts": "b\n",
            "src/c.ts": "c\n"
        });
        addWalkthrough(repo, branch, [
            {path: "src/a.ts", why: "a"},
            {path: "src/b.ts", why: "b"},
            {path: "src/c.ts", why: "c"},
        ]);
        startReview(repo, branch);

        const api = await getTestApi();
        let state = await api.refresh();
        assert.strictEqual(state.state?.position, 1);
        let model = await api.getPanelModel();
        assert.strictEqual(model.atFirst, true, "en la primera no hay a donde retroceder");
        assert.strictEqual(model.atLast, false);

        await vscode.commands.executeCommand("gitReview.next");
        state = api.getState();
        assert.strictEqual(state.state?.position, 2);
        let porcelain = gitReview(["status", "--porcelain"], repo.dir);
        assert.match(porcelain.stdout.split("\n")[0], /\t2\t3\t3\t/);
        model = await api.getPanelModel();
        assert.strictEqual(model.atFirst, false, "en el medio los dos controles sirven");
        assert.strictEqual(model.atLast, false);

        await vscode.commands.executeCommand("gitReview.next");
        state = api.getState();
        assert.strictEqual(state.state?.position, 3);
        model = await api.getPanelModel();
        assert.strictEqual(model.atLast, true, "en la ultima no hay a donde avanzar");
        assert.strictEqual(model.atFirst, false);

        await vscode.commands.executeCommand("gitReview.prev");
        state = api.getState();
        assert.strictEqual(state.state?.position, 2);
        porcelain = gitReview(["status", "--porcelain"], repo.dir);
        assert.match(porcelain.stdout.split("\n")[0], /\t2\t3\t3\t/);
        model = await api.getPanelModel();
        assert.strictEqual(model.atFirst, false);
        assert.strictEqual(model.atLast, false);
    });

    it("avanzar en modo walk abre los cambios de la entrada, no el archivo pelado", async () => {
        const branch = "us4-next-opens-diff";
        createBranchWithChanges(repo, branch, {"src/first.ts": "first\n", "src/second.ts": "second\n"});
        addWalkthrough(repo, branch, [
            {path: "src/first.ts", why: "primera"},
            {path: "src/second.ts", why: "segunda"},
        ]);
        startReview(repo, branch);

        const api = await getTestApi();
        let state = await api.refresh();
        assert.strictEqual(state.state?.mode, "walk");
        assert.strictEqual(state.state?.position, 1);

        await vscode.commands.executeCommand("gitReview.next");
        state = api.getState();
        assert.strictEqual(state.state?.position, 2);

        const tab = await waitForActiveTab();
        assert.ok(tab, "avanzar no abrio ningun tab");

        // Misma garantia que afirma `openChange` en open-entry.spec.ts: qué
        // superficie exacta se usa lo decide la extension de git, pero NO puede
        // ser el archivo del working tree abierto como texto plano — esa es la
        // accion aparte (`openEntry`, el boton "Abrir archivo").
        const input = tab!.input;
        const isPlainFileEditor = input instanceof vscode.TabInputText && input.uri.scheme === "file";
        assert.ok(!isPlainFileEditor, `avanzar debe mostrar los cambios, no el archivo: ${JSON.stringify(input)}`);

        const shownPath = input instanceof vscode.TabInputTextDiff
            ? input.modified.fsPath
            : (input as vscode.TabInputText).uri.fsPath;
        assert.strictEqual(path.basename(shownPath), "second.ts");
    });

    it("un intento en el limite propaga la respuesta de la CLI sin dejar el panel inconsistente (AC2/AC3)", async () => {
        const branch = "us4-boundary";
        createBranchWithChanges(repo, branch, {"src/only.ts": "only\n"});
        addWalkthrough(repo, branch, [{path: "src/only.ts", why: "unica entrada"}]);
        startReview(repo, branch);

        const api = await getTestApi();
        let state = await api.refresh();
        assert.strictEqual(state.state?.position, 1);
        assert.strictEqual(state.state?.total, 1);

        // Una sola entrada: es a la vez el principio y el final, y el panel
        // deshabilita los dos controles en vez de dejar dos clics mudos.
        let model = await api.getPanelModel();
        assert.strictEqual(model.atFirst, true);
        assert.strictEqual(model.atLast, true);

        // El contrato del que depende el aviso: en un extremo la CLI no falla
        // (exit 0) y deja el mensaje en stdout, no en stderr. Si esto cambiara,
        // navigate.ts dejaria de tener nada que mostrar.
        const atEnd = gitReview(["next"], repo.dir);
        assert.strictEqual(atEnd.status, 0);
        assert.match(atEnd.stdout, /no more entries/);
        assert.strictEqual(atEnd.stderr.trim(), "");

        // Y la review tiene que seguir siendo valida en posicion 1 despues de
        // intentarlo por el comando, nunca un estado a medias.
        await vscode.commands.executeCommand("gitReview.next");
        state = api.getState();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.position, 1);

        await vscode.commands.executeCommand("gitReview.prev");
        state = api.getState();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.position, 1);

        model = await api.getPanelModel();
        assert.strictEqual(model.atFirst, true);
        assert.strictEqual(model.atLast, true);
    });

    it("correr el verbo en la terminal actualiza el panel sin reabrirlo (AC4, FR-019)", async () => {
        const branch = "us4-external";
        createBranchWithChanges(repo, branch, {"src/x.ts": "x\n", "src/y.ts": "y\n"});
        addWalkthrough(repo, branch, [
            {path: "src/x.ts", why: "x"},
            {path: "src/y.ts", why: "y"},
        ]);
        startReview(repo, branch);

        const api = await getTestApi();
        let state = await api.refresh();
        assert.strictEqual(state.state?.position, 1);

        // "en la terminal": bypassea el comando de la extensión.
        const result = gitReview(["next"], repo.dir);
        assert.strictEqual(result.status, 0);

        state = await waitUntil((s) => s.state?.position === 2, api);
        assert.strictEqual(state.state?.position, 2);
        assert.strictEqual(displayOf(state.entries[1].id), "src/y.ts");
    });
});
