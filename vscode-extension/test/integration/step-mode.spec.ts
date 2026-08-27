import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {commitChangeResources, readCommitChanges} from "../../src/commands/openEntry";
import {ensureGitApi} from "../../src/review/repository";
import {entryPickLabel} from "../../src/views/panelModel";
import {closeAllEditors, waitForActiveTab} from "./helpers/editors";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    createBranchWithCommits,
    git,
    gitReview,
    sharedFixtureRepo,
    startReview,
    writeFile
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
        assert.strictEqual(model.current?.display, state.entries[1].id as string);
        assert.strictEqual(model.current?.banked, false);
        assert.strictEqual(model.why, undefined);

        // Y en el selector, el commit con ediciones guardadas se distingue con texto.
        const picks = state.entries.map((entry) => entryPickLabel(entry, state.state?.position));
        assert.strictEqual(picks[0].description, "saved edits");
        assert.strictEqual(picks[1].description, "current");
        assert.strictEqual(picks[0].label, `01  ${state.entries[0].id as string}`);
    });

    it("el panel identifica el commit por su asunto y su autor, y los actualiza al navegar (003 US1)", async () => {
        const branch = "us1-003-subject";
        const commits = Array.from({length: 3}, (_, i) => ({
            file: `src/paridad${i + 1}.ts`,
            content: `export const n = ${i + 1};\n`,
            // Asuntos distintos entre sí a propósito: es lo único que distingue
            // "el asunto del commit correcto" de "un asunto cualquiera" si las
            // listas que la CLI deriva quedaran desalineadas.
            message: `feat: paso numero ${i + 1}`,
        }));
        createBranchWithCommits(repo, branch, commits);
        startReview(repo, branch, ["--step"]);

        const api = await getTestApi();
        let state = await api.refresh();
        assert.strictEqual(state.state?.mode, "step");
        assert.strictEqual(state.entries.length, 3);

        // La CLI reporta un asunto y un autor por posición (no un mapa vacío).
        assert.ok(state.subjects, "la CLI instalada no reporto los registros subject");
        assert.ok(state.authors, "la CLI instalada no reporto los registros author");
        assert.strictEqual(state.subjects!.get(1), "feat: paso numero 1");
        assert.strictEqual(state.subjects!.get(3), "feat: paso numero 3");
        assert.strictEqual(state.authors!.get(1), "Test <test@example.com>");

        // Escenario 1: el panel muestra los del commit donde está el cursor.
        let model = await api.getPanelModel();
        assert.strictEqual(model.position, 1);
        assert.strictEqual(model.current?.subject, "feat: paso numero 1");
        assert.strictEqual(model.current?.author, "Test <test@example.com>");
        // El identificador no desaparece: acompaña al asunto.
        assert.strictEqual(model.current?.display, state.entries[0].id as string);

        // Escenario 2: al avanzar muestra los del commit nuevo, sin quedar
        // mostrando los del anterior.
        assert.strictEqual(gitReview(["next"], repo.dir).status, 0);
        state = await api.refresh();
        model = await api.getPanelModel();
        assert.strictEqual(model.position, 2);
        assert.strictEqual(model.current?.subject, "feat: paso numero 2");
        assert.notStrictEqual(model.current?.subject, "feat: paso numero 1");

        // Escenario 3: el selector identifica cada commit por su asunto.
        const picks = state.entries.map((entry) =>
            entryPickLabel(entry, state.state?.position, state.subjects?.get(entry.position)));
        assert.deepStrictEqual(
            picks.map((p) => p.label),
            state.entries.map((entry, i) =>
                `0${i + 1}  ${entry.id as string}  feat: paso numero ${i + 1}`)
        );
    });

    it("un asunto y un autor no ASCII llegan al panel tal cual los escribio su autor (003 US1 escenario 4)", async () => {
        const branch = "us1-003-nonascii";
        const subject = "feat: añadir el café ☕";
        const author = "Ana Muñoz";

        git(["checkout", "-b", branch], repo.dir);
        writeFile(repo, "src/cafe.ts", "export const cafe = true;\n");
        git(["add", "."], repo.dir);
        git(["-c", `user.name=${author}`, "commit", "-m", subject], repo.dir);
        git(["checkout", "main"], repo.dir);

        startReview(repo, branch, ["--step"]);
        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.state?.mode, "step");

        // Byte a byte, sin escapes ni sustituciones (FR-010, SC-006): lo mismo
        // que imprime la terminal.
        const model = await api.getPanelModel();
        assert.strictEqual(model.current?.subject, subject);
        assert.strictEqual(model.current?.author, `${author} <test@example.com>`);
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

        // modo step nunca abre el archivo del working tree directamente. Se
        // afirma sobre el tab y no sobre `activeTextEditor`: `vscode.changes`
        // identifica cada archivo del multi-diff con su Uri `file:`, y el host
        // puede dejar el editor activo ahí aunque ambos lados del diff sean
        // blobs `git:` — comportamiento suyo, distinto entre plataformas.
        const input = tab!.input;
        assert.ok(
            !(input instanceof vscode.TabInputText && input.uri.scheme === "file"),
            `el clic en un commit no puede abrir el working tree como texto plano: ${JSON.stringify(input)}`
        );
    });

    it("los cambios de un commit sólo piden los lados del diff que existen", async function () {
        // El síntoma era mudo —el diff abría igual y el host escupía `Unable to
        // read file 'git:...?ref=<sha>^'` al log—, así que lo que se afirma es
        // el Uri de cada lado y que la extensión de git puede leerlo de verdad.
        const branch = "us6-step-sides";
        git(["checkout", "main"], repo.dir);
        writeFile(repo, "src/base.ts", "base\n");
        git(["add", "."], repo.dir);
        git(["commit", "-m", "add base.ts on main"], repo.dir);

        git(["checkout", "-b", branch], repo.dir);
        writeFile(repo, "src/added.ts", "added\n");
        git(["add", "."], repo.dir);
        git(["commit", "-m", "add added.ts"], repo.dir);
        writeFile(repo, "src/base.ts", "base modificado\n");
        git(["add", "."], repo.dir);
        git(["commit", "-m", "modify base.ts"], repo.dir);
        fs.rmSync(path.join(repo.dir, "src", "base.ts"));
        git(["add", "-A"], repo.dir);
        git(["commit", "-m", "delete base.ts"], repo.dir);
        git(["checkout", "main"], repo.dir);

        startReview(repo, branch, ["--step"]);
        const api = await getTestApi();
        const state = await api.refresh();
        assert.strictEqual(state.state?.mode, "step");
        assert.strictEqual(state.entries.length, 3);

        const rootUri = vscode.workspace.workspaceFolders![0].uri;
        const gitApi = await ensureGitApi();
        assert.ok(gitApi, "la extensión de git no expuso su API");

        const commits = [];
        for (const entry of state.entries) {
            const sha = entry.id as string;
            const changes = await readCommitChanges(rootUri, sha);
            assert.ok(changes, `no se pudieron leer los archivos del commit ${sha}`);
            commits.push({sha, resources: commitChangeResources(gitApi!, rootUri, sha, changes!)});
        }

        // 1. agrega un archivo: no hay lado izquierdo que pedir.
        assert.strictEqual(commits[0].resources.length, 1);
        const [addedUri, addedLeft, addedRight] = commits[0].resources[0];
        assert.strictEqual(path.basename(addedUri.fsPath), "added.ts");
        assert.strictEqual(addedLeft, undefined, "un archivo agregado no existe en el commit padre");
        assert.ok(addedRight, "falta el lado derecho del archivo agregado");

        // 2. lo modifica: los dos lados.
        assert.strictEqual(commits[1].resources.length, 1);
        const [modifiedUri, modifiedLeft, modifiedRight] = commits[1].resources[0];
        assert.strictEqual(path.basename(modifiedUri.fsPath), "base.ts");
        assert.ok(modifiedLeft, "falta el lado izquierdo del archivo modificado");
        assert.ok(modifiedRight, "falta el lado derecho del archivo modificado");

        // 3. lo elimina: no hay lado derecho que pedir.
        assert.strictEqual(commits[2].resources.length, 1);
        const [deletedUri, deletedLeft, deletedRight] = commits[2].resources[0];
        assert.strictEqual(path.basename(deletedUri.fsPath), "base.ts");
        assert.ok(deletedLeft, "falta el lado izquierdo del archivo eliminado");
        assert.strictEqual(deletedRight, undefined, "un archivo eliminado no existe en el commit");

        // Todo Uri que se pasa tiene que ser legible: ésa es la lectura que
        // fallaba. Y el contenido es el del ref pedido, no el del working tree.
        const read = async (uri: vscode.Uri) =>
            Buffer.from(await vscode.workspace.fs.readFile(uri)).toString("utf8");
        for (const commit of commits) {
            for (const [, left, right] of commit.resources) {
                for (const side of [left, right]) {
                    if (!side) {
                        continue;
                    }
                    await assert.doesNotReject(
                        async () => read(side),
                        `la extensión de git no pudo leer ${side.toString()} (commit ${commit.sha})`
                    );
                }
            }
        }
        assert.strictEqual(await read(addedRight!), "added\n");
        assert.strictEqual(await read(modifiedLeft!), "base\n");
        assert.strictEqual(await read(modifiedRight!), "base modificado\n");
        assert.strictEqual(await read(deletedLeft!), "base modificado\n");

        // Y el comando sigue abriendo la vista de cambios del commit pedido.
        await vscode.commands.executeCommand("gitReview.openEntry", state.entries[0]);
        const tab = await waitForActiveTab();
        assert.ok(tab, "el commit que agrega un archivo no abrió ninguna vista de cambios");
        assert.ok(
            tab!.label.startsWith(`Commit ${commits[0].sha.slice(0, 7)}`),
            `el tab abierto no es el del commit pedido: ${tab!.label}`
        );
    });
});
