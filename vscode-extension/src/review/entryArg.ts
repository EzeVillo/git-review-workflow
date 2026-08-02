import {EntryRecord} from "../cli/porcelain";

function isEntryRecord(value: unknown): value is EntryRecord {
    return typeof value === "object" && value !== null && (value as EntryRecord).id !== undefined;
}

/**
 * Normaliza el argumento con el que llega un comando de entrada. Hay tres
 * formas y las tres son reales:
 *
 * - `TreeItem.command` pasa el `EntryRecord` explícitamente (`arguments`);
 * - los menús `view/item/context` (los íconos inline) ignoran ese `arguments`
 *   y pasan el **nodo** del árbol — `{kind: "entry", entry}` —, que no tiene
 *   `id` propio;
 * - desde la paleta de comandos no llega ningún argumento: ahí la entrada
 *   implícita es la actual (`state.position`).
 *
 * Sin vscode como dependencia, para que sea testeable como unidad.
 */
export function resolveEntryArg(
    arg: unknown,
    entries: EntryRecord[],
    position: number | undefined
): EntryRecord | undefined {
    if (arg === undefined || arg === null) {
        return entries.find((entry) => entry.position === position);
    }
    if (isEntryRecord(arg)) {
        return arg;
    }
    if (typeof arg === "object" && isEntryRecord((arg as { entry?: unknown }).entry)) {
        return (arg as { entry: EntryRecord }).entry;
    }
    return undefined;
}
