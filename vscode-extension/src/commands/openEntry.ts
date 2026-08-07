import * as cp from "node:child_process";
import {promisify} from "node:util";
import * as vscode from "vscode";
import {CommitChange, parseNameStatus} from "../cli/nameStatus";
import {EntryRecord, ReviewMode} from "../cli/porcelain";
import {PathRef} from "../cli/unquote";
import {ensureGitApi, GitApi, gitApiUnavailableReason} from "../review/repository";

const execFile = promisify(cp.execFile);
/** Multi-diff inventory for a commit/range can be large; do not block the host forever. */
const GIT_DIFF_TIMEOUT_MS = 30000;
const GIT_DIFF_MAX_BUFFER = 20 * 1024 * 1024;

/**
 * Ejecutable de git: respeta `git.path` del host (misma setting que la
 * extensión de git de VS Code) y, si no hay, cae a `git` en el PATH.
 */
function gitExecutable(): string {
    const configured = vscode.workspace.getConfiguration("git").get<string>("path");
    if (typeof configured === "string" && configured.trim().length > 0) {
        return configured.trim();
    }
    return "git";
}

/** Opciones de `execFile` para las lecturas de diff multi-archivo. */
function gitExecFileOptions(cwd: string): cp.ExecFileOptionsWithStringEncoding {
    return {
        cwd,
        encoding: "utf8",
        timeout: GIT_DIFF_TIMEOUT_MS,
        maxBuffer: GIT_DIFF_MAX_BUFFER,
        // En Windows evita el flash de consola al spawnear git.
        windowsHide: true,
    };
}

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
        // Archivo eliminado en el rango: no hay working tree. Abrimos el blob
        // pre-borrado en HEAD (en review, lower bound) vía la API de git — un
        // documento `git:` real, no `file:`. `git.openChange` en paths ausentes
        // a menudo no materializa tab en el host de test de Windows.
        const gitApi = await ensureGitApi();
        if (gitApi) {
            const left = gitApi.toGitUri(fileUri, "HEAD");
            const document = await vscode.workspace.openTextDocument(left);
            await vscode.window.showTextDocument(document);
            return;
        }
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
 * Sin API de git no hay diff que mostrar, pero *por qué* no la hay cambia lo que
 * el revisor tiene que hacer: confiar en la carpeta, habilitar la extensión, o
 * simplemente esperar. Un solo mensaje para las tres cosas era un callejón sin
 * salida. `subject` nombra lo que no se pudo abrir —los cambios de un commit o
 * los de la review entera—: el motivo es el mismo, pero el aviso tiene que decir
 * de qué acción está hablando.
 */
async function reportMissingGitApi(subject: string): Promise<void> {
    switch (gitApiUnavailableReason()) {
        case "untrusted": {
            const manage = "Manage Trust";
            const choice = await vscode.window.showWarningMessage(
                `Showing ${subject} needs the git extension, and VS Code disables it while this folder is in restricted mode. Trust the folder to enable it.`,
                manage
            );
            if (choice === manage) {
                await vscode.commands.executeCommand("workbench.trust.manage");
            }
            return;
        }
        case "missing":
            void vscode.window.showWarningMessage(
                `The built-in git extension is disabled: enable it to see ${subject}.`
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
export async function readCommitChanges(
    rootUri: vscode.Uri,
    sha: string
): Promise<CommitChange[] | undefined> {
    try {
        const {stdout} = await execFile(
            gitExecutable(),
            ["diff-tree", "-r", "-z", "--no-commit-id", "--name-status", "--root", sha],
            gitExecFileOptions(rootUri.fsPath)
        );
        return parseNameStatus(stdout);
    } catch {
        return undefined;
    }
}

/**
 * Los archivos del rango de una review `whole`, o `undefined` si git no pudo
 * decirlo. `HEAD` de una rama de review está clavado en el merge-base y el PR
 * vive como cambios staged encima, así que el rango entero es exactamente
 * `diff HEAD` — más las ediciones del revisor, que es lo mismo que ya muestra
 * `git.openChange` archivo por archivo.
 *
 * `git diff` y no `diff-index` como en el commit: la porcelana refresca el
 * índice antes de comparar, y sin eso un índice desincronizado (típico en
 * Windows, o después de tocar los archivos desde afuera) listaría archivos que
 * no cambiaron. `--no-renames` fija el comportamiento en vez de heredar el
 * `diff.renames` del usuario: un rename partido en `D` + `A` son dos entradas
 * correctas del multi-diff, mientras que depender de la config haría que la
 * misma review se viera distinta en dos máquinas.
 */
export async function readRangeChanges(rootUri: vscode.Uri): Promise<CommitChange[] | undefined> {
    try {
        const {stdout} = await execFile(
            gitExecutable(),
            ["diff", "--name-status", "-z", "--no-renames", "HEAD"],
            gitExecFileOptions(rootUri.fsPath)
        );
        return parseNameStatus(stdout);
    } catch {
        return undefined;
    }
}

/**
 * Los tres Uri por archivo del multi-diff del rango. El lado derecho es el
 * archivo del **working tree**, no un blob `git:` como en el commit: en una
 * review el working tree *es* el PR aplicado, así que el diff queda editable —
 * que es el flujo entero de `git review`. El izquierdo sale de `HEAD`, o sea del
 * merge-base.
 */
export function rangeChangeResources(
    gitApi: GitApi,
    rootUri: vscode.Uri,
    changes: CommitChange[]
): [vscode.Uri, vscode.Uri | undefined, vscode.Uri | undefined][] {
    return changes.map((change) => [
        vscode.Uri.joinPath(rootUri, change.path),
        change.before === undefined
            ? undefined
            : gitApi.toGitUri(vscode.Uri.joinPath(rootUri, change.before), "HEAD"),
        change.after === undefined ? undefined : vscode.Uri.joinPath(rootUri, change.after),
    ]);
}

/**
 * Comando `gitReview.openAllChanges` — el equivalente en `whole` del diff que
 * `step` abre por commit: todos los archivos del rango juntos, en un solo
 * multi-diff. `label` nombra la pestaña; es el origen de la review (el PR), lo
 * mismo que el panel muestra en su barra.
 */
export async function openRangeChanges(rootUri: vscode.Uri, label: string): Promise<void> {
    const gitApi = await ensureGitApi();
    if (!gitApi) {
        await reportMissingGitApi("the changes of a review");
        return;
    }
    const changes = await readRangeChanges(rootUri);
    if (!changes) {
        void vscode.window.showErrorMessage("Could not read the files of this review's range.");
        return;
    }
    if (changes.length === 0) {
        void vscode.window.showInformationMessage("This review's range does not touch any files.");
        return;
    }
    await vscode.commands.executeCommand(
        "vscode.changes",
        `Review ${label}`,
        rangeChangeResources(gitApi, rootUri, changes)
    );
}

async function openCommitChanges(rootUri: vscode.Uri, sha: string): Promise<void> {
    // Se resuelve acá y no al activar: ver `ensureGitApi`.
    const gitApi = await ensureGitApi();
    if (!gitApi) {
        await reportMissingGitApi("a commit's changes");
        return;
    }
    const changes = await readCommitChanges(rootUri, sha);
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
