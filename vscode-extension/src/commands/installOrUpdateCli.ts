import * as vscode from "vscode";

const INSTALL_DOCS_URL = "https://github.com/EzeVillo/git-review-workflow#readme";

/** `gitReview.installCli` — abre la guía de instalación de la CLI (US5, `cli-missing`/`cli-outdated`). */
export async function installOrUpdateCli(): Promise<void> {
    await vscode.env.openExternal(vscode.Uri.parse(INSTALL_DOCS_URL));
}

/**
 * Botón "How to fix it" del estado `out-of-range`: muestra el diagnóstico
 * que la CLI ya produce con la acción concreta (`git reset --soft`),
 * preservado tal cual, sin texto propio (FR-023, FR-024).
 */
export async function showOutOfRangeHelp(stderr: string | undefined): Promise<void> {
    const message = stderr && stderr.trim().length > 0 ? stderr.trim() : "The cursor is out of range; run 'git review status' in a terminal for the diagnosis.";
    await vscode.window.showWarningMessage(message);
}
