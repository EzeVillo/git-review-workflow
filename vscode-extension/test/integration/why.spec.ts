import * as assert from "node:assert";
import * as vscode from "vscode";
import {whyUri} from "../../src/views/whyContentProvider";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    addWalkthrough,
    createBranchWithChanges,
    sharedFixtureRepo,
    startReview
} from "./helpers/fixture";

/** La preview de markdown se abre de forma asíncrona; sondea hasta que haya un tab activo. */
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

describe("US3: leer el porqué de cada entrada", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        abortReview(repo);
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    });

    it("el hover muestra el why, y la lectura completa preserva saltos de línea y formato (AC1)", async () => {
        const branch = "us3-why";
        const why = "Primera línea.\n\nSegunda línea, después de una vacía.\n- item uno\n- item dos";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        addWalkthrough(repo, branch, [{path: "src/a.ts", why}]);
        startReview(repo, branch);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const entry = state.entries[0];

        const treeProvider = api.getTreeProvider();
        const baseItem = treeProvider.getTreeItem({kind: "entry", entry});
        const resolved = await treeProvider.resolveTreeItem(baseItem, {kind: "entry", entry});
        assert.ok(resolved.tooltip instanceof vscode.MarkdownString, "el tooltip debería ser un MarkdownString con el why");
        // El archivo del walkthrough le agrega un salto de línea final de
        // storage; lo que importa acá es que los saltos de línea INTERNOS
        // (la línea vacía, los ítems de lista) se preserven tal cual.
        assert.strictEqual((resolved.tooltip as vscode.MarkdownString).value.replace(/\n+$/, ""), why);

        const pathRef = entry.id as { raw: string; display: string };
        const uri = whyUri(pathRef.display, pathRef.raw);
        const doc = await vscode.workspace.openTextDocument(uri);
        assert.strictEqual(doc.getText().replace(/\n+$/, ""), why, "la lectura completa tiene que preservar el texto tal cual, con sus saltos de línea");
    });

    it("el icono inline abre el why aunque el menu pase el nodo del arbol y no el EntryRecord", async () => {
        const branch = "us3-why-icon";
        const why = "El porque completo de esta entrada.";
        createBranchWithChanges(repo, branch, {"src/icon.ts": "icon\n"});
        addWalkthrough(repo, branch, [{path: "src/icon.ts", why}]);
        startReview(repo, branch);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const entry = state.entries[0];

        // Forma EXACTA con la que VS Code invoca un `view/item/context`: el
        // elemento del TreeDataProvider, no el `arguments` de TreeItem.command.
        await vscode.commands.executeCommand("gitReview.showWhy", {kind: "entry", entry});
        const tab = await waitForActiveTab();
        assert.ok(tab, "el icono no abrio ningun tab");
        assert.ok(tab!.input instanceof vscode.TabInputWebview, `se esperaba la preview de markdown, no ${JSON.stringify(tab!.input)}`);

        // Y el mismo comando desde la paleta (sin argumento) cae en la entrada actual.
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
        await vscode.commands.executeCommand("gitReview.showWhy");
        const paletteTab = await waitForActiveTab();
        assert.ok(paletteTab, "la invocacion sin argumento no abrio ningun tab");
        assert.ok(paletteTab!.input instanceof vscode.TabInputWebview);
    });

    it("una entrada sin texto se indica sin error (AC2)", async () => {
        const branch = "us3-empty-why";
        createBranchWithChanges(repo, branch, {"src/b.ts": "b\n"});
        addWalkthrough(repo, branch, [{path: "src/b.ts", why: ""}]);
        startReview(repo, branch);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const entry = state.entries[0];

        const treeProvider = api.getTreeProvider();
        const baseItem = treeProvider.getTreeItem({kind: "entry", entry});
        const resolved = await treeProvider.resolveTreeItem(baseItem, {kind: "entry", entry});
        assert.strictEqual(resolved.tooltip, "(sin explicación)");
    });
});
