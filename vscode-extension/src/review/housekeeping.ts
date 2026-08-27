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
    | "clean-fixes-only-all"
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
        case "clean-fixes-only-all":
            // No branch: --fixes-only alone only ever touches review-fixes/*
            // (clean's own scoping, see bin/git-review-verbs/clean), so this
            // never reaches a live review/* session the way a bare clean-all does.
            return ["--fixes-only"];
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
                title: `Delete the leftovers from reviewing ${src}?`,
                detail: `This removes the review branch and any edits you extracted from it. Anything you already committed elsewhere stays. It cannot be undone.`,
                button: "Delete",
            };
        case "clean-keep-fixes": {
            // onto → edits en la rama del PR; sin onto → review-fixes/<src>.
            // El clean no toca el working tree: solo tira el undo review/*.
            //
            // Lo que se CONSERVA va primero, y no es un adorno: este diálogo
            // sale del botón que cierra el ciclo, y la única duda que frena a
            // alguien ahí es si el clean se lleva sus ediciones. La respuesta
            // es que no, y decirla antes de nombrar lo que sí se pierde es la
            // diferencia entre leer el cartel y apretar a ciegas.
            const destination = action.onto ? src : `review-fixes/${src}`;
            return {
                title: `Done with the review of ${src}?`,
                detail: `Your edits stay on ${destination} — commit and push them from Source Control. What goes away is being able to undo this finish.`,
                button: "Done",
            };
        }
        case "clean-fixes-only": {
            // La sesión se nombra sólo cuando existe: prometer que se deja algo
            // que no está es ruido, y el argv es el mismo en los dos casos.
            const session = action.session
                ? " You can still undo the finish afterwards."
                : "";
            return {
                title: `Delete the edits you extracted from ${src}?`,
                detail: `${fixesCostSentence(action.fixesState)}${session} It cannot be undone.`,
                button: "Delete",
            };
        }
        case "clean-fixes-only-all":
            return {
                title: "Delete every branch of extracted edits?",
                detail: "They hold edits you made while reviewing and never committed anywhere else. Nothing you are reviewing right now is touched. It cannot be undone.",
                button: "Delete all",
            };
        case "clean-all":
            return {
                title: "Delete all review leftovers?",
                detail: "This removes every review branch and every branch of extracted edits that you are not currently on. Paused reviews and your last review points are left alone. It cannot be undone.",
                button: "Delete all",
            };
        case "forget-saved-one":
            return {
                title: `Delete the paused review of ${src}?`,
                detail: `This throws away the edits you had saved with it. It cannot be undone.`,
                button: "Delete",
            };
        case "forget-saved-all":
            return {
                title: "Delete every paused review?",
                detail: "This throws away the edits saved with each of them. It cannot be undone.",
                button: "Delete all",
            };
        // Los tres de --delta dicen la CONSECUENCIA y no la operación, y la
        // dicen con la etiqueta que el asistente usa para el rango ("only what
        // is new"): quien vaya a apretar esto lo eligió alguna vez ahí, y es el
        // único lugar donde ese dato se nota. "Removes the last-reviewed tip"
        // describía un ref que ninguna superficie del producto nombra.
        case "forget-delta-one":
            return {
                title: `Forget where you got to on ${src}?`,
                detail: "Next time you review this branch, \"only what is new\" will have no starting point, so you will be offered the full range instead.",
                button: "Forget",
            };
        case "forget-delta-all":
            return {
                title: "Forget where you got to on every branch?",
                detail: "Next time you review any of them, \"only what is new\" will have no starting point, so you will be offered the full range instead.",
                button: "Forget all",
            };
        case "forget-delta-stale":
            return {
                title: "Forget the branches that are gone?",
                detail: "This clears where you got to on branches that no longer exist. It checks the remote first, so it may take a moment.",
                button: "Forget",
            };
        default: {
            const _exhaustive: never = action.kind;
            throw new Error(`unknown housekeeping kind: ${_exhaustive}`);
        }
    }
}
