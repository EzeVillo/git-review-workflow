/**
 * `ReviewIntent` (data-model.md § ReviewIntent): la review que todavía no
 * existe, armada por el asistente entre que el revisor empieza a elegir y
 * confirma. No se persiste — si el asistente se cancela, no queda nada.
 *
 * `range`/`source` cubren full|delta y remote|local|offline: el asistente de
 * `start` los elige en pasos lineales (origen siempre; rango sólo con registro
 * delta). El tipo y `intentToArgs` son el contrato de esa UI con la CLI.
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
 * Contexto leído del reporte de la CLI (nunca adivinado) contra el que se
 * validan las combinaciones de un `ReviewIntent` (data-model.md § ReviewIntent,
 * FR-015). Separado de `intentToArgs`: traducir a argv no es validar.
 */
export interface IntentValidationContext {
    /**
     * Registro `delta` de `config --porcelain <rama>` para la rama elegida.
     * Ausente = esa rama nunca se revisó, o el reporte no se pidió por rama.
     */
    delta?: { name: string; tip: string };
}

export type IntentValidationResult =
    | { ok: true }
    | { ok: false; reason: string };

/**
 * Valida las reglas de un `ReviewIntent` que dependen del reporte de la CLI.
 * Hoy: `range = "delta"` sólo es legal cuando hay un `delta` presente para la
 * rama (FR-015). Todo lo demás —working tree sucio, review ya existente— lo
 * deja fallar la CLI (FR-032 / `002/FR-033`).
 */
export function validateIntent(
    intent: ReviewIntent,
    context: IntentValidationContext
): IntentValidationResult {
    if (intent.range === "delta" && context.delta === undefined) {
        return {
            ok: false,
            reason: 'range "delta" requires a prior review tip (delta record) for the branch',
        };
    }
    return {ok: true};
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
