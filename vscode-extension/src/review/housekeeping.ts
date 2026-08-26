/**
 * Acciones de housekeeping y su mapeo a la lista cerrada de args
 * (specs/006-superficie-panel-completa/contracts/cli-invocation.md).
 * Sin vscode: puro y testeable.
 */

import {sourceOf} from "../cli/porcelain";
import type {FixesState} from "../cli/porcelain";
import type {ReviewState} from "./state";

export type HousekeepingKind =
    | "clean-one"
    | "clean-keep-fixes"
    | "clean-fixes-only"
    | "clean-all"
    | "forget-saved-one"
    | "forget-saved-all"
    | "forget-delta-one"
    | "forget-delta-all"
    | "forget-delta-stale";

export interface HousekeepingAction {
    kind: HousekeepingKind;
    /** Source name (`feature/x`), nunca `review-saved/x`. Requerido en `*-one` y `clean-keep-fixes`. */
    source?: string;
    /**
     * Solo `clean-keep-fixes`: si el finish fue con `--onto-source`. Define el
     * destino que nombra el confirm (rama del PR vs `review-fixes/<src>`).
     * Ausente se trata como no-onto (destino por defecto).
     */
    onto?: boolean;
    /**
     * Sólo `clean-fixes-only`: lo que la CLI reportó sobre esa rama, para que
     * la confirmación diga cuánto trabajo cuesta. No se deriva acá — quien
     * puede preguntarle a git es la CLI. Ausente se trata como `unknown`.
     */
    fixesState?: FixesState;
    /**
     * Sólo `clean-fixes-only`: si `review/<src>` sigue existiendo. Cambia la
     * copy y nada más: el argv lleva `--fixes-only` siempre, porque un dato que
     * se relee en cada refresco no puede decidir qué ramas borra un comando.
     */
    session?: boolean;
}

/**
 * Lo que la confirmación de `clean-fixes-only` dice sobre el costo. Una oración
 * por estado y ninguna se pliega en otra: "no committed" no es "seguro porque
 * ya está integrada", y "unknown" no es "no integrada".
 */
function fixesCostSentence(state: FixesState | undefined): string {
    switch (state) {
        case "empty":
            return "Nothing was ever committed on it, so no work of yours is lost.";
        case "merged":
            return "Its commits are already in the base branch.";
        case "unmerged":
            return "It has commits the base branch does not have — deleting it loses them.";
        default:
            return "There is no base branch configured, so git cannot tell whether its commits are integrated.";
    }
}

/** Prefijos de rama de review → source (mismo criterio que `sourceOf` en porcelain). */
export function sourceFromReviewName(name: string): string {
    for (const prefix of ["review-saved/", "review/", "review-fixes/"]) {
        if (name.startsWith(prefix)) {
            return name.slice(prefix.length);
        }
    }
    return name;
}

/**
 * Cierre `pending` a limpiar/deshacer desde el panel. No depende de HEAD: el
 * pending es del repo (`list --porcelain`), igual que `finish --abort`.
 *
 * Ausente fuera de `finish-pending`, o si el inventario no trae fila pending
 * (no debería ocurrir cuando la situación es esa).
 */
export function pendingFinishInfo(
    state: ReviewState
): {source: string; onto: boolean} | undefined {
    if (state.situation !== "finish-pending") {
        return undefined;
    }
    const pending = state.branches.find((branch) => branch.finish?.state === "pending");
    if (!pending?.finish) {
        return undefined;
    }
    return {source: sourceOf(pending), onto: pending.finish.onto};
}

/** Source del pending de finish, o `undefined`. Ver `pendingFinishInfo`. */
export function pendingFinishSource(state: ReviewState): string | undefined {
    return pendingFinishInfo(state)?.source;
}

export function verbForHousekeeping(action: HousekeepingAction): "clean" | "forget" {
    return action.kind.startsWith("clean") ? "clean" : "forget";
}

/**
 * Args del verbo (sin el verbo). Lanza si falta `source` en un kind que lo
 * exige (`*-one`, `clean-keep-fixes`).
 */
export function argsForHousekeeping(action: HousekeepingAction): string[] {
    switch (action.kind) {
        case "clean-one":
            if (!action.source) {
                throw new Error("clean-one requires source");
            }
            return [action.source];
        case "clean-keep-fixes":
            if (!action.source) {
                throw new Error("clean-keep-fixes requires source");
            }
            // Flag before the branch name — same shape as the CLI usage line.
            return ["--keep-fixes", action.source];
        case "clean-fixes-only":
            if (!action.source) {
                throw new Error("clean-fixes-only requires source");
            }
            // Flag before the branch name, same shape as --keep-fixes.
            return ["--fixes-only", action.source];
        case "clean-all":
            return [];
        case "forget-saved-one":
            if (!action.source) {
                throw new Error("forget-saved-one requires source");
            }
            return ["--saved", action.source];
        case "forget-saved-all":
            return ["--saved", "--all"];
        case "forget-delta-one":
            if (!action.source) {
                throw new Error("forget-delta-one requires source");
            }
            return ["--delta", action.source];
        case "forget-delta-all":
            return ["--delta", "--all"];
        case "forget-delta-stale":
            return ["--delta", "--stale"];
        default: {
            const _exhaustive: never = action.kind;
            throw new Error(`unknown housekeeping kind: ${_exhaustive}`);
        }
    }
}

/** `forget --delta --stale` toca la red (fetch). */
export function housekeepingNeedsNetwork(action: HousekeepingAction): boolean {
    return action.kind === "forget-delta-stale";
}

export interface ConfirmCopy {
    title: string;
    detail: string;
    button: string;
}

export function confirmCopyFor(action: HousekeepingAction): ConfirmCopy {
    const src = action.source ?? "";
    switch (action.kind) {
        case "clean-one":
            return {
                title: `Clean leftover review branches for ${src}?`,
                detail: `Deletes review/${src} and review-fixes/${src} (and banked edit refs) if they exist and are not checked out. Does not touch delta markers.`,
                button: "Clean",
            };
        case "clean-keep-fixes": {
            // onto → edits en la rama del PR; sin onto → review-fixes/<src>.
            // El clean no toca el working tree: solo tira el undo review/*.
            const destination = action.onto ? src : `review-fixes/${src}`;
            return {
                title: `Drop the finish undo for ${src}?`,
                detail: `Runs git review clean --keep-fixes ${src}: deletes review/${src} and the finish undo point so the pending finish goes away. Your staged edits stay on ${destination}; delta markers are left alone. Remember to commit and push them from Source Control.`,
                button: "Clean",
            };
        }
        case "clean-fixes-only": {
            // La sesión se nombra sólo cuando existe: prometer que se deja algo
            // que no está es ruido, y el argv es el mismo en los dos casos.
            const session = action.session
                ? ` The review session on review/${src} is left standing, so you can still undo the finish.`
                : "";
            return {
                title: `Discard the edits extracted onto review-fixes/${src}?`,
                detail: `git review clean --fixes-only ${src}

${fixesCostSentence(action.fixesState)}${session} It cannot be undone.`,
                button: "Discard",
            };
        }
        case "clean-all":
            return {
                title: "Clean all leftover review branches?",
                detail: "Deletes every review/* and review-fixes/* branch that is not currently checked out, plus orphaned edit/undo refs. Does not touch delta markers or saved reviews.",
                button: "Clean All",
            };
        case "forget-saved-one":
            return {
                title: `Discard the saved review of ${src}?`,
                detail: `Deletes review-saved/${src}, its banked edits and metadata, and rolls back the delta marker it left.`,
                button: "Discard",
            };
        case "forget-saved-all":
            return {
                title: "Discard every saved review?",
                detail: "Deletes all review-saved/* branches, their banked edits and metadata, and rolls back their delta markers.",
                button: "Discard All Saved",
            };
        case "forget-delta-one":
            return {
                title: `Forget the delta marker for ${src}?`,
                detail: "Removes the last-reviewed tip used by git review start --delta for this branch (remote and local markers).",
                button: "Forget Marker",
            };
        case "forget-delta-all":
            return {
                title: "Forget every delta marker?",
                detail: "Removes all last-reviewed tips used by git review start --delta.",
                button: "Forget All Markers",
            };
        case "forget-delta-stale":
            return {
                title: "Forget stale delta markers?",
                detail: "Fetches from the remote (when needed) and removes markers whose branch no longer exists.",
                button: "Forget Stale",
            };
        default: {
            const _exhaustive: never = action.kind;
            throw new Error(`unknown housekeeping kind: ${_exhaustive}`);
        }
    }
}
