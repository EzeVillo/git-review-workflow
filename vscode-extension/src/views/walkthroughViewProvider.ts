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
    "openAllChanges",
    "showWhy",
    "next",
    "prev",
    "refresh",
    "installCli",
    // Copia el comando npm del empty state cli-missing/cli-outdated. Lleva
    // `kind` ("install" | "update"); el host resuelve el string allowlisteado.
    "copyCliInstall",
    "outOfRangeHelp",
    "continueReview",
    "startReview",
    "setBase",
    "setRemote",
    // Finish / Save / Cancel no pasan por el webview: son iconos de view/title
    // (y la paleta). Undo/Continue de un finish trabado sí, porque viven en el
    // banner del panel, no en el chrome.
    "undoFinish",
    "resumeFinish",
    // Housekeeping (006): fila del inventario → índice como continueReview.
    "discardInventory",
    // finish-pending: clean del source del pending (sin índice; el host
    // resuelve desde state). También palette con picker.
    "cleanReview",
    // Superficie del empty state (006): solo se dibujan en no-review.
    "compareReview",
    "walkthroughInit",
    "walkthroughBuild",
    // Support (links externos): el webview manda un id; el host resuelve la
    // URL contra un allowlist y abre con openExternal. No es un comando de
    // la paleta ni de la CLI.
    "openSupport",
] as const;

export type PanelMessage = (typeof PANEL_MESSAGES)[number];

/**
 * Ids de link de Support que el webview puede pedir. El host es el único que
 * conoce las URLs: un id desconocido se ignora (nada del webview se abre a
 * ciegas). Sumar LinkedIn / donate / rate = una entrada acá + en el mapa del
 * host + un botón en `renderSupport`.
 */
export const SUPPORT_LINK_IDS = ["star"] as const;
export type SupportLinkId = (typeof SUPPORT_LINK_IDS)[number];

export const SUPPORT_URLS: Record<SupportLinkId, string> = {
    // GitHub no tiene deep-link público de "star": abre el repo, donde está el
    // botón. Si algún día hay marketplace rating u otro destino, se desdobla.
    star: "https://github.com/EzeVillo/git-review-workflow",
};

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
    private readonly visibilityEmitter = new vscode.EventEmitter<boolean>();

    /**
     * Visibilidad del webview: el sondeo de CLI ausente/vieja solo corre
     * mientras el panel está a la vista (no con la vista resuelta pero oculta
     * por `retainContextWhenHidden`).
     */
    readonly onDidChangeVisibility = this.visibilityEmitter.event;

    /**
     * `index` / `id` / `kind` son los únicos datos que un mensaje puede traer
     * además del `type` (contracts/extension-surface.md § Protocolo). Viajan
     * como `unknown` a propósito: acá no se valida nada, lo resuelve el host
     * contra su propio estado / allowlist.
     *
     * El segundo argumento es `index` para inventario/whole, `id` de Support
     * para `openSupport`, y `kind` para `copyCliInstall` — el host discrimina
     * por `type`.
     */
    constructor(private readonly onMessage: (message: PanelMessage, extra?: unknown) => void) {
    }

    get isVisible(): boolean {
        return this.view?.visible === true;
    }

    /**
     * Se llama cada vez que la vista pasa a ser visible, no una sola vez: si el
     * revisor la oculta, el host destruye el contexto del webview y al volver lo
     * reconstruye de cero. Por eso nada de lo de acá puede asumir que corre una
     * única vez, y por eso el modelo se repostea contra el webview nuevo.
     *
     * Con `retainContextWhenHidden` el host puede mantener el webview vivo al
     * esconderlo: en ese caso no se re-resuelve, y la visibilidad se sigue por
     * `onDidChangeVisibility`.
     */
    resolveWebviewView(view: vscode.WebviewView): void {
        this.view = view;
        view.webview.options = {enableScripts: true};
        // El listener va ANTES del html, no después: es el html el que arranca
        // el script que postea `ready`, y un mensaje que llegue antes de que el
        // host esté escuchando se pierde igual que se perdía el modelo.
        const listener = view.webview.onDidReceiveMessage((raw: unknown) => {
            const msg = raw as { type?: unknown; index?: unknown; id?: unknown } | undefined;
            const type = msg?.type;
            if (type === READY) {
                this.post();
                return;
            }
            if (isPanelMessage(type)) {
                // openSupport → `id`; copyCliInstall → `kind`; el resto con
                // payload → `index` (fila/entrada). El host valida cada uno.
                let extra: unknown = msg?.index;
                if (type === "openSupport") {
                    extra = msg?.id;
                } else if (type === "copyCliInstall") {
                    extra = (msg as { kind?: unknown }).kind;
                }
                this.onMessage(type, extra);
            }
        });
        const visibility = view.onDidChangeVisibility(() => {
            this.visibilityEmitter.fire(view.visible);
        });
        view.onDidDispose(() => {
            listener.dispose();
            visibility.dispose();
            if (this.view === view) {
                this.view = undefined;
            }
            this.visibilityEmitter.fire(false);
        });
        view.webview.html = this.html();
        // resolveWebviewView corre al mostrarse: el primer tick de visibilidad
        // no siempre dispara onDidChangeVisibility, así que se anuncia acá.
        this.visibilityEmitter.fire(view.visible);
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
