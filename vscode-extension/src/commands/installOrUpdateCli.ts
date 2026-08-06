import * as vscode from "vscode";

const INSTALL_DOCS_URL = "https://github.com/EzeVillo/git-review-workflow#readme";

/** `gitReview.installCli` — abre la guía de instalación de la CLI (US5, `cli-missing`/`cli-outdated`). */
export async function installOrUpdateCli(): Promise<void> {
    await vscode.env.openExternal(vscode.Uri.parse(INSTALL_DOCS_URL));
}

/**
 * Botón "How to fix it" de `out-of-range` y `error`: muestra el diagnóstico
 * que la CLI ya produce con la acción concreta (`git reset --soft`,
 * `git review abort`, `git branch -D`, …), preservado tal cual, sin texto
 * propio (FR-023, FR-024).
 */
export async function showOutOfRangeHelp(stderr: string | undefined): Promise<void> {
    const message = stderr && stderr.trim().length > 0
        ? stderr.trim()
        : "Run 'git review status' in a terminal for the diagnosis and recovery command.";
    await vscode.window.showWarningMessage(message);
}
