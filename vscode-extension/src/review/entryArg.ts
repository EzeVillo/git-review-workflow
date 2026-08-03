import {EntryRecord} from "../cli/porcelain";

function isEntryRecord(value: unknown): value is EntryRecord {
    return typeof value === "object" && value !== null && (value as EntryRecord).id !== undefined;
}

/**
 * Normaliza el argumento con el que llega un comando de entrada. Hay dos
 * formas y las dos son reales:
 *
 * - un `EntryRecord` explícito, cuando el llamador ya sabe de qué entrada
 *   habla;
 * - **sin argumento**, que es como los dispara el panel y la paleta de
 *   comandos: ahí la entrada implícita es la actual (`state.position`).
 *
 * Cualquier otra cosa da `undefined` en vez de una entrada arbitraria: un
 * comando que no sabe sobre qué entrada opera no debe operar sobre la primera.
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
    return undefined;
}
