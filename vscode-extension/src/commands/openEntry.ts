import * as cp from "node:child_process";
import * as vscode from "vscode";
import {EntryRecord, ReviewMode} from "../cli/porcelain";
import {PathRef} from "../cli/unquote";
import {GitApi} from "../review/repository";

function isPathRef(id: string | PathRef): id is PathRef {
    return typeof id !== "string";
}

/**
 * Comando `gitReview.openEntry`. En modo walk, abre el documento del working
 * tree de la entrada; si el archivo no existe (eliminado en el rango), cae al
 * diff. En modo step, muestra los cambios del commit (research.md Decisión 10).
 */
export async function openEntry(rootUri: vscode.Uri, mode: ReviewMode, entry: EntryRecord, gitApi: GitApi | undefined): Promise<void> {
    if (mode === "step") {
        if (typeof entry.id === "string") {
            await openCommitChanges(gitApi, rootUri, entry.id);
        }
        return;
    }

    if (!isPathRef(entry.id)) {
        return;
    }
    const fileUri = vscode.Uri.joinPath(rootUri, entry.id.display);
    try {
        await vscode.workspace.fs.stat(fileUri);
    } catch {
        // Archivo eliminado en el rango: la única superficie con contenido es el diff.
        await vscode.commands.executeCommand("git.openChange", fileUri);
        return;
    }
    const document = await vscode.workspace.openTextDocument(fileUri);
    await vscode.window.showTextDocument(document);
}

/** Comando `gitReview.openChange` — siempre el diff, nunca el archivo del working tree. */
export async function openChange(rootUri: vscode.Uri, mode: ReviewMode, entry: EntryRecord, gitApi: GitApi | undefined): Promise<void> {
    if (mode === "step") {
        if (typeof entry.id === "string") {
            await openCommitChanges(gitApi, rootUri, entry.id);
        }
        return;
    }
    if (!isPathRef(entry.id)) {
        return;
    }
    await vscode.commands.executeCommand("git.openChange", vscode.Uri.joinPath(rootUri, entry.id.display));
}

async function openCommitChanges(gitApi: GitApi | undefined, rootUri: vscode.Uri, sha: string): Promise<void> {
    if (!gitApi) {
        void vscode.window.showWarningMessage("La extensión de git no está disponible para mostrar el diff del commit.");
        return;
    }
    let output: string;
    try {
        output = cp.execFileSync("git", ["show", "--name-only", "--pretty=format:", sha], {
            cwd: rootUri.fsPath,
            encoding: "utf8",
        });
    } catch {
        void vscode.window.showErrorMessage(`No se pudo leer los archivos del commit ${sha}.`);
        return;
    }
    const files = output
        .split("\n")
        .map((f) => f.trim())
        .filter((f) => f.length > 0);
    if (files.length === 0) {
        void vscode.window.showInformationMessage(`El commit ${sha} no cambia archivos.`);
        return;
    }
    const resources: [vscode.Uri, vscode.Uri, vscode.Uri][] = files.map((f) => {
        const fileUri = vscode.Uri.joinPath(rootUri, f);
        return [fileUri, gitApi.toGitUri(fileUri, `${sha}^`), gitApi.toGitUri(fileUri, sha)];
    });
    await vscode.commands.executeCommand("vscode.changes", `Commit ${sha.slice(0, 7)}`, resources);
}
