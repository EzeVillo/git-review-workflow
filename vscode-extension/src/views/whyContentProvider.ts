import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";

export const WHY_SCHEME = "git-review-why";

export interface Why {
    /** Payload completo de stdout, sin tocar. */
    text: string;
    /** false si text está vacío con exit 0. */
    present: boolean;
}

/** Uri del documento virtual del *why* de una entrada; el path es sólo para mostrar. */
export function whyUri(display: string, raw: string): vscode.Uri {
    return vscode.Uri.from({
        scheme: WHY_SCHEME,
        path: `/${display}.md`,
        query: `raw=${encodeURIComponent(raw)}`,
    });
}

function rawFromUri(uri: vscode.Uri): string {
    const params = new URLSearchParams(uri.query);
    return params.get("raw") ?? "";
}

/**
 * `status --why <raw>`, bajo demanda — nunca al construir el árbol
 * (contracts/cli-invocation.md). `present = false` (exit 0, cuerpo vacío) y un
 * fallo (exit != 0, `undefined`) son estados distintos (FR-018).
 */
export async function fetchWhy(raw: string, options: InvokeOptions): Promise<Why | undefined> {
    const result = await invokeGitReview("status", ["--why", raw], options);
    if (result.exitCode !== 0) {
        return undefined;
    }
    return {text: result.stdout, present: result.stdout.length > 0};
}

/**
 * Expone el *why* como documento Markdown de sólo lectura (research.md
 * Decisión 6). Sin caché: el costo que evita cachear es una invocación extra
 * en hover, y el walkthrough del tip no cambia durante una review.
 */
export class WhyContentProvider implements vscode.TextDocumentContentProvider {
    private readonly changeEmitter = new vscode.EventEmitter<vscode.Uri>();
    readonly onDidChange = this.changeEmitter.event;

    constructor(private readonly getOptions: () => InvokeOptions) {
    }

    async provideTextDocumentContent(uri: vscode.Uri): Promise<string> {
        const raw = rawFromUri(uri);
        const why = await fetchWhy(raw, this.getOptions());
        if (why === undefined) {
            return "No se pudo obtener el porqué de esta entrada.";
        }
        if (!why.present) {
            return "*Esta entrada no tiene explicación.*";
        }
        return why.text;
    }
}
