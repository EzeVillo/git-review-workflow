/**
 * `Situation` — el resultado de una invocación (data-model.md § Situation).
 * Módulo sin dependencia de `vscode`: es lógica pura, testeable sin host.
 */
export type Situation =
    "review"
    | "no-review"
    | "out-of-range"
    | "error"
    | "cli-missing"
    | "cli-outdated"
    | "finish-conflict"
    | "finish-pending";

/**
 * Mapea el exit code de `status --porcelain` a `Situation`. Un exit code
 * desconocido (`>3`, o cualquier otro valor incluido `1`) se trata siempre
 * como `error`, nunca como `review`.
 */
export function situationForExitCode(exitCode: number | null): Situation {
    switch (exitCode) {
        case 0:
            return "review";
        case 2:
            return "no-review";
        case 3:
            return "out-of-range";
        default:
            return "error";
    }
}

/**
 * `situationForExitCode` ampliado con el registro `finish`
 * (contracts/finish-state.md, data-model.md § `Situation`): `finish-conflict`
 * gana siempre sobre `review`, y `finish-pending` sobre `no-review` — nunca al
 * revés, y nunca sobre ninguna otra situación (`out-of-range`/`error`/
 * `cli-*` no cambian, aunque el inventario trajera un cierre pendiente de OTRA
 * review). `hasFinishConflict` viene de parsear el registro `finish` de
 * `status --porcelain` (sólo posible con exit `0`); `hasFinishPending` viene
 * de si el inventario de `list --porcelain` trae al menos una fila `finish …
 * pending` (sólo relevante con exit `2`, donde el panel ya invoca `list` para
 * el estado vacío).
 */
export function situationFor(
    exitCode: number | null,
    hasFinishConflict: boolean,
    hasFinishPending: boolean
): Situation {
    const base = situationForExitCode(exitCode);
    if (base === "review" && hasFinishConflict) {
        return "finish-conflict";
    }
    if (base === "no-review" && hasFinishPending) {
        return "finish-pending";
    }
    return base;
}
