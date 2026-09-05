import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    createBranchWithChanges,
    gitReviewOrThrow,
    sharedFixtureRepo,
    withBaseConfigured,
} from "./helpers/fixture";

/**
 * El bloque de guías de autoría del estado vacío.
 *
 * Lo que sólo se puede afirmar acá — y no en los tests unitarios ni en los de
 * contrato — es el tramo que va del control a la CLI y vuelta: *Create* tiene
 * que invocar `git review walkthrough guide`, el archivo tiene que aparecer
 * donde la CLI dijo, y la fila tiene que dejar de decir `none` sin que nadie
 * apriete Refresh. El watcher no mira estos archivos a propósito (el de la guía
 * propia vive en la raíz del gitdir, que cambia en cada operación de git), así
 * que ese refresco lo hace el cliente que creó la guía, dentro del lock.
 */
function ownGuidePath(repoDir: string): string {
    return path.join(repoDir, ".git", "review-walkthrough-guide.md");
}

function teamGuidePath(repoDir: string): string {
    return path.join(repoDir, ".review", "walkthrough-guide.md");
}

/**
 * Canonicaliza un path para compararlo con el que reporta la CLI.
 *
 * Los dos lados nombran el mismo archivo escrito distinto: la CLI lo imprime
 * con barras normales y el nombre largo, mientras que `os.tmpdir()` en el
 * runner de Windows devuelve la forma 8.3 (`RUNNER~1`) que `fs.realpathSync`
 * —a diferencia de su variante `.native`— no expande. Comparar los literales
 * afirma la plataforma que corre la suite, no que el panel abra lo que la CLI
 * dijo.
 */
function canonical(p: string): string {
    let resolved = p;
    try {
        resolved = fs.realpathSync.native(p);
    } catch {
        // Sin archivo no hay nada que expandir: queda el literal.
    }
    const slashed = resolved.split(path.sep).join("/");
    return process.platform === "win32" ? slashed.toLowerCase() : slashed;
}

describe("el bloque de guias de autoria del panel", function () {
    this.timeout(120000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        abortReview(repo);
        withBaseConfigured(repo, "main");
        fs.rmSync(ownGuidePath(repo.dir), {force: true, maxRetries: 10, retryDelay: 50});
        fs.rmSync(teamGuidePath(repo.dir), {force: true, maxRetries: 10, retryDelay: 50});
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    });

    it("las dos filas estan siempre, con el estado que reporto la CLI", async () => {
        const api = await getTestApi();
        assert.strictEqual((await api.refresh()).situation, "no-review");
        const model = await api.getPanelModel();

        // Siempre las dos y en el orden de la CLI: sin la fila, el panel no
        // podria ofrecer crear la que falta sin rearmar su ruta.
        assert.deepStrictEqual(model.guides.map((g) => g.kind), ["team", "own"]);
        assert.deepStrictEqual(
            model.guides.map((g) => g.label),
            ["Repository guide", "Your guide"]
        );
        for (const guide of model.guides) {
            assert.strictEqual(guide.state, "absent");
            assert.strictEqual(guide.badge, "none");
            assert.strictEqual(guide.exists, false);
            assert.ok(path.isAbsolute(guide.path), `ruta absoluta: ${guide.path}`);
        }
        // Descartar es solo de la tuya: la compartida es un archivo trackeado.
        assert.strictEqual(model.guides[0]?.discardable, false);
        assert.strictEqual(model.guides[1]?.discardable, false);
    });

    it("Create invoca la CLI, y la fila deja de decir none sin apretar Refresh", async () => {
        const api = await getTestApi();
        await api.refresh();
        let model = await api.getPanelModel();
        const index = model.guides.findIndex((g) => g.kind === "own");
        assert.ok(index >= 0);

        const file = ownGuidePath(repo.dir);
        assert.strictEqual(fs.existsSync(file), false);

        await api.sendPanelMessage("createGuide", index);
        assert.ok(fs.existsSync(file), "la CLI creo el archivo");
        // Vacio a proposito: un esqueleto con placeholders lo leeria el proximo
        // agente como si las instrucciones fueran las convenciones.
        assert.strictEqual(fs.readFileSync(file, "utf8"), "");

        model = await api.getPanelModel();
        const own = model.guides.find((g) => g.kind === "own");
        // Creada pero sin contenido: `empty`, que no es `absent` — lo que se
        // ofrece ahora es abrirla, no crearla otra vez.
        assert.strictEqual(own?.state, "empty");
        assert.strictEqual(own?.exists, true);
        assert.strictEqual(own?.discardable, true);
        assert.strictEqual(canonical(own!.path), canonical(file));
    });

    it("con contenido la fila pasa a in force", async () => {
        const api = await getTestApi();
        const file = ownGuidePath(repo.dir);
        fs.writeFileSync(file, "marca las migraciones como key\n", "utf8");

        await api.refresh();
        const own = (await api.getPanelModel()).guides.find((g) => g.kind === "own");
        assert.strictEqual(own?.state, "in-force");
        assert.strictEqual(own?.badge, "in force");
    });

    it("una guia de puro whitespace no cuenta como guia", async () => {
        // Misma regla que un borrador vacio: un archivo sin nada adentro no es un
        // conjunto de convenciones, y nombrarlo mandaria al agente a leer lineas
        // en blanco.
        const api = await getTestApi();
        fs.writeFileSync(ownGuidePath(repo.dir), "   \n\t\n", "utf8");
        await api.refresh();
        const own = (await api.getPanelModel()).guides.find((g) => g.kind === "own");
        assert.strictEqual(own?.state, "empty");
    });

    it("Discard pide confirmacion y solo borra si se confirma", async () => {
        const api = await getTestApi();
        const file = ownGuidePath(repo.dir);
        fs.writeFileSync(file, "mis reglas\n", "utf8");
        await api.refresh();
        const index = (await api.getPanelModel()).guides.findIndex((g) => g.kind === "own");
        assert.ok(index >= 0);

        const original = vscode.window.showWarningMessage;
        let asked = 0;
        (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage =
            async (message: string) => {
                asked++;
                assert.ok(message.length > 0, message);
                return undefined;
            };
        try {
            await api.sendPanelMessage("discardGuide", index);
        } finally {
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = original;
        }
        assert.strictEqual(asked, 1, "se pide confirmacion");
        assert.ok(fs.existsSync(file), "sin confirmar no se borra");

        let confirmed = 0;
        (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage =
            async () => {
                confirmed++;
                return "Discard";
            };
        try {
            await api.sendPanelMessage("discardGuide", index);
        } finally {
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = original;
        }
        assert.strictEqual(confirmed, 1);
        assert.strictEqual(fs.existsSync(file), false, "confirmando se borra");
        const own = (await api.getPanelModel()).guides.find((g) => g.kind === "own");
        assert.strictEqual(own?.state, "absent");
    });

    it("Create sobre una guia que ya existe no la pisa", async () => {
        // El host se niega antes de invocar, y la CLI se negaria igual: pisar
        // prosa escrita a mano con un archivo vacio no lo hace nadie.
        const api = await getTestApi();
        const file = ownGuidePath(repo.dir);
        fs.writeFileSync(file, "mis reglas\n", "utf8");
        await api.refresh();
        const index = (await api.getPanelModel()).guides.findIndex((g) => g.kind === "own");

        await api.sendPanelMessage("createGuide", index);
        assert.strictEqual(fs.readFileSync(file, "utf8"), "mis reglas\n");
    });

    it("dentro de una review no hay guias: ni registros ni filas", async () => {
        // Adentro de una review se lee status y ningun otro verbo, y ese reporte no
        // nombra las guias: el panel las dibuja en el pie y una review no tiene
        // pie. Con el archivo escrito y en vigor, que el modelo este vacio prueba
        // las dos puntas a la vez -- la CLI no las reporta ahi y el cliente no
        // rearma nada por su cuenta.
        const branch = "guides-panel-review";
        createBranchWithChanges(repo, branch, {"src/g.ts": "g\n"});
        fs.writeFileSync(ownGuidePath(repo.dir), "mis reglas\n", "utf8");
        // --offline resuelve los dos extremos localmente: esta spec no agrega
        // un origin al fixture, y --local igual iria a buscarlo.
        gitReviewOrThrow(["start", "--offline", branch], repo.dir);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.guides, undefined);
        const model = await api.getPanelModel();
        assert.deepStrictEqual(model.guides, []);
        // Y afuera vuelven a estar, por el verbo que si las reporta.
        gitReviewOrThrow(["abort"], repo.dir);
        const after = await api.refresh();
        assert.strictEqual(after.situation, "no-review");
        assert.deepStrictEqual((after.guides ?? []).map((g) => g.kind), ["team", "own"]);
    });
});
