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
 * donde la CLI dijo, y la fila tiene que dejar de decir `absent` sin que nadie
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

async function settle(api: Awaited<ReturnType<typeof getTestApi>>): Promise<void> {
    for (let i = 0; i < 40; i++) {
        await new Promise((resolve) => setTimeout(resolve, 50));
        await api.refresh();
    }
}

/** Espera hasta que `check` se cumpla, refrescando; devuelve si se cumplió. */
async function waitFor(check: () => boolean, tries = 100): Promise<boolean> {
    for (let i = 0; i < tries; i++) {
        if (check()) return true;
        await new Promise((resolve) => setTimeout(resolve, 50));
    }
    return check();
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
            assert.strictEqual(guide.badge, "absent");
            assert.strictEqual(guide.exists, false);
            assert.ok(path.isAbsolute(guide.path), `ruta absoluta: ${guide.path}`);
        }
        // Descartar es solo de la tuya: la compartida es un archivo trackeado.
        assert.strictEqual(model.guides[0]?.discardable, false);
        assert.strictEqual(model.guides[1]?.discardable, false);
    });

    it("Create invoca la CLI, y la fila deja de decir absent sin apretar Refresh", async () => {
        const api = await getTestApi();
        await api.refresh();
        let model = await api.getPanelModel();
        const index = model.guides.findIndex((g) => g.kind === "own");
        assert.ok(index >= 0);

        const file = ownGuidePath(repo.dir);
        assert.strictEqual(fs.existsSync(file), false);

        api.sendPanelMessage("createGuide", index);
        assert.ok(await waitFor(() => fs.existsSync(file)), "la CLI creo el archivo");
        // Vacio a proposito: un esqueleto con placeholders lo leeria el proximo
        // agente como si las instrucciones fueran las convenciones.
        assert.strictEqual(fs.readFileSync(file, "utf8"), "");

        await settle(api);
        model = await api.getPanelModel();
        const own = model.guides.find((g) => g.kind === "own");
        // Creada pero sin contenido: `empty`, que no es `absent` — lo que se
        // ofrece ahora es abrirla, no crearla otra vez.
        assert.strictEqual(own?.state, "empty");
        assert.strictEqual(own?.exists, true);
        assert.strictEqual(own?.discardable, true);
        assert.strictEqual(own?.path, file);
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
            api.sendPanelMessage("discardGuide", index);
            await waitFor(() => asked > 0);
            await new Promise((resolve) => setTimeout(resolve, 300));
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
            api.sendPanelMessage("discardGuide", index);
            await waitFor(() => !fs.existsSync(file));
            await settle(api);
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

        api.sendPanelMessage("createGuide", index);
        await settle(api);
        assert.strictEqual(fs.readFileSync(file, "utf8"), "mis reglas\n");
    });

    it("dentro de una review el bloque sigue, y llega por status --porcelain", async () => {
        // Adentro de una review el panel lee status y ningun otro verbo, asi que
        // que las filas esten ahi prueba que el registro viaja tambien por ese
        // reporte -- si no, dibujarlas costaria una invocacion extra por refresco.
        const branch = "guides-panel-review";
        createBranchWithChanges(repo, branch, {"src/g.ts": "g\n"});
        fs.writeFileSync(ownGuidePath(repo.dir), "mis reglas\n", "utf8");
        // --offline resuelve los dos extremos localmente: esta spec no agrega
        // un origin al fixture, y --local igual iria a buscarlo.
        gitReviewOrThrow(["start", "--offline", branch], repo.dir);

        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const model = await api.getPanelModel();
        assert.deepStrictEqual(model.guides.map((g) => g.kind), ["team", "own"]);
        assert.strictEqual(model.guides.find((g) => g.kind === "own")?.state, "in-force");
        // Y la compartida no se puede crear desde aca: es un archivo del working
        // tree, y la extraccion de finish (git add -A) se lo llevaria al PR de
        // otra persona. La CLI lo niega; el panel lo dice antes.
        assert.strictEqual(model.guides.find((g) => g.kind === "team")?.creatable, false);
    });
});
