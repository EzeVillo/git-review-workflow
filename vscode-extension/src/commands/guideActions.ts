/**
 * Los tres controles de una fila del bloque de guías de autoría. Son controles
 * del **cuerpo** del panel, no acciones del producto: no están en
 * `contributes.commands` ni en la paleta, y sin la fila que los dibuja no
 * tienen sujeto — exactamente como los del bloque de borradores.
 *
 * Una guía es prosa sobre el CONTENIDO del walkthrough (qué entradas merecen
 * `> key`, cómo se escribe un porqué, qué va en el heads-up). La extensión no
 * lee un byte de ella: la abre, pide a la CLI que la cree o que la borre, y
 * nada más. Y la ruta viene del registro `guide` de `config --porcelain`: **se
 * abre, nunca se arma**.
 */

import * as vscode from "vscode";
import {GuideRecord} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {createGuideArgs, deleteGuideArgs} from "../review/reviewIntent";
import {ReviewStateManager} from "../review/state";
import {guideAt} from "../views/panelModel";
import {STALE} from "../review/userCopy";
import {confirmMutation} from "../review/confirm";

/** El stderr de la CLI, aplanado a una línea (mismo criterio que el resto). */
function flatten(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

/**
 * La fila `index`, resuelta contra el estado del HOST. El índice es lo único
 * que un mensaje del webview lleva, y nunca se le cree: lo que termina en la
 * CLI sale de acá.
 */
function rowAt(stateManager: ReviewStateManager, index: unknown): GuideRecord | undefined {
    return guideAt(stateManager.state.guides ?? [], index);
}

/**
 * *Open*: muestra la guía en el editor, en la ruta que reportó la CLI.
 *
 * Abrirla es mostrarla, no leerla — igual que con el borrador y con
 * `.review/walkthrough.md` tras un `walkthrough init`.
 */
export async function openGuide(index: unknown, stateManager: ReviewStateManager): Promise<void> {
    const guide = rowAt(stateManager, index);
    if (guide === undefined || guide.state === "absent") {
        return;
    }
    try {
        const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(guide.path));
        await vscode.window.showTextDocument(doc, {preview: false});
    } catch {
        void vscode.window.showErrorMessage(`Could not open ${guide.path}.`);
    }
}

/**
 * *Create*: pide a la CLI el archivo vacío y abre lo que haya creado.
 *
 * La escritura la hace la CLI y no la extensión, y eso no es ceremonia: si cada
 * cliente creara el archivo por su cuenta serían tres implementaciones de
 * "crear un archivo vacío en el gitdir" y tres chances de errarle a la ruta —
 * la misma razón por la que *Open* abre la ruta reportada en vez de derivarla.
 *
 * Refresca dentro del lock pase lo que pase, como `invokeDraft`: la guía es un
 * archivo del gitdir (o un untracked de `.review/`) y **el watcher no la mira**
 * — el de la propia vive en la raíz del gitdir, que cambia en cada operación de
 * git, así que vigilarla sería una tormenta de refrescos por el archivo que
 * menos cambia del panel. Sin este refresco la fila se quedaría diciendo
 * `absent` sobre un archivo que acaba de nacer.
 */
export async function createGuide(
    index: unknown,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const guide = rowAt(stateManager, index);
    if (guide === undefined || guide.state !== "absent") {
        return;
    }

    let created: string | undefined;
    await lock.run(async () => {
        // Re-resolver dentro del lock: el reporte pudo cambiar, y crear sobre
        // una guía que ya existe la CLI lo niega -- mejor no pedírselo.
        const fresh = rowAt(stateManager, index);
        if (fresh === undefined || fresh.kind !== guide.kind || fresh.state !== "absent") {
            return;
        }
        const result = await invokeGitReview("walkthrough", createGuideArgs(fresh.kind), {
            ...getInvokeOptions(),
            network: false,
        });
        await stateManager.refresh();
        if (result.errorCode || result.exitCode !== 0) {
            const text = flatten(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not create the guide."
            );
            return;
        }
        created = fresh.path;
    });

    if (created === undefined) {
        return;
    }
    // Abrirla es el paso siguiente y no un extra: el archivo se crea VACÍO a
    // propósito -- un esqueleto con placeholders lo leería el próximo agente
    // como si las instrucciones fueran las convenciones -- así que sin abrirlo
    // el botón deja al revisor mirando una fila que dice "empty".
    try {
        const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(created));
        await vscode.window.showTextDocument(doc, {preview: false});
    } catch {
        void vscode.window.showInformationMessage(`Created ${created}.`);
    }
}

/**
 * *Discard*: borra **tu** guía, con confirmación modal.
 *
 * Es prosa escrita a mano, así que se pregunta nombrando el verbo real que se
 * va a correr, igual que `discardDraft` y `discardInventory`. Sólo la propia:
 * la compartida es un archivo trackeado, así que borrarla es `git rm` más un
 * commit — una decisión sobre qué entra al PR, que no es de este botón, y la
 * CLI dice lo mismo del otro lado negando `--delete --team`.
 */
export async function discardGuide(
    index: unknown,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const guide = rowAt(stateManager, index);
    if (guide === undefined || guide.kind !== "own" || guide.state === "absent") {
        return;
    }
    const confirmed = await confirmMutation(
        "discardGuide",
        "Discard the authoring guide you wrote?",
        `This deletes ${guide.path}. It cannot be undone.`,
        "Discard"
    );
    if (!confirmed) {
        return;
    }

    await lock.run(async () => {
        const fresh = rowAt(stateManager, index);
        if (fresh === undefined || fresh.kind !== "own" || fresh.state === "absent") {
            void vscode.window.showInformationMessage(
                STALE
            );
            return;
        }
        const result = await invokeGitReview("walkthrough", deleteGuideArgs(), {
            ...getInvokeOptions(),
            network: false,
        });
        await stateManager.refresh();
        if (result.errorCode || result.exitCode !== 0) {
            const text = flatten(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not delete the guide."
            );
        }
    });
}
