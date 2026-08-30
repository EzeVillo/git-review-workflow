import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {EntryRecord, ReviewMode} from "../cli/porcelain";
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
 * (nunca parsea la salida humana del verbo), y muestra los cambios de la
 * entrada resultante — lo mismo que el botón "Diff", no el archivo pelado:
 * avanzar es pasar a leer *el diff* de esa entrada, y el archivo entero sigue a
 * un clic de distancia desde el panel. Los límites de la secuencia se
 * propagan tal cual desde la CLI, sin comportamiento propio.
 *
 * El lock **sólo** cubre CLI + refresh. Abrir el editor (`openChange`) es
 * solo lectura y puede tardar (multi-diff de un commit grande): dejar el
 * `MutationLock` / `gitReview.busy` tomados durante eso descartaría finish/
 * abort/save confirmados con un toast de "already in progress".
 */
export async function navigate(
    direction: NavigateDirection,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    // Con un cierre trabado la review sigue legible pero moverse por la
    // secuencia no corresponde — el panel retira next/prev (`navigationLocked`)
    // y el comando se niega acá también, para que un atajo o `executeCommand`
    // no mute el porcelain a espaldas del banner.
    if (stateManager.state.situation !== "review") {
        return;
    }

    // Capturado dentro del lock; openChange corre después de soltarlo.
    let openAfter: {cwd: string; mode: ReviewMode; entry: EntryRecord} | undefined;

    await lock.run(async () => {
        const options = getInvokeOptions();
        const before = stateManager.state.state?.position;
        const result = await invokeGitReview(direction, [], options);
        const state = await stateManager.refresh();

        if (result.exitCode !== 0) {
            // stderr de la CLI tal cual; si viene vacío (CLI matada / rota),
            // un mensaje genérico evita el fallo silencioso.
            const text = result.stderr.trim();
            void vscode.window.showInformationMessage(
                text.length > 0 ? text : `git review ${direction} failed.`
            );
            return;
        }

        if (state.situation !== "review" || !state.state) {
            return;
        }

        // En un extremo de la secuencia la CLI no falla: informa por stdout y
        // deja el cursor donde estaba (bin/git-review-verbs/next). Sin esto el
        // clic sería mudo, así que se muestra ese mismo mensaje — el de la CLI,
        // no uno propio — y no se reabre lo que ya está abierto. La señal es que
        // el cursor no se movió, no el texto del verbo.
        if (state.state.position === before) {
            const message = firstLine(result.stdout);
            if (message.length > 0) {
                void vscode.window.showInformationMessage(message);
            }
            return;
        }

        const current = state.entries.find((e) => e.position === state.state?.position);
        if (current) {
            openAfter = {cwd: options.cwd, mode: state.state.mode, entry: current};
        }
    });

    if (openAfter) {
        await openChange(vscode.Uri.file(openAfter.cwd), openAfter.mode, openAfter.entry);
    }
}
