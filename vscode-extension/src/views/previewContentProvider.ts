import * as vscode from "vscode";

/** Scheme reservado por si más adelante se prefiere documento virtual cacheado. */
export const PREVIEW_SCHEME = "git-review-preview";

export function previewUri(stat: boolean): vscode.Uri {
    return vscode.Uri.from({
        scheme: PREVIEW_SCHEME,
        path: stat ? "/preview-stat.txt" : "/preview.diff",
    });
}

/**
 * Placeholder: el comando de preview hoy abre un documento untitled con el
 * stdout (más simple y sin cachear estado). Se mantiene el scheme exportado
 * por si se unifica con whyContentProvider.
 */
export class PreviewContentProvider implements vscode.TextDocumentContentProvider {
    private content = "";

    setContent(text: string): void {
        this.content = text;
    }

    provideTextDocumentContent(): string {
        return this.content;
    }
}
