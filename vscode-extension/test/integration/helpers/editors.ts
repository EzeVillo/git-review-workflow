import * as vscode from "vscode";

export async function closeAllEditors(): Promise<void> {
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
}

/** Snapshot de todos los tabs abiertos (todos los grupos). */
export function snapshotTabs(): readonly vscode.Tab[] {
    return vscode.window.tabGroups.all.flatMap((group) => group.tabs);
}

/**
 * Los comandos que abren superficies del host (`vscode.diff`,
 * `vscode.changes`, la preview de markdown del why) lo hacen de forma
 * asíncrona; sondea hasta que haya un tab activo. Es el único sondeo de tabs de
 * la suite: el margen es generoso a propósito y una copia aparte se quedaría
 * atrás al ajustarlo. El extension host se pone lento
 * bajo carga (el runner lo reporta como "unresponsive") y con 5 s el sondeo se
 * rendía antes de que el tab existiera, con el comando en curso.
 *
 * Preferí `waitForNewTab` cuando ya puede haber un tab activo (p. ej. un diff
 * de un paso anterior): este helper devuelve *cualquier* tab activo y flaquea
 * al afirmar path/input del tab equivocado.
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

/**
 * Espera un tab que no estuviera en `previousTabs` (p. ej. `snapshotTabs()`
 * antes del comando). Opcionalmente filtra con `predicate` (TabInput /
 * fsPath). Más estable que `waitForActiveTab` cuando el host ya tenía un
 * editor abierto.
 */
export async function waitForNewTab(
    previousTabs: readonly vscode.Tab[],
    predicate?: (tab: vscode.Tab) => boolean,
    timeoutMs = 20000
): Promise<vscode.Tab | undefined> {
    const previous = new Set(previousTabs);
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        for (const tab of snapshotTabs()) {
            if (previous.has(tab)) {
                continue;
            }
            if (predicate === undefined || predicate(tab)) {
                return tab;
            }
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
    }
    for (const tab of snapshotTabs()) {
        if (!previous.has(tab) && (predicate === undefined || predicate(tab))) {
            return tab;
        }
    }
    return undefined;
}
