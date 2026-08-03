import * as vscode from "vscode";
import {panelHtml} from "./panelHtml";
import {PanelModel} from "./panelModel";

/**
 * Conjunto **cerrado** de mensajes que el webview puede mandar
 * (contracts/extension-surface.md § Protocolo). El webview no ejecuta comandos:
 * postea uno de estos y el host decide. Cualquier otro valor se ignora.
 */
export const PANEL_MESSAGES = [
    "openEntry",
    "openChange",
    "showWhy",
    "next",
    "prev",
    "refresh",
    "showUncovered",
    "installCli",
    "outOfRangeHelp",
    "continueReview",
] as const;

export type PanelMessage = (typeof PANEL_MESSAGES)[number];

/**
 * El handshake, deliberadamente **fuera** de `PANEL_MESSAGES`: no es una acción
 * del revisor y no rutea a ningún comando, sólo avisa que el script del webview
 * ya está escuchando.
 */
const READY = "ready";

function isPanelMessage(value: unknown): value is PanelMessage {
    return typeof value === "string" && (PANEL_MESSAGES as readonly string[]).includes(value);
}

function nonce(): string {
    let text = "";
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    for (let i = 0; i < 32; i++) {
        text += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return text;
}

/**
 * El panel (research.md Decisión 4): un webview cuyo contenido principal es la
 * **entrada actual** con su *why* como cuerpo, no la lista de la secuencia —
 * ésa vive en los `QuickPick` de `pickEntry.ts`.
 *
 * El host postea el `PanelModel` entero y el webview lo dibuja de cero: no hay
 * actualización parcial dirigida desde acá, por la misma razón por la que no hay
 * estado incremental del lado de la extensión (FR-019).
 */
export class WalkthroughViewProvider implements vscode.WebviewViewProvider {
    public static readonly viewId = "gitReview.walkthrough";

    private view: vscode.WebviewView | undefined;
    private model: PanelModel | undefined;

    /**
     * `index` es el único dato que un mensaje puede traer además del `type`
     * (`continueReview`, contracts/extension-surface.md § Protocolo). Viaja
     * como `unknown` a propósito: acá no se valida nada, lo resuelve el host
     * contra su propio estado.
     */
    constructor(private readonly onMessage: (message: PanelMessage, index?: unknown) => void) {
    }

    /**
     * Se llama cada vez que la vista pasa a ser visible, no una sola vez: si el
     * revisor la oculta, el host destruye el contexto del webview y al volver lo
     * reconstruye de cero. Por eso nada de lo de acá puede asumir que corre una
     * única vez, y por eso el modelo se repostea contra el webview nuevo.
     */
    resolveWebviewView(view: vscode.WebviewView): void {
        this.view = view;
        view.webview.options = {enableScripts: true};
        // El listener va ANTES del html, no después: es el html el que arranca
        // el script que postea `ready`, y un mensaje que llegue antes de que el
        // host esté escuchando se pierde igual que se perdía el modelo.
        const listener = view.webview.onDidReceiveMessage((raw: unknown) => {
            const type = (raw as { type?: unknown } | undefined)?.type;
            if (type === READY) {
                this.post();
                return;
            }
            if (isPanelMessage(type)) {
                this.onMessage(type, (raw as { index?: unknown } | undefined)?.index);
            }
        });
        view.onDidDispose(() => {
            listener.dispose();
            if (this.view === view) {
                this.view = undefined;
            }
        });
        view.webview.html = this.html();
    }

    update(model: PanelModel): void {
        this.model = model;
        this.post();
    }

    /**
     * Un `post` que salga mientras el webview todavía carga se pierde, pero no
     * queda nada colgado: el `ready` de ese webview vuelve a pedir el modelo, y
     * el modelo es siempre el completo (no hay actualización parcial que
     * reconstruir).
     */
    private post(): void {
        if (this.view && this.model) {
            void this.view.webview.postMessage({type: "model", model: this.model});
        }
    }

    private html(): string {
        return panelHtml(nonce());
    }
}
