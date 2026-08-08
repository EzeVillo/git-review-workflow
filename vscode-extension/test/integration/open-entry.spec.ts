import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {PathRef} from "../../src/cli/unquote";
import {closeAllEditors, snapshotTabs, waitForActiveTab, waitForNewTab} from "./helpers/editors";
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

    it("el boton del panel abre los cambios, sin argumento y cayendo en la entrada actual", async () => {
        const branch = "us2-inline-diff";
        createBranchWithChanges(repo, branch, {"src/inline.ts": "export const inline = 1;\n"});
        addWalkthrough(repo, branch, [{path: "src/inline.ts", why: "inline"}]);

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.position, 1);

        // Forma EXACTA con la que el panel lo dispara: sin argumento
        // (`resolveEntryArg` cae en la entrada de `state.position`).
        const previousTabs = snapshotTabs();
        await vscode.commands.executeCommand("gitReview.openChange");
        const tab = await waitForNewTab(previousTabs, (candidate) => {
            const input = candidate.input;
            if (input instanceof vscode.TabInputTextDiff) {
                return path.basename(input.modified.fsPath) === "inline.ts";
            }
            if (input instanceof vscode.TabInputText) {
                return path.basename(input.uri.fsPath) === "inline.ts";
            }
            return false;
        }) ?? await waitForActiveTab();
        assert.ok(tab, "el boton de cambios no abrio ningun tab");

        // `src/inline.ts` lo agrega el PR: no hay lado izquierdo con el que
        // comparar, así que la vista de cambios es el contenido que el PR
        // agrega, como documento `git:` de sólo lectura. Lo que se afirma es la
        // garantía que vale para cualquiera de las dos formas: esto NO es el
        // archivo del working tree abierto como texto plano — ésa es la otra
        // acción, `openEntry`.
        const input = tab!.input;
        const isPlainFileEditor = input instanceof vscode.TabInputText && input.uri.scheme === "file";
        assert.ok(!isPlainFileEditor, `openChange no puede abrir el working tree como texto plano: ${JSON.stringify(input)}`);

        const shownPath = input instanceof vscode.TabInputTextDiff
            ? input.modified.fsPath
            : (input as vscode.TabInputText).uri.fsPath;
        assert.strictEqual(path.basename(shownPath), "inline.ts");
    });

    it("un archivo modificado abre el diff de los dos lados, contra el working tree", async () => {
        // El archivo ya existe en la base, asi que hay lado izquierdo (el
        // merge-base) y derecho. Es el caso que la delegacion en
        // `git.openChange` dejaba sin abrir mientras la extension de git no
        // hubiera terminado de escanear el repo: el sintoma era mudo, ningun
        // tab y ningun error. Los lados salen de `git diff HEAD`, que esta al
        // dia siempre.
        git(["checkout", "main"], repo.dir);
        writeFile(repo, "src/tracked.ts", "export const tracked = 0;\n");
        git(["add", "."], repo.dir);
        git(["commit", "-m", "add tracked.ts on main"], repo.dir);

        const branch = "us2-modified-diff";
        createBranchWithChanges(repo, branch, {"src/tracked.ts": "export const tracked = 1;\n"});
        addWalkthrough(repo, branch, [{path: "src/tracked.ts", why: "modificado"}]);

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        const entry = state.entries.find((e) => displayOf(e.id) === "src/tracked.ts");
        assert.ok(entry, "no se encontró la entrada para src/tracked.ts");

        await closeAllEditors();
        const previousTabs = snapshotTabs();
        await vscode.commands.executeCommand("gitReview.openChange", entry);
        const tab = await waitForNewTab(
            previousTabs,
            (candidate) => candidate.input instanceof vscode.TabInputTextDiff
        );
        assert.ok(tab, "no se abrió el diff del archivo modificado");

        const input = tab!.input as vscode.TabInputTextDiff;
        // Izquierda: el blob del merge-base, documento `git:` de sólo lectura.
        assert.strictEqual(input.original.scheme, "git");
        assert.ok(
            input.original.fsPath.endsWith(path.normalize("src/tracked.ts")),
            `el lado izquierdo no es tracked.ts: ${input.original.fsPath}`
        );
        // Derecha: el working tree. Es lo que hace editable el diff, que es el
        // flujo entero de `git review` — un blob `git:` de los dos lados (lo
        // que mostraba `git.openChange`) sería de sólo lectura.
        assert.strictEqual(input.modified.scheme, "file");
        assert.ok(
            input.modified.fsPath.endsWith(path.normalize("src/tracked.ts")),
            `el lado derecho no es el working tree de tracked.ts: ${input.modified.fsPath}`
        );
        assert.strictEqual(
            fs.readFileSync(input.modified.fsPath, "utf8"),
            "export const tracked = 1;\n"
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
        // working tree como texto editable (no existe): openEntry cae al blob
        // en HEAD — nunca `file:` sobre el path eliminado.
        await closeAllEditors();
        const previousTabs = snapshotTabs();
        await vscode.commands.executeCommand("gitReview.openEntry", entry);
        const activeTab =
            (await waitForNewTab(
                previousTabs,
                (candidate) => {
                    const input = candidate.input;
                    if (input instanceof vscode.TabInputTextDiff) {
                        return true;
                    }
                    if (input instanceof vscode.TabInputText) {
                        return input.uri.scheme !== "file";
                    }
                    return false;
                },
                30000
            )) ??
            (await waitForNewTab(previousTabs, undefined, 30000)) ??
            (await waitForActiveTab(30000));
        assert.ok(activeTab, "no se abrió ningún tab");
        const input = activeTab!.input;
        const isPlainFileEditor = input instanceof vscode.TabInputText && input.uri.scheme === "file";
        assert.ok(!isPlainFileEditor, `no debería haber abierto el archivo eliminado como editor de texto plano: ${JSON.stringify(input)}`);
    });

    it("modo whole: una entrada de la lista abre el archivo correcto (US2/004)", async () => {
        // Sin walkthrough: entra en whole, con la lista de FR-001 en vez de la
        // secuencia curada. El mismo comando que usa walk abre la entrada,
        // resuelta desde state.entries igual que allá — sin cursor.
        const branch = "us2-whole-open";
        const oddPath = "src/raro café con espacios.ts";
        createBranchWithChanges(repo, branch, {
            "src/plain.ts": "export const plain = 1;\n",
            [oddPath]: "export const raro = 1;\n",
        });

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "whole");
        assert.strictEqual(state.state?.position, undefined, "whole no tiene cursor");

        const entry = state.entries.find((e) => displayOf(e.id) === oddPath);
        assert.ok(entry, `no se encontró la entrada para ${oddPath} en el listado de whole`);

        await vscode.commands.executeCommand("gitReview.openEntry", entry);
        const editor = vscode.window.activeTextEditor;
        assert.ok(editor, "no se abrió ningún editor");
        // El path relativo entero, no sólo el basename: es lo que distingue
        // este archivo de otro con el mismo nombre en otra carpeta.
        const openedPath = editor!.document.uri.fsPath;
        assert.ok(
            openedPath.endsWith(path.normalize(oddPath)),
            `se abrió otro archivo: ${openedPath}`
        );
        // El contenido se lee del disco y no de `document.getText()`: el host
        // cachea el TextDocument por Uri, y el primer escenario de este archivo
        // abre y edita este mismo path a propósito (AC1). Al reabrirlo devuelve
        // el modelo viejo — medido en Linux: en disco
        // "export const raro = 1;\n" y en el documento
        // "// edited by test\nexport const raro = 1;\n", con isDirty en false.
        // Eso es caché del host, no lo que la extensión abrió.
        assert.strictEqual(
            fs.readFileSync(path.join(repo.dir, oddPath), "utf8"),
            "export const raro = 1;\n"
        );
    });

    it("modo whole: un archivo eliminado en el rango cae al diff, igual que en walk", async () => {
        git(["checkout", "main"], repo.dir);
        writeFile(repo, "src/doomed-whole.ts", "will be deleted\n");
        git(["add", "."], repo.dir);
        git(["commit", "-m", "add doomed-whole.ts on main"], repo.dir);

        const branch = "us2-whole-deleted";
        git(["checkout", "-b", branch], repo.dir);
        fs.rmSync(path.join(repo.dir, "src", "doomed-whole.ts"));
        writeFile(repo, "src/keep-whole.ts", "kept\n");
        git(["add", "-A"], repo.dir);
        git(["commit", "-m", "delete doomed-whole.ts, add keep-whole.ts"], repo.dir);
        git(["checkout", "main"], repo.dir);

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "whole");

        const entry = state.entries.find((e) => displayOf(e.id) === "src/doomed-whole.ts");
        assert.ok(entry, "no se encontró la entrada para src/doomed-whole.ts en whole");

        await closeAllEditors();
        const previousTabs = snapshotTabs();
        await vscode.commands.executeCommand("gitReview.openEntry", entry);
        // Path eliminado: openEntry abre el blob en HEAD (esquema git:) o un
        // diff — nunca un TabInputText file: del working tree.
        const activeTab =
            (await waitForNewTab(
                previousTabs,
                (candidate) => {
                    const input = candidate.input;
                    if (input instanceof vscode.TabInputTextDiff) {
                        return true;
                    }
                    if (input instanceof vscode.TabInputText) {
                        return input.uri.scheme !== "file";
                    }
                    return false;
                },
                30000
            )) ??
            (await waitForNewTab(previousTabs, undefined, 30000)) ??
            (await waitForActiveTab(30000));
        assert.ok(activeTab, "no se abrió ningún tab");
        const input = activeTab!.input;
        const isPlainFileEditor = input instanceof vscode.TabInputText && input.uri.scheme === "file";
        assert.ok(!isPlainFileEditor, `no debería haber abierto el archivo eliminado como editor de texto plano: ${JSON.stringify(input)}`);
    });

    it("modo whole: abrir una fila la deja marcada en el modelo del panel", async () => {
        // La marca no la deriva la CLI —whole no tiene cursor—: la registra el
        // host cuando el panel abre una fila, y viaja al webview en el modelo.
        const branch = "us2-whole-mark";
        createBranchWithChanges(repo, branch, {
            "src/first.ts": "export const first = 1;\n",
            "src/second.ts": "export const second = 2;\n",
        });

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.situation, "review");
        assert.strictEqual(state.state?.mode, "whole");

        const before = await api.getPanelModel();
        assert.strictEqual(before.lastOpened, undefined, "una review recién abierta no tiene fila marcada");

        const entry = state.entries.find((e) => displayOf(e.id) === "src/second.ts");
        assert.ok(entry, "no se encontró la entrada para src/second.ts");

        await vscode.commands.executeCommand("gitReview.openChange", entry);
        const after = await api.getPanelModel();
        assert.strictEqual(after.lastOpened, "src/second.ts");
        // Y es UNA fila: abrir otra mueve la marca, no agrega una segunda.
        const other = state.entries.find((e) => displayOf(e.id) === "src/first.ts");
        assert.ok(other, "no se encontró la entrada para src/first.ts");
        await vscode.commands.executeCommand("gitReview.openChange", other);
        assert.strictEqual((await api.getPanelModel()).lastOpened, "src/first.ts");
    });

    it("modo walk: abrir una entrada no deja marca, porque el cursor ya la muestra", async () => {
        const branch = "us2-walk-mark";
        createBranchWithChanges(repo, branch, {"src/walkmark.ts": "export const m = 1;\n"});
        addWalkthrough(repo, branch, [{path: "src/walkmark.ts", why: "marcado"}]);

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.state?.mode, "walk");

        await vscode.commands.executeCommand("gitReview.openEntry", state.entries[0]);
        const model = await api.getPanelModel();
        assert.strictEqual(model.lastOpened, undefined);
    });

    it("modo whole: el boton de diff abre todos los cambios del rango en una sola vista", async () => {
        const branch = "us2-whole-all";
        createBranchWithChanges(repo, branch, {
            "src/all-a.ts": "export const a = 1;\n",
            "src/all-b.ts": "export const b = 2;\n",
        });

        const api = await getTestApi();
        startReview(repo, branch);
        const state = await api.refresh();
        assert.strictEqual(state.state?.mode, "whole");
        assert.strictEqual(state.state?.source, branch);

        // Forma EXACTA con la que el panel lo dispara: sin argumento, porque la
        // unidad es el rango entero y no una fila.
        await vscode.commands.executeCommand("gitReview.openAllChanges");
        const tab = await waitForActiveTab();
        assert.ok(tab, "el boton de diff no abrio ninguna vista de cambios");
        // El label lo compone el host a partir del título que pasa la extensión
        // (`Review <source>`), igual que `Commit <sha>` en step.
        assert.ok(
            tab!.label.startsWith(`Review ${branch}`),
            `el tab abierto no es el de los cambios del rango: ${tab!.label}`
        );
        // Y no es el archivo del working tree abierto como texto plano: eso
        // sería haber caído en la acción de una fila.
        const input = tab!.input;
        assert.ok(
            !(input instanceof vscode.TabInputText && input.uri.scheme === "file"),
            `openAllChanges no puede abrir un archivo suelto: ${JSON.stringify(input)}`
        );
        // Abrir el rango completo no es haber llegado a ninguna fila.
        assert.strictEqual((await api.getPanelModel()).lastOpened, undefined);
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

        const sha = state.entries[0].id as string;
        await vscode.commands.executeCommand("gitReview.openEntry", state.entries[0]);

        // No basta con que no se haya abierto el archivo del working tree: eso
        // también se cumple cuando no se abre nada, que es justo como fallaba
        // esto cuando la API de git se resolvía una sola vez al activar y la
        // extensión de git todavía no había cargado. El tab tiene que existir y
        // ser el del commit.
        // El label lo compone el host (`Commit <sha> (N files)`); lo que se
        // afirma es el título que pasa la extensión, con el SHA adentro.
        const tab = await waitForActiveTab();
        assert.ok(tab, "el clic en un commit no abrió ninguna vista de cambios");
        assert.ok(
            tab!.label.startsWith(`Commit ${sha.slice(0, 7)}`),
            `el tab abierto no es el de los cambios del commit: ${tab!.label}`
        );

        // Sobre el tab, no sobre `activeTextEditor`: el multi-diff identifica
        // cada archivo con el Uri `file:` del working tree (es el primer
        // elemento de la terna que recibe `vscode.changes`), y el host puede
        // dejar el editor activo apuntando ahí aunque los dos lados del diff
        // sean blobs `git:`. Eso lo decide el host y difiere entre plataformas
        // — en Linux el editor activo es ese `file:` y en Windows no—, así que
        // afirmarlo probaba el host y no la extensión. Lo que la extensión
        // garantiza, y lo que aquí se afirma, es que la pestaña abierta no es
        // el archivo suelto: ésa es la otra acción (`openEntry`, el botón
        // "File"). Misma forma que el test del rango completo, más arriba.
        const input = tab!.input;
        assert.ok(
            !(input instanceof vscode.TabInputText && input.uri.scheme === "file"),
            `el clic en un commit no puede abrir el working tree como texto plano: ${JSON.stringify(input)}`
        );
    });
});
