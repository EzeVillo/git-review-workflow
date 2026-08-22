/**
 * Los dos controles de la fila del walkthrough del autor. Son controles del
 * **cuerpo** del panel, no acciones del producto: no están en
 * `contributes.commands` ni en la paleta, y sin la fila que los dibuja no
 * tienen sujeto — exactamente como los del bloque de borradores y los de las
 * guías.
 *
 * Lo que la fila agrega al panel es que el autor se entere. Un walkthrough se
 * escribe cuando el PR está terminado y después el PR sigue moviéndose; el
 * verbo que lo diría es `build`, y correrlo hay que acordárselo justo en el
 * momento en que nadie está pensando en el walkthrough. La fila lo dice sola.
 *
 * Ninguno de los dos escribe el archivo ni lo interpreta: uno lo abre en la
 * ruta que reportó la CLI —**se abre, nunca se arma**— y el otro deja en el
 * portapapeles un puntero a esa misma ruta. Actualizarlo es de la CLI, por el
 * botón *Walkthrough: Update* de la sección, que invoca `walkthrough init`.
 */

import * as vscode from "vscode";
import {WalkthroughRecord} from "../cli/configPorcelain";
import {ReviewStateManager} from "../review/state";
import {walkthroughAgentPrompt} from "../review/userCopy";

/**
 * El registro, resuelto contra el estado del HOST. El webview manda un índice
 * fijo (la fila es una sola), y como con las otras filas no se le cree: lo que
 * termina en un comando sale de acá.
 */
function rowOf(stateManager: ReviewStateManager): WalkthroughRecord | undefined {
    return stateManager.state.walkthrough;
}

/**
 * *Open*: muestra el walkthrough en el editor, en la ruta que reportó la CLI.
 *
 * Abrirlo es mostrarlo, no leerlo: la extensión no interpreta un byte de su
 * contenido, igual que con el borrador y con las guías.
 */
export async function openWalkthrough(stateManager: ReviewStateManager): Promise<void> {
    const walkthrough = rowOf(stateManager);
    if (walkthrough === undefined || walkthrough.state === "absent") {
        return;
    }
    try {
        const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(walkthrough.path));
        await vscode.window.showTextDocument(doc, {preview: false});
    } catch {
        void vscode.window.showErrorMessage(`Could not open ${walkthrough.path}.`);
    }
}

/**
 * *Copy for agent*: deja en el portapapeles un puntero al walkthrough.
 *
 * No abre ninguna conexión, no invoca ningún modelo y no se integra con ningún
 * asistente: copiar es copiar. La consigna vive dentro del archivo, que es
 * donde se mantiene sola.
 */
export async function copyWalkthroughPrompt(stateManager: ReviewStateManager): Promise<void> {
    const walkthrough = rowOf(stateManager);
    if (walkthrough === undefined || walkthrough.state === "absent") {
        return;
    }
    await vscode.env.clipboard.writeText(walkthroughAgentPrompt(walkthrough.path));
    void vscode.window.showInformationMessage(
        "Copied an instruction pointing at this PR's reading order."
    );
}
