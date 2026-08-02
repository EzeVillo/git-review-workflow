import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    createBranchWithCommits,
    gitReview,
    sharedFixtureRepo,
    startReview
} from "./helpers/fixture";

describe("US6: revisar commit por commit", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(() => {
        abortReview(repo);
    });

    it("lista los commits en orden, marca el actual, distingue el que tiene ediciones guardadas (AC1)", async () => {
        const branch = "us6-step";
        const commits = Array.from({length: 9}, (_, i) => ({
            file: `src/file${i + 1}.ts`,
            content: `export const n = ${i + 1};\n`,
            message: `commit ${i + 1}`,
        }));
        createBranchWithCommits(repo, branch, commits);
        startReview(repo, branch, ["--step"]);

        const api = await getTestApi();
        let state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "step");
        assert.strictEqual(state.state?.total, 9);
        assert.strictEqual(state.entries.length, 9);
        assert.strictEqual(state.state?.position, 1);
        assert.ok(state.entries.every((e) => e.banked === false));

        // Editar el commit actual (1) y avanzar: la CLI banquea la edición.
        fs.writeFileSync(path.join(repo.dir, "src", "file1.ts"), "export const n = 999;\n");
        const next = gitReview(["next"], repo.dir);
        assert.strictEqual(next.status, 0);

        state = await api.refresh();
        assert.strictEqual(state.state?.position, 2);
        assert.strictEqual(state.entries[0].banked, true, "el commit 1 tendría que quedar marcado con ediciones guardadas");
        assert.strictEqual(state.entries[1].banked, false);

        // El orden de las entradas es el de la CLI (rev-list), no alfabético
        // por SHA ni por archivo.
        const cliOrder = gitReview(["status", "--porcelain"], repo.dir)
            .stdout.split("\n")
            .filter((l) => l.startsWith("entry\t"))
            .map((l) => l.split("\t")[2]);
        const treeOrder = state.entries.map((e) => e.id as string);
        assert.deepStrictEqual(treeOrder, cliOrder);

        const treeProvider = api.getTreeProvider();
        const bankedItem = treeProvider.getTreeItem({kind: "entry", entry: state.entries[0]});
        assert.strictEqual(bankedItem.description, "con ediciones guardadas");
        const currentItem = treeProvider.getTreeItem({kind: "entry", entry: state.entries[1]});
        assert.notStrictEqual(currentItem.description, "con ediciones guardadas");
    });

    it("el clic en un commit muestra sus cambios, no un archivo del working tree (AC2)", async () => {
        const branch = "us6-step-click";
        createBranchWithCommits(repo, branch, [
            {file: "src/one.ts", content: "one\n", message: "first"},
            {file: "src/two.ts", content: "two\n", message: "second"},
        ]);
        startReview(repo, branch, ["--step"]);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.state?.mode, "step");

        await vscode.commands.executeCommand("gitReview.openEntry", state.entries[1]);
        // modo step nunca abre el archivo del working tree directamente.
        const active = vscode.window.activeTextEditor?.document.uri.fsPath;
        assert.notStrictEqual(active, path.join(repo.dir, "src", "two.ts"));
    });
});
