/**
 * `ReviewIntent` (data-model.md § ReviewIntent): la review que todavía no
 * existe, armada por el asistente entre que el revisor empieza a elegir y
 * confirma. No se persiste — si el asistente se cancela, no queda nada.
 *
 * 008: `layout` es walk|keys|step|whole (sin `auto`). Cada valor mapea 1:1 a
 * argv de start; la viabilidad la reporta config --porcelain (offer).
 */

import {DeltaRecord} from "../cli/configPorcelain";

export type ReviewLayout = "walk" | "keys" | "step" | "whole";
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
     * Registro `delta` ya filtrado al origin del source elegido
     * (`deltaForSource`). Ausente = esa rama nunca se revisó en ese eje, o el
     * reporte no se pidió por rama.
     */
    delta?: DeltaRecord;
}

export type IntentValidationResult =
    | { ok: true }
    | { ok: false; reason: string };

/**
 * Valida las reglas de un `ReviewIntent` que dependen del reporte de la CLI.
 * Hoy: `range = "delta"` sólo es legal cuando hay un `delta` del origin que
 * corresponde al source (FR-015). Todo lo demás —working tree sucio, review
 * ya existente— lo deja fallar la CLI (FR-032 / `002/FR-033`).
 */
export function validateIntent(
    intent: ReviewIntent,
    context: IntentValidationContext
): IntentValidationResult {
    if (intent.range === "delta" && context.delta === undefined) {
        return {
            ok: false,
            reason: 'range "delta" requires a prior review tip (delta record) for the chosen source',
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
 * Layout (008):
 * - walk → sin flag (la CLI detecta walkthrough)
 * - keys → `--keys`
 * - step → `--step`
 * - whole → `--no-walk` (idempotente sin sidecar; 1:1 con la opción de UI)
 */
export function intentToArgs(intent: ReviewIntent, currentBranch: string): string[] {
    const args: string[] = [];

    if (intent.layout === "step") {
        args.push("--step");
    } else if (intent.layout === "whole") {
        args.push("--no-walk");
    } else if (intent.layout === "keys") {
        args.push("--keys");
    }
    // walk: no layout flags

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

/**
 * Argumentos de `git review walkthrough draft` (011,
 * contracts/cli-invocation-draft.md). El verbo es `walkthrough`; `draft` es el
 * primer argumento.
 *
 * Origen y rango son **los mismos** que el asistente ya resolvió: el borrador
 * tiene que listar los archivos de la review que se va a iniciar, no los de
 * otro rango. Nunca `--force`: pisar un borrador empezado se pide a mano.
 */
export function draftArgs(
    branch: string,
    source: ReviewSource,
    range: ReviewRange,
    build: boolean
): string[] {
    const args = ["draft"];

    if (build) {
        args.push("--build");
    }

    if (source === "local") {
        args.push("--local");
    } else if (source === "offline") {
        args.push("--offline");
    }

    if (range === "delta") {
        args.push("--delta");
    }

    args.push("--", branch);
    return args;
}
