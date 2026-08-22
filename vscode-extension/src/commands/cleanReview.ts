import * as vscode from "vscode";
import {InvokeOptions} from "../cli/invoke";
import {BranchRecord, sourceOf} from "../cli/porcelain";
import {MutationLock} from "../review/mutationLock";
import {pendingFinishInfo, sourceFromReviewName} from "../review/housekeeping";
import {ReviewStateManager} from "../review/state";
import {captureToken} from "../review/staleGuard";
import {runHousekeeping} from "./runHousekeeping";

type CleanPick = vscode.QuickPickItem & { action: "one" | "all" };

/**
 * `gitReview.cleanReview`: limpia leftovers de una fuente o de todas
 * (`git review clean [<branch>]`). El marcador `--delta` no se toca.
 *
 * `target` opcional:
 * - `number`: fila del inventario (webview clean por índice).
 * - `string`: source explícito (`feature/x`).
 * - omitido en `finish-pending`: limpia el source del cierre con undo vivo
 *   (botón Clean del panel), sin picker y **sin mirar HEAD** — el pending es
 *   del repo (`pendingFinishInfo`).
 * - omitido en cualquier otro caso: QuickPick de palette (one / all).
 */
export async function cleanReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions,
    target?: unknown
): Promise<void> {
    if (typeof target === "number") {
        const review = stateManager.state.branches[target];
        if (!review) {
            return;
        }
        const source = sourceOf(review);
        await runHousekeeping(
            {kind: "clean-one", source},
            lock,
            stateManager,
            getInvokeOptions,
            captureToken(stateManager.state)
        );
        return;
    }

    if (typeof target === "string" && target.trim() !== "") {
        await runHousekeeping(
            {kind: "clean-one", source: target.trim()},
            lock,
            stateManager,
            getInvokeOptions,
            captureToken(stateManager.state)
        );
        return;
    }

    // Panel finish-pending: el finish ya entregó las edits. Clean con
    // --keep-fixes tira solo review/* + undo (cierra el pending). Las edits
    // staged quedan donde el finish las dejó (review-fixes/* o la rama del PR
    // si fue --onto-source). HEAD no importa: source/onto salen del inventario.
    const pending = pendingFinishInfo(stateManager.state);
    if (pending !== undefined) {
        await runHousekeeping(
            {kind: "clean-keep-fixes", source: pending.source, onto: pending.onto},
            lock,
            stateManager,
            getInvokeOptions,
            captureToken(stateManager.state)
        );
        return;
    }

    const items: CleanPick[] = [
        {label: "Clean leftovers for one branch…", action: "one"},
        {label: "Clean all leftover review branches", action: "all"},
    ];
    const pick = await vscode.window.showQuickPick(items, {
        title: "Clean review leftovers",
        placeHolder: "What to delete",
    });
    if (!pick) {
        return;
    }
    if (pick.action === "all") {
        await runHousekeeping({kind: "clean-all"}, lock, stateManager, getInvokeOptions);
        return;
    }

    const source = await pickSource(stateManager.state.branches);
    if (!source) {
        return;
    }
    await runHousekeeping({kind: "clean-one", source}, lock, stateManager, getInvokeOptions);
}

/**
 * La rama a limpiar sale del inventario y solo de ahí. `clean` borra ramas: un
 * nombre tipeado a mano es la única forma de pedirle que borre algo que el
 * revisor no vio en ninguna lista, y un typo ahí no falla, apunta a otro lado.
 * El QuickPick filtra incrementalmente, así que escribir sigue siendo la forma
 * de llegar al ítem — pero lo que vuelve es siempre uno de los que reportó la
 * CLI.
 */
async function pickSource(branches: BranchRecord[]): Promise<string | undefined> {
    const names = [
        ...new Set(branches.map((r) => sourceFromReviewName(r.name))),
    ];
    if (names.length === 0) {
        void vscode.window.showErrorMessage("No reviews to clean were found.");
        return undefined;
    }
    const chosen = await vscode.window.showQuickPick(
        names.map((name) => ({label: name})),
        {
            title: "Branch to clean",
            placeHolder: "Source branch name (without review/ prefix)",
        }
    );
    return chosen?.label;
}
