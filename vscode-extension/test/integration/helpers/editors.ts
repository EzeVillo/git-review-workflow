import * as vscode from "vscode";

export async function closeAllEditors(): Promise<void> {
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
}

/**
 * Los comandos que abren superficies del host (`git.openChange`,
 * `vscode.changes`, la preview de markdown del why) lo hacen de forma
 * asíncrona; sondea hasta que haya un tab activo. Es el único sondeo de tabs de
 * la suite: el margen es generoso a propósito y una copia aparte se quedaría
 * atrás al ajustarlo. El extension host se pone lento
 * bajo carga (el runner lo reporta como "unresponsive") y con 5 s el sondeo se
 * rendía antes de que el tab existiera, con el comando en curso.
 */
export async function waitForActiveTab(timeoutMs = 20000): Promise<vscode.Tab | undefined> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const tab = vscode.window.tabGroups.activeTabGroup.activeTab;
        if (tab) {
            return tab;
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return vscode.window.tabGroups.activeTabGroup.activeTab;
}
