import * as vscode from "vscode";
import {EntryRecord, ReviewMode, UncoveredRecord} from "../cli/porcelain";
import {entryPickLabel} from "../views/panelModel";

/**
 * `showQuickPick` no permite preseleccionar un ítem, y FR-006 pide que la
 * entrada actual esté señalada también acá. `activeItems` se asigna **después**
 * de `items`: asignar `items` reposiciona el cursor en el primero.
 */
function show<T extends vscode.QuickPickItem>(
    items: T[],
    active: T | undefined,
    title: string,
    placeholder: string
): Promise<T | undefined> {
    return new Promise((resolve) => {
        const quickPick = vscode.window.createQuickPick<T>();
        quickPick.title = title;
        quickPick.placeholder = placeholder;
        quickPick.matchOnDescription = true;
        quickPick.items = items;
        if (active) {
            quickPick.activeItems = [active];
        }
        let picked: T | undefined;
        quickPick.onDidAccept(() => {
            picked = quickPick.selectedItems[0];
            quickPick.hide();
        });
        quickPick.onDidHide(() => {
            quickPick.dispose();
            resolve(picked);
        });
        quickPick.show();
    });
}

interface EntryItem extends vscode.QuickPickItem {
    entry: EntryRecord;
}

/**
 * `gitReview.goToEntry` — la secuencia completa, en el orden de la CLI (FR-005a).
 * **Abre** la entrada elegida; no mueve el cursor: la CLI no tiene un verbo para
 * saltar a una posición arbitraria y sintetizarlo con `next`/`prev` sería
 * inventar comportamiento propio (FR-002, FR-016).
 */
export async function pickEntry(
    entries: EntryRecord[],
    mode: ReviewMode,
    position: number | undefined
): Promise<EntryRecord | undefined> {
    const items: EntryItem[] = entries.map((entry) => ({...entryPickLabel(entry, position), entry}));

    const active = items.find((item) => item.entry.position === position);
    const picked = await show(
        items,
        active,
        mode === "step" ? "Commits de la review" : "Entradas del walkthrough",
        "El orden es el de la secuencia de lectura; elegir no mueve el cursor"
    );
    return picked?.entry;
}

interface UncoveredItem extends vscode.QuickPickItem {
    file: UncoveredRecord;
}

/**
 * `gitReview.showUncovered` — los archivos del rango sin entrada en el
 * walkthrough, en una superficie **separada** de la secuencia (FR-008).
 */
export async function pickUncovered(files: UncoveredRecord[]): Promise<UncoveredRecord | undefined> {
    const items: UncoveredItem[] = files.map((file) => ({label: file.id.display, file}));
    const picked = await show(
        items,
        undefined,
        "Archivos sin cobertura",
        "Cambian en la review y el walkthrough no los anota"
    );
    return picked?.file;
}
