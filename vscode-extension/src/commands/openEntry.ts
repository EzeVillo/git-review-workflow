import * as cp from "node:child_process";
import * as vscode from "vscode";
import {CommitChange, parseNameStatus} from "../cli/nameStatus";
import {EntryRecord, ReviewMode} from "../cli/porcelain";
import {PathRef} from "../cli/unquote";
import {ensureGitApi, GitApi, gitApiUnavailableReason} from "../review/repository";

function isPathRef(id: string | PathRef): id is PathRef {
    return typeof id !== "string";
}

/**
 * Comando `gitReview.openEntry`. En modo walk, abre el documento del working
 * tree de la entrada; si el archivo no existe (eliminado en el rango), cae al
 * diff. En modo step, muestra los cambios del commit (research.md Decisión 10).
 */
export async function openEntry(rootUri: vscode.Uri, mode: ReviewMode, entry: EntryRecord): Promise<void> {
    if (mode === "step") {
        if (typeof entry.id === "string") {
            await openCommitChanges(rootUri, entry.id);
        }
        return;
    }

    if (!isPathRef(entry.id)) {
        return;
    }
    await openWorkingTreeFile(rootUri, entry.id.display);
}

/**
 * Abre el archivo del working tree —que en una review *es* el PR aplicado— y
 * cae al diff si no existe (eliminado en el rango). Lo usan por igual las
 * entradas de la secuencia y los archivos sin cobertura.
 */
export async function openWorkingTreeFile(rootUri: vscode.Uri, display: string): Promise<void> {
    const fileUri = vscode.Uri.joinPath(rootUri, display);
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
export async function openChange(rootUri: vscode.Uri, mode: ReviewMode, entry: EntryRecord): Promise<void> {
    if (mode === "step") {
        if (typeof entry.id === "string") {
            await openCommitChanges(rootUri, entry.id);
        }
        return;
    }
    if (!isPathRef(entry.id)) {
        return;
    }
    await vscode.commands.executeCommand("git.openChange", vscode.Uri.joinPath(rootUri, entry.id.display));
}

/**
 * Sin API de git no hay diff de commit que mostrar, pero *por qué* no la hay
 * cambia lo que el revisor tiene que hacer: confiar en la carpeta, habilitar la
 * extensión, o simplemente esperar. Un solo mensaje para las tres cosas era un
 * callejón sin salida.
 */
async function reportMissingGitApi(): Promise<void> {
    switch (gitApiUnavailableReason()) {
        case "untrusted": {
            const manage = "Manage Trust";
            const choice = await vscode.window.showWarningMessage(
                "Showing a commit's changes needs the git extension, and VS Code disables it while this folder is in restricted mode. Trust the folder to enable it.",
                manage
            );
            if (choice === manage) {
                await vscode.commands.executeCommand("workbench.trust.manage");
            }
            return;
        }
        case "missing":
            void vscode.window.showWarningMessage(
                "The built-in git extension is disabled: enable it to see a commit's changes."
            );
            return;
        default:
            void vscode.window.showWarningMessage(
                "The git extension has not finished loading yet. Try again in a few seconds."
            );
    }
}

/**
 * Los tres Uri que `vscode.changes` pide por archivo: con qué se lo identifica,
 * el lado izquierdo y el derecho. Un lado `undefined` es cómo se dice "de este
 * lado el archivo no existe" —el commit lo agrega, o lo elimina—; poner ahí el
 * Uri `git:` de un blob inexistente es justo lo que hace fallar la lectura.
 */
export function commitChangeResources(
    gitApi: GitApi,
    rootUri: vscode.Uri,
    sha: string,
    changes: CommitChange[]
): [vscode.Uri, vscode.Uri | undefined, vscode.Uri | undefined][] {
    const gitUri = (path: string, ref: string) => gitApi.toGitUri(vscode.Uri.joinPath(rootUri, path), ref);
    return changes.map((change) => [
        vscode.Uri.joinPath(rootUri, change.path),
        change.before === undefined ? undefined : gitUri(change.before, `${sha}^`),
        change.after === undefined ? undefined : gitUri(change.after, sha),
    ]);
}

/**
 * Los archivos que toca un commit, o `undefined` si git no pudo decirlo.
 * Plumbing y no `git show`: la salida no depende de la config del usuario
 * (formato, `diff.renames`, `core.quotePath`). `--root` es lo que hace que el
 * primer commit del repo liste sus archivos en vez de nada.
 */
export function readCommitChanges(rootUri: vscode.Uri, sha: string): CommitChange[] | undefined {
    try {
        const output = cp.execFileSync(
            "git",
            ["diff-tree", "-r", "-z", "--no-commit-id", "--name-status", "--root", sha],
            {cwd: rootUri.fsPath, encoding: "utf8"}
        );
        return parseNameStatus(output);
    } catch {
        return undefined;
    }
}

async function openCommitChanges(rootUri: vscode.Uri, sha: string): Promise<void> {
    // Se resuelve acá y no al activar: ver `ensureGitApi`.
    const gitApi = await ensureGitApi();
    if (!gitApi) {
        await reportMissingGitApi();
        return;
    }
    const changes = readCommitChanges(rootUri, sha);
    if (!changes) {
        void vscode.window.showErrorMessage(`Could not read the files of commit ${sha}.`);
        return;
    }
    if (changes.length === 0) {
        void vscode.window.showInformationMessage(`Commit ${sha} changes no files.`);
        return;
    }
    await vscode.commands.executeCommand(
        "vscode.changes",
        `Commit ${sha.slice(0, 7)}`,
        commitChangeResources(gitApi, rootUri, sha, changes)
    );
}
