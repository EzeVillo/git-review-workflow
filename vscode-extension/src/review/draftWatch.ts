/**
 * Qué hay que vigilar para ver crecer un borrador, y cada cuánto se contesta.
 *
 * El borrador del revisor vive en el gitdir (`<gitdir>/review-walkthrough/
 * <src>.md`), o sea fuera del working tree y fuera de los refs: el agente que
 * lo completa no mueve `HEAD`, no toca el índice y no escribe una sola línea
 * de `config`, así que **ninguna** de las señales de refresco del panel lo ve.
 * Sin esto el progreso `3/9` se queda congelado hasta que alguien aprieta
 * Refresh — justo en el momento en que el revisor está mirando el panel para
 * ver si el agente terminó.
 *
 * Los directorios salen de las rutas que la CLI ya reportó (`draft` de
 * `config --porcelain` y de `status --porcelain`), nunca de rearmar el layout
 * del gitdir: es la misma regla que hace que *Open draft* abra la ruta que dio
 * la CLI en vez de derivarla. Consecuencia deliberada: un borrador de una rama
 * cuya carpeta todavía no aparece en ningún reporte no tiene quién lo mire —
 * ahí no hay progreso que seguir, sólo un archivo que aún no existe para el
 * panel.
 *
 * Módulo sin `vscode` a propósito, como `soleTarget`: la decisión de qué mirar
 * es pura y se testea sin editor. El watcher en sí vive en `repository.ts`,
 * con las otras dos señales de refresco.
 */

/**
 * Lo que hace falta de un `ReviewState` — estructural, para no arrastrar el
 * módulo que importa `vscode`.
 */
export interface DraftPathSource {
    /** Registros `draft` de `config --porcelain` (uno por rama con borrador). */
    drafts?: readonly {path: string}[];
    /** Ruta del borrador en vigor de la review activa (`status --porcelain`). */
    draftPath?: string;
}

/**
 * Debounce del watcher. Escribir el borrador es un `mv` (create) que suele
 * venir con su change detrás, y un agente puede reescribir el archivo entero
 * varias veces seguidas; sin esto cada pasada costaría un refresco completo.
 * Corto igual: lo que se está midiendo es "el panel reacciona solo", no "el
 * panel reacciona en el próximo minuto".
 */
export const DRAFT_WATCH_DEBOUNCE_MS = 250;

/** El directorio que contiene `file`, o `undefined` si no se puede nombrar. */
function containerOf(file: string): string | undefined {
    // Los dos separadores: la CLI resuelve con `git rev-parse --absolute-git-dir`,
    // que en Windows contesta con `/` (`C:/repo/.git`), pero nada obliga a que
    // el host que la corrió lo haga.
    const cut = Math.max(file.lastIndexOf("/"), file.lastIndexOf("\\"));
    return cut > 0 ? file.slice(0, cut) : undefined;
}

/**
 * Los directorios a vigilar, únicos y en orden estable — el orden es lo que
 * permite comparar dos resultados como texto y no rehacer los watchers en cada
 * refresco.
 */
export function draftWatchDirs(state: DraftPathSource): string[] {
    const dirs = new Set<string>();
    const add = (file: unknown): void => {
        if (typeof file !== "string" || file.trim() === "") {
            return;
        }
        const dir = containerOf(file);
        if (dir !== undefined) {
            dirs.add(dir);
        }
    };
    add(state.draftPath);
    for (const draft of state.drafts ?? []) {
        add(draft?.path);
    }
    return [...dirs].sort();
}
