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

/**
 * La preview de markdown se abre de forma asíncrona; sondea hasta que haya un
 * tab activo. Margen generoso por la misma razón que en `open-entry.spec.ts`:
 * bajo carga el extension host tarda más que el sondeo original de 5 s.
 */
async function waitForActiveTab(timeoutMs = 20000): Promise<vscode.Tab | undefined> {
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

    it("el panel muestra el why de la entrada actual, y la lectura completa preserva saltos de línea y formato (AC1)", async () => {
        const branch = "us3-why";
        const why = "Primera línea.\n\nSegunda línea, después de una vacía.\n- item uno\n- item dos";
        createBranchWithChanges(repo, branch, {"src/a.ts": "a\n"});
        addWalkthrough(repo, branch, [{path: "src/a.ts", why}]);
        startReview(repo, branch);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const entry = state.entries[0];

        // El why está en el panel sin pedirlo (FR-017). El archivo del
        // walkthrough le agrega un salto de línea final de storage; lo que
        // importa acá es que los saltos de línea INTERNOS (la línea vacía, los
        // ítems de lista) se preserven tal cual.
        const model = await api.getPanelModel();
        assert.strictEqual(model.why?.state, "present");
        assert.strictEqual(model.why?.text?.replace(/\n+$/, ""), why);

        const pathRef = entry.id as { raw: string; display: string };
        const uri = whyUri(pathRef.display, pathRef.raw);
        const doc = await vscode.workspace.openTextDocument(uri);
        assert.strictEqual(doc.getText().replace(/\n+$/, ""), why, "la lectura completa tiene que preservar el texto tal cual, con sus saltos de línea");
    });

    it("el boton del panel abre la lectura completa, igual que la paleta (AC3)", async () => {
        const branch = "us3-why-icon";
        const why = "El porque completo de esta entrada.";
        createBranchWithChanges(repo, branch, {"src/icon.ts": "icon\n"});
        addWalkthrough(repo, branch, [{path: "src/icon.ts", why}]);
        startReview(repo, branch);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const entry = state.entries[0];

        // Forma con la que el panel lo dispara: sin argumento, cayendo en la
        // entrada actual (`resolveEntryArg`).
        await vscode.commands.executeCommand("gitReview.showWhy");
        const tab = await waitForActiveTab();
        assert.ok(tab, "el boton del panel no abrio ningun tab");
        assert.ok(tab!.input instanceof vscode.TabInputWebview, `se esperaba la preview de markdown, no ${JSON.stringify(tab!.input)}`);

        // Y con un EntryRecord explícito, que es como llega desde otros llamadores.
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
        await vscode.commands.executeCommand("gitReview.showWhy", entry);
        const explicitTab = await waitForActiveTab();
        assert.ok(explicitTab, "la invocacion con la entrada explicita no abrio ningun tab");
        assert.ok(explicitTab!.input instanceof vscode.TabInputWebview);
    });

    it("una entrada sin texto se indica sin error (AC2)", async () => {
        const branch = "us3-empty-why";
        createBranchWithChanges(repo, branch, {"src/b.ts": "b\n"});
        addWalkthrough(repo, branch, [{path: "src/b.ts", why: ""}]);
        startReview(repo, branch);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");

        // "sin explicación" es un estado propio, distinto de un fallo (FR-018).
        const model = await api.getPanelModel();
        assert.deepStrictEqual(model.why, {state: "absent"});
    });
});
