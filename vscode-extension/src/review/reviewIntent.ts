/**
 * `ReviewIntent` (data-model.md § ReviewIntent): la review que todavía no
 * existe, armada por el asistente entre que el revisor empieza a elegir y
 * confirma. No se persiste — si el asistente se cancela, no queda nada.
 *
 * `range`/`source` llevan ya los cuatro valores de la tabla, aunque esta fase
 * sólo alcanza `full`/`remote`: la UI de "Más opciones" (Fase 8, US6) sólo
 * agrega superficie para llegar a `delta`/`local`/`offline`, no un contrato
 * nuevo — así que el tipo y `intentToArgs` lo soportan desde ahora.
 */
export type ReviewLayout = "auto" | "step" | "no-walk";
export type ReviewRange = "full" | "delta";
export type ReviewSource = "remote" | "local" | "offline";

export interface ReviewIntent {
    /** Ausente = la rama actual (el default de data-model.md); ver `intentToArgs`. */
    branch?: string;
    layout: ReviewLayout;
    range: ReviewRange;
    source: ReviewSource;
}

/**
 * Traduce un `ReviewIntent` a los argumentos exactos que
 * contracts/cli-invocation.md § `start` permite — nada más: nunca `--base`,
 * `--from` ni el `<base>` posicional (la base sale de `git review config`, no
 * de esta invocación, FR-010a).
 *
 * El `--` precede siempre al nombre de rama, incluso cuando `branch` no
 * "parece" una opción: pasarlo siempre —y no sólo cuando hace falta— es lo que
 * evita una rama de código condicional que se ejercita una vez cada mil (U1).
 * Sin él, una rama llamada `-foo` la leería el parseo de opciones de `start` en
 * vez de tratarla como el nombre que el revisor eligió.
 *
 * `currentBranch` es el fallback de `branch` ausente, no un segundo lugar
 * donde mirar "por si": el asistente siempre pasa un `branch` explícito
 * (cli-invocation.md § start, columna "Cuándo se pasa": "Siempre, explícito"),
 * así que esta rama sólo se ejercita desde un intent armado a mano (los tests).
 */
export function intentToArgs(intent: ReviewIntent, currentBranch: string): string[] {
    const args: string[] = [];

    if (intent.layout === "step") {
        args.push("--step");
    } else if (intent.layout === "no-walk") {
        args.push("--no-walk");
    }

    if (intent.range === "delta") {
        args.push("--delta");
    }

    if (intent.source === "local") {
        args.push("--local");
    } else if (intent.source === "offline") {
        args.push("--offline");
    }

    args.push("--", intent.branch ?? currentBranch);
    return args;
}
