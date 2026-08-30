import * as vscode from "vscode";
import {EntryRecord, ReviewMode} from "../cli/porcelain";
import {entryPickLabel} from "../views/panelModel";

/**
 * `showQuickPick` no permite preseleccionar un ítem, y acá hace falta que la
 * entrada actual esté señalada también. `activeItems` se asigna **después** de
 * `items`: asignar `items` reposiciona el cursor en el primero.
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
 * `gitReview.goToEntry` — la secuencia completa, en el orden de la CLI.
 * **Abre** la entrada elegida; no mueve el cursor: la CLI no tiene un verbo para
 * saltar a una posición arbitraria y sintetizarlo con `next`/`prev` sería
 * inventar comportamiento propio.
 */
export async function pickEntry(
    entries: EntryRecord[],
    mode: ReviewMode,
    position: number | undefined,
    subjects?: Map<number, string>
): Promise<EntryRecord | undefined> {
    const items: EntryItem[] = entries.map((entry) => ({
        ...entryPickLabel(entry, position, subjects?.get(entry.position)),
        entry,
    }));

    // whole no tiene entrada actual (su `state.position` nunca está definido),
    // así que acá `active` sale siempre `undefined` — correcto, no un bug: sin
    // cursor no hay nada que preseleccionar.
    const active = items.find((item) => item.entry.position === position);
    const titles: Record<ReviewMode, string> = {
        step: "Review commits",
        walk: "Walkthrough entries",
        whole: "Files in this review",
    };
    const picked = await show(
        items,
        active,
        titles[mode],
        "In reading order; picking one does not move the cursor"
    );
    return picked?.entry;
}
