import {ReviewSource} from "./reviewIntent";

/**
 * El default de origen que el asistente preselecciona. Es un ajuste del host
 * (`gitReview.defaultSource`), no estado del producto — la CLI no sabe que existe.
 *
 * La precedencia workspace-sobre-user es la de VS Code: quien llama pasa los
 * niveles ya leídos de `inspect("defaultSource")` (o el valor efectivo de
 * `get()` modelado como un solo nivel). Esta función sólo elige entre ellos y
 * valida el enum; no lee configuración por su cuenta.
 */
export interface SourcePreferenceLevels {
    /** Valor a nivel workspace (gana sobre user). */
    workspaceValue?: string;
    /** Valor a nivel user/global. */
    globalValue?: string;
}

const VALID: ReadonlySet<string> = new Set(["remote", "local", "offline"]);

function asSource(value: string | undefined): ReviewSource | undefined {
    if (value !== undefined && VALID.has(value)) {
        return value as ReviewSource;
    }
    return undefined;
}

/**
 * Resuelve el origen efectivo: workspace gana sobre user; sin ninguno,
 * `"remote"` (default del manifiesto y de data-model.md).
 */
export function resolveDefaultSource(levels: SourcePreferenceLevels): ReviewSource {
    return asSource(levels.workspaceValue) ?? asSource(levels.globalValue) ?? "remote";
}
