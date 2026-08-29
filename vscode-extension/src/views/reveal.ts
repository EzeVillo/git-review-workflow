/**
 * Las mutaciones que traen el panel a la vista, o sea el `reveals:` del canónico
 * (`contracts/client-product-surface.yaml`).
 *
 * «Lo que el panel muestra no se notifica» tiene un supuesto que nadie
 * garantizaba: que el panel esté a la vista. El borrador nace en el asistente de
 * inicio, que corre sobre el editor, y con la vista cerrada la fila nueva se
 * dibuja donde nadie la ve — y como esa mutación tampoco notifica, no queda
 * ningún acuse en ningún lado.
 *
 * La lista es corta a propósito: sólo las mutaciones cuya respuesta es un bloque
 * que ANTES NO ESTABA. Si el panel salta en cada mutación, deja de significar
 * que pasó algo.
 *
 * Byte for byte the same set as REVEALING_IDS (Kotlin) and RevealingIds (C#).
 */
export const REVEALING_IDS = [
    "startReview",
    "startFromDraft",
    "continueReview",
    "finishReview",
] as const;

export type RevealingId = (typeof REVEALING_IDS)[number];

/** Si `id` es una de las mutaciones que el canónico marca en `reveals:`. */
export function revealsPanel(id: string): boolean {
    return (REVEALING_IDS as readonly string[]).includes(id);
}

/**
 * Trae el panel a la vista, sin robar el foco. El host lo provee; acá vive la
 * decisión de si corresponde.
 */
export type PanelRevealer = () => void;

/**
 * LA ÚNICA PUERTA al reveal, y por eso toma el `id`: es lo que hace que
 * `reveals:` del canónico **gobierne** en vez de sólo describir — la misma
 * lección que dejó `confirms:`, que se declaraba en tres lugares y no gobernaba
 * en ninguno.
 *
 * Se llama DESPUÉS del refresco y sólo en verde: revelar un panel que no cambió
 * es el salto que enseña a ignorar los saltos, y sobre un error el mensaje ya
 * está en pantalla.
 *
 * El gate estático lo corre `scripts/check-client-product-surface.mjs`.
 */
export function revealPanel(id: RevealingId, reveal: PanelRevealer): void {
    if (!revealsPanel(id)) {
        // Un id que el canónico no declara no revela: acá la degradación segura
        // es la contraria a la de confirmMutation — de más, el panel salta
        // cuando no corresponde y se vuelve ruido.
        console.error(`revealPanel called for ${id}, which the canonical does not list under reveals:`);
        return;
    }
    reveal();
}
