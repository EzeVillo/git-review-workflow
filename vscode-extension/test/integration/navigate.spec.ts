import * as assert from "node:assert";
import * as vscode from "vscode";
import {PathRef} from "../../src/cli/unquote";
import {GitReviewTestApi} from "../../src/extension";
import {ReviewState} from "../../src/review/state";
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

    afterEach(() => {
        abortReview(repo);
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

        await vscode.commands.executeCommand("gitReview.next");
        state = api.getState();
        assert.strictEqual(state.state?.position, 2);
        let porcelain = gitReview(["status", "--porcelain"], repo.dir);
        assert.match(porcelain.stdout.split("\n")[0], /\t2\t3\t3\t/);

        await vscode.commands.executeCommand("gitReview.next");
        state = api.getState();
        assert.strictEqual(state.state?.position, 3);

        await vscode.commands.executeCommand("gitReview.prev");
        state = api.getState();
        assert.strictEqual(state.state?.position, 2);
        porcelain = gitReview(["status", "--porcelain"], repo.dir);
        assert.match(porcelain.stdout.split("\n")[0], /\t2\t3\t3\t/);
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

        // Ya en la última (y única) entrada: la CLI no falla, no-opea ("no
        // more entries" queda en stdout, que la extensión nunca lee — FR-015).
        // El panel tiene que seguir reflejando una review válida en
        // posición 1, nunca un estado a medias.
        await vscode.commands.executeCommand("gitReview.next");
        state = api.getState();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.position, 1);

        await vscode.commands.executeCommand("gitReview.prev");
        state = api.getState();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.position, 1);
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
