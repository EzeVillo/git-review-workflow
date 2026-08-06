/**
 * Acciones de housekeeping y su mapeo a la lista cerrada de args
 * (specs/006-superficie-panel-completa/contracts/cli-invocation.md).
 * Sin vscode: puro y testeable.
 */

import {sourceOf} from "../cli/porcelain";
import type {ReviewState} from "./state";

export type HousekeepingKind =
    | "clean-one"
    | "clean-keep-fixes"
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
 * Source del cierre `pending` a limpiar desde el panel
 * (`git review clean --keep-fixes <src>`). No depende de HEAD: el pending es
 * del repo (`list --porcelain`), igual que `finish --abort` resuelve el undo
 * sin inventar la rama actual.
 *
 * Ausente fuera de `finish-pending`, o si el inventario no trae fila pending
 * (no debería ocurrir cuando la situación es esa).
 */
export function pendingFinishSource(state: ReviewState): string | undefined {
    if (state.situation !== "finish-pending") {
        return undefined;
    }
    const pending = state.branches.find((branch) => branch.finish?.state === "pending");
    if (!pending) {
        return undefined;
    }
    return sourceOf(pending);
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
        case "clean-keep-fixes":
            return {
                title: `Drop the finish undo for ${src}?`,
                detail: `Runs git review clean --keep-fixes ${src}: deletes review/${src} and the finish undo point so the pending finish goes away. Leaves review-fixes/${src} (your staged edits) and delta markers alone.`,
                button: "Clean",
            };
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
