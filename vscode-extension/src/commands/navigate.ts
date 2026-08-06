import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {openChange} from "./openEntry";

export type NavigateDirection = "next" | "prev";

/** Primera línea con contenido, que es donde la CLI deja el mensaje operativo. */
function firstLine(text: string): string {
    return text.split("\n").map((line) => line.trim()).find((line) => line.length > 0) ?? "";
}

/**
 * `gitReview.next` / `gitReview.prev`: invoca el verbo de la CLI a través del
 * `MutationLock`, refresca con `status --porcelain` inmediatamente después
 * (nunca parsea la salida humana del verbo, FR-015), y muestra los cambios de
 * la entrada resultante — lo mismo que el botón "Diff", no el archivo pelado:
 * avanzar es pasar a leer *el diff* de esa entrada, y el archivo entero sigue a
 * un clic de distancia desde el panel. Los límites de la secuencia se
 * propagan tal cual desde la CLI, sin comportamiento propio (FR-016).
 */
export async function navigate(
    direction: NavigateDirection,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    // FR-027: con un cierre trabado la review sigue legible pero moverse por
    // la secuencia no corresponde — el panel retira next/prev
    // (`navigationLocked`) y el comando se niega acá también, para que un
    // atajo o `executeCommand` no mute el porcelain a espaldas del banner.
    if (stateManager.state.situation !== "review") {
        return;
    }

    await lock.run(async () => {
        const options = getInvokeOptions();
        const before = stateManager.state.state?.position;
        const result = await invokeGitReview(direction, [], options);
        const state = await stateManager.refresh();

        if (result.exitCode !== 0) {
            if (result.stderr.trim().length > 0) {
                void vscode.window.showInformationMessage(result.stderr.trim());
            }
            return;
        }

        if (state.situation !== "review" || !state.state) {
            return;
        }

        // En un extremo de la secuencia la CLI no falla: informa por stdout y
        // deja el cursor donde estaba (bin/git-review-verbs/next). Sin esto el
        // clic sería mudo, así que se muestra ese mismo mensaje — el de la CLI,
        // no uno propio (FR-016) — y no se reabre lo que ya está abierto. La
        // señal es que el cursor no se movió, no el texto del verbo (FR-015).
        if (state.state.position === before) {
            const message = firstLine(result.stdout);
            if (message.length > 0) {
                void vscode.window.showInformationMessage(message);
            }
            return;
        }

        const current = state.entries.find((e) => e.position === state.state?.position);
        if (current) {
            await openChange(vscode.Uri.file(options.cwd), state.state.mode, current);
        }
    });
}
