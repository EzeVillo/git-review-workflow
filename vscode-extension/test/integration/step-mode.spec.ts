import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {entryPickLabel} from "../../src/views/panelModel";
import {closeAllEditors, waitForActiveTab} from "./helpers/editors";
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

    afterEach(async () => {
        abortReview(repo);
        await closeAllEditors();
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

        // El panel muestra el commit actual dentro de la secuencia, y no pide
        // explicaciones: el modo step no las tiene.
        const model = await api.getPanelModel();
        assert.strictEqual(model.mode, "step");
        assert.strictEqual(model.position, 2);
        assert.strictEqual(model.total, 9);
        assert.strictEqual(model.entryCount, 9);
        assert.strictEqual(model.uncoveredCount, 0);
        assert.strictEqual(model.current?.display, state.entries[1].id as string);
        assert.strictEqual(model.current?.banked, false);
        assert.strictEqual(model.why, undefined);

        // Y en el selector, el commit con ediciones guardadas se distingue con texto.
        const picks = state.entries.map((entry) => entryPickLabel(entry, state.state?.position));
        assert.strictEqual(picks[0].description, "con ediciones guardadas");
        assert.strictEqual(picks[1].description, "actual");
        assert.strictEqual(picks[0].label, `01  ${state.entries[0].id as string}`);
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

        const sha = state.entries[1].id as string;
        await vscode.commands.executeCommand("gitReview.openEntry", state.entries[1]);

        // Los cambios del commit, y los del commit *que se pidió*: el tab lleva
        // su SHA. Afirmar sólo que no se abrió el working tree dejaba pasar el
        // caso en que no se abre nada.
        // El label lo compone el host (`Commit <sha> (N files)`); lo que se
        // afirma es el título que pasa la extensión, con el SHA adentro.
        const tab = await waitForActiveTab();
        assert.ok(tab, "el clic en un commit no abrió ninguna vista de cambios");
        assert.ok(
            tab!.label.startsWith(`Commit ${sha.slice(0, 7)}`),
            `el tab abierto no es el del commit pedido: ${tab!.label}`
        );

        // modo step nunca abre el archivo del working tree directamente.
        const active = vscode.window.activeTextEditor?.document.uri.fsPath;
        assert.notStrictEqual(active, path.join(repo.dir, "src", "two.ts"));
    });
});
