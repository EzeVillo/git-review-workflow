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
    "goToEntry",
    "showUncovered",
    "installCli",
    "outOfRangeHelp",
] as const;

export type PanelMessage = (typeof PANEL_MESSAGES)[number];

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

    constructor(private readonly onMessage: (message: PanelMessage) => void) {
    }

    resolveWebviewView(view: vscode.WebviewView): void {
        this.view = view;
        view.webview.options = {enableScripts: true};
        view.webview.html = this.html();
        view.webview.onDidReceiveMessage((raw: unknown) => {
            const type = (raw as { type?: unknown } | undefined)?.type;
            if (isPanelMessage(type)) {
                this.onMessage(type);
            }
        });
        this.post();
    }

    update(model: PanelModel): void {
        this.model = model;
        this.post();
    }

    private post(): void {
        if (this.view && this.model) {
            void this.view.webview.postMessage({type: "model", model: this.model});
        }
    }

    private html(): string {
        return panelHtml(nonce());
    }
}
