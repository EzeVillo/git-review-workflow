import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {PathRef} from "../../src/cli/unquote";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    addWalkthrough,
    createBranchWithChanges,
    git,
    sharedFixtureRepo,
    startReview,
    writeFile
} from "./helpers/fixture";

function displayOf(id: string | PathRef): string {
    return typeof id === "string" ? id : id.display;
}

async function closeAllEditors(): Promise<void> {
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
}

/** `git.openChange` abre el editor de forma asíncrona; sondea hasta que haya un tab activo. */
async function waitForActiveTab(timeoutMs = 5000): Promise<vscode.Tab | undefined> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const tab = vscode.window.tabGroups.activeTabGroup.activeTab;
        if (tab) {
            return tab;
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return vscode.window.tabGroups.activeTabGroup.activeTab;
}

describe("US2: saltar al archivo de una entrada", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        abortReview(repo);
        await closeAllEditors();
    });

    it("el clic abre el archivo correcto, incluidos paths con espacios y no ASCII (AC2), y las ediciones se aplican al working tree (AC1)", async () => {
        const branch = "us2-open";
        const oddPath = "src/raro café con espacios.ts";
        createBranchWithChanges(repo, branch, {
            "src/plain.ts": "export const plain = 1;\n",
            [oddPath]: "export const raro = 1;\n",
        });
        addWalkthrough(repo, branch, [
            {path: "src/plain.ts", why: "plano"},
            {path: oddPath, why: "raro"},
        ]);

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");

        const entry = state.entries.find((e) => displayOf(e.id) === oddPath);
        assert.ok(entry, `no se encontró la entrada para ${oddPath}`);

        await vscode.commands.executeCommand("gitReview.openEntry", entry);
        const editor = vscode.window.activeTextEditor;
        assert.ok(editor, "no se abrió ningún editor");
        assert.strictEqual(path.basename(editor!.document.uri.fsPath), path.basename(oddPath));
        assert.strictEqual(editor!.document.getText(), "export const raro = 1;\n");

        // AC1: editar el documento abierto modifica el working tree de verdad.
        await editor!.edit((builder) => {
            builder.insert(new vscode.Position(0, 0), "// edited by test\n");
        });
        await editor!.document.save();

        const onDisk = fs.readFileSync(path.join(repo.dir, oddPath), "utf8");
        assert.ok(onDisk.startsWith("// edited by test\n"), "la edición no llegó al working tree");
    });

    it("el icono inline de diff recibe el nodo del arbol y abre el diff igual", async () => {
        const branch = "us2-inline-diff";
        createBranchWithChanges(repo, branch, {"src/inline.ts": "export const inline = 1;\n"});
        addWalkthrough(repo, branch, [{path: "src/inline.ts", why: "inline"}]);

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const entry = state.entries[0];

        // Forma EXACTA con la que VS Code invoca un `view/item/context`.
        await vscode.commands.executeCommand("gitReview.openChange", {kind: "entry", entry});
        const tab = await waitForActiveTab();
        assert.ok(tab, "el icono de diff no abrio ningun tab");
        assert.ok(tab!.input instanceof vscode.TabInputTextDiff, `se esperaba un diff, no ${JSON.stringify(tab!.input)}`);
        assert.strictEqual(
            path.basename((tab!.input as vscode.TabInputTextDiff).modified.fsPath),
            "inline.ts"
        );
    });

    it("cae al diff cuando el archivo de la entrada no existe en el working tree (eliminado en el rango, AC3)", async () => {
        // El archivo existe en main; el branch del PR lo elimina, en el mismo
        // commit que agrega otro archivo (así el walkthrough tiene algo más
        // que anotar además del eliminado).
        git(["checkout", "main"], repo.dir);
        writeFile(repo, "src/doomed.ts", "will be deleted\n");
        git(["add", "."], repo.dir);
        git(["commit", "-m", "add doomed.ts on main"], repo.dir);

        const branch = "us2-deleted";
        git(["checkout", "-b", branch], repo.dir);
        fs.rmSync(path.join(repo.dir, "src", "doomed.ts"));
        writeFile(repo, "src/keep.ts", "kept\n");
        git(["add", "-A"], repo.dir);
        git(["commit", "-m", "delete doomed.ts, add keep.ts"], repo.dir);
        git(["checkout", "main"], repo.dir);

        addWalkthrough(repo, branch, [
            {path: "src/doomed.ts", why: "se elimina en este PR"},
            {path: "src/keep.ts", why: "archivo nuevo"},
        ]);

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "walk");

        const entry = state.entries.find((e) => displayOf(e.id) === "src/doomed.ts");
        assert.ok(entry, "no se encontró la entrada para src/doomed.ts");

        const fileUri = vscode.Uri.joinPath(vscode.workspace.workspaceFolders![0].uri, "src/doomed.ts");
        await assert.rejects(async () => {
            await vscode.workspace.fs.stat(fileUri);
        }, "src/doomed.ts no debería existir en el working tree de la review");

        // El comando no debe tirar, y no puede haber abierto el archivo del
        // working tree como texto editable (no existe): git.openChange delega
        // en la extensión de git, que muestra el contenido bajo un esquema
        // propio (diff, o el blob de `git:`) — nunca `file:` sobre el path
        // eliminado.
        await vscode.commands.executeCommand("gitReview.openEntry", entry);
        const activeTab = await waitForActiveTab();
        assert.ok(activeTab, "no se abrió ningún tab");
        const input = activeTab!.input;
        const isPlainFileEditor = input instanceof vscode.TabInputText && input.uri.scheme === "file";
        assert.ok(!isPlainFileEditor, `no debería haber abierto el archivo eliminado como editor de texto plano: ${JSON.stringify(input)}`);
    });

    it("modo step: el clic muestra los cambios del commit, no abre un archivo del working tree", async () => {
        const branch = "us2-step";
        createBranchWithChanges(repo, branch, {"src/step.ts": "step\n"});

        const api = await getTestApi();
        startReview(repo, branch, ["--step"]);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "step");
        assert.strictEqual(state.entries.length, 1);
        assert.strictEqual(typeof state.entries[0].id, "string");

        await vscode.commands.executeCommand("gitReview.openEntry", state.entries[0]);
        // No debe haberse abierto un editor de texto plano para el archivo:
        // modo step delega en la vista de cambios del commit.
        const active = vscode.window.activeTextEditor?.document.uri.fsPath;
        assert.notStrictEqual(active, path.join(repo.dir, "src", "step.ts"));
    });
});
