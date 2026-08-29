import * as vscode from "vscode";

/**
 * Los controles que abren un diálogo antes de mutar, o sea el `confirms:` del
 * canónico (`contracts/client-product-surface.yaml`).
 *
 * Vive acá y no disperso en veinte comandos porque hasta ahora no vivía en
 * ningún lado: esta extensión tenía sus confirmaciones repartidas en dieciséis
 * `showWarningMessage` sueltos y `confirms:` no gobernaba nada — el checker del
 * contrato lo parseaba y lo descartaba sin usarlo. Sacar o agregar una
 * confirmación no ponía nada en rojo, y así el canónico llegó a declarar
 * `confirms: true` para un control que hacía rato no confirmaba.
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
 * LA ÚNICA PUERTA a un diálogo de confirmación de esta extensión, y por eso
 * toma el `id`: es lo que hace que la tabla de arriba **gobierne** en vez de
 * sólo describir. El id no cambia lo que se dibuja; cambia que un llamador no
 * pueda abrir un modal que el contrato no declara.
 *
 * Devuelve `true` sólo cuando se eligió el botón afirmativo: cerrar el diálogo
 * o apretar Cancel es «no hagas nada», nunca «seguí».
 *
 * El gate estático lo corre `scripts/check-client-product-surface.mjs`: todo id
 * declarado tiene un llamador acá, y no hay ningún otro modal en `src/`.
 */
export async function confirmMutation(
    id: ConfirmingId,
    title: string,
    detail: string,
    button: string
): Promise<boolean> {
    if (!requiresConfirmation(id)) {
        // Un id que el canónico no declara no puede abrir un modal. Se reporta
        // y se confirma igual: un cartel de más molesta, uno de menos borra
        // trabajo sin preguntar. El gate estático es el que lo evita antes.
        console.error(`confirmMutation called for ${id}, which the canonical marks confirms: false`);
    }
    const answer = await vscode.window.showWarningMessage(
        title,
        {modal: true, detail},
        button
    );
    return answer === button;
}
