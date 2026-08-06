import * as vscode from "vscode";
import {npmCommandFor} from "../cli/installHint";

const INSTALL_DOCS_URL = "https://github.com/EzeVillo/git-review-workflow#readme";

/**
 * `gitReview.installCli` — otras vías de instalación (Homebrew, PowerShell,
 * one-liner). El camino recomendado (npm + Copy) vive en el empty state del
 * panel; este comando es el secundario "Other install options" y la paleta.
 */
export async function installOrUpdateCli(): Promise<void> {
    await vscode.env.openExternal(vscode.Uri.parse(INSTALL_DOCS_URL));
}

/**
 * Copia al clipboard el comando npm allowlisteado. El webview manda solo
 * `kind` (`install` | `update`); el host es quien resuelve el string — no se
 * confía texto arbitrario del panel.
 */
export async function copyCliInstallCommand(kind: unknown): Promise<void> {
    if (kind !== "install" && kind !== "update") {
        return;
    }
    await vscode.env.clipboard.writeText(npmCommandFor(kind));
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
