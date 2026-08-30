import * as vscode from "vscode";

/**
 * Los controles que abren un diálogo antes de mutar: el `confirms:` del
 * canónico (`contracts/client-product-surface.yaml`), que sin esta puerta
 * existía pero nadie lo consultaba (ver CLAUDE.md, "La copy de los paneles").
 *
 * `startReview` y `startFromDraft` NO están, a propósito y en los dos caminos
 * que llegan al start: el asistente ya pregunta cuatro cosas y `start` no
 * destruye nada — se niega solo con el árbol sucio, y una review empezada se
 * cancela con un botón del panel.
 *
 * Byte for byte the same set as CONFIRMING_IDS (Kotlin) and ConfirmingIds (C#).
 */
export const CONFIRMING_IDS = [
    "continueReview",
    "discardInventory",
    "discardDraft",
    "discardGuide",
    "discardFixes",
    "discardAllFixes",
    "cleanReview",
    "undoFinish",
    "compareReview",
    "walkthroughInit",
    "walkthroughBuild",
    "saveReview",
    "abortReview",
] as const;

export type ConfirmingId = (typeof CONFIRMING_IDS)[number];

/** Si `id` es uno de los que el canónico marca `confirms: true`. */
export function requiresConfirmation(id: string): boolean {
    return (CONFIRMING_IDS as readonly string[]).includes(id);
}

/**
 * LA ÚNICA PUERTA a un diálogo de confirmación de esta extensión. Toma el
 * `id` para que un llamador no pueda abrir un modal que el contrato no
 * declara; el id no cambia lo que se dibuja.
 *
 * Devuelve `true` sólo cuando se eligió el botón afirmativo: cerrar el diálogo
 * o apretar Cancel es «no hagas nada», nunca «seguí».
 *
 * Gate estático: `scripts/check-client-product-surface.mjs` confirma que todo
 * id declarado tiene un llamador acá y que no hay ningún otro modal en `src/`.
 */
export async function confirmMutation(
    id: ConfirmingId,
    title: string,
    detail: string,
    button: string
): Promise<boolean> {
    if (!requiresConfirmation(id)) {
        // No debería pasar (lo evita el gate estático), pero si pasa se confirma
        // igual: un cartel de más molesta, uno de menos borra trabajo sin preguntar.
        console.error(`confirmMutation called for ${id}, which the canonical marks confirms: false`);
    }
    const answer = await vscode.window.showWarningMessage(
        title,
        {modal: true, detail},
        button
    );
    return answer === button;
}
