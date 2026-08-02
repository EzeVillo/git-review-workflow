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
    | "cli-outdated";

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
