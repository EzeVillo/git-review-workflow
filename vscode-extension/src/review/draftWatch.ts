/**
 * Qué hay que vigilar para ver crecer un borrador, y cada cuánto se contesta.
 *
 * El borrador del revisor vive en el gitdir (`<gitdir>/review-walkthrough/
 * <src>.md`), fuera del working tree y de los refs: el agente que lo completa
 * no mueve `HEAD`, no toca el índice y no escribe `config`, así que
 * **ninguna** señal de refresco del panel lo ve. Sin esto el progreso `3/9`
 * se queda congelado hasta que alguien aprieta Refresh — justo cuando el
 * revisor mira el panel para ver si el agente terminó.
 *
 * Los directorios salen de las rutas que la CLI ya reportó (`draft` de
 * `config --porcelain` y de `status --porcelain`), nunca de rearmar el layout
 * del gitdir. Consecuencia deliberada: un borrador de una rama cuya carpeta
 * todavía no aparece en ningún reporte no tiene quién lo mire — ahí no hay
 * progreso que seguir, sólo un archivo que aún no existe para el panel.
 *
 * Módulo sin `vscode`, como `soleTarget`: la decisión de qué mirar es pura y
 * se testea sin editor. El watcher en sí vive en `repository.ts`.
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

/**
 * Lo que hace falta de un `ReviewState` para decidir si un guardado toca una
 * guía de autoría. Estructural, por lo mismo que `DraftPathSource`.
 */
export interface GuidePathSource {
    /** Registros `guide` de `config --porcelain` (siempre los dos). */
    guides?: readonly {path: string}[];
    /**
     * El registro `walkthrough`, por el mismo motivo y con la misma regla. El
     * watcher tampoco lo mira: vive en el work tree, así que toda operación de
     * git lo mueve, y el cliente que corre init/build refresca solo. Lo que
     * queda sin cubrir es idéntico al de las guías — lo escribís a mano y
     * guardás — y se cubre igual.
     */
    walkthrough?: {path: string};
}

/**
 * Si `file` es una de las guías que la CLI reportó.
 *
 * Existe porque las guías **no** las mira el watcher, a propósito: la propia
 * vive en la RAÍZ del gitdir, que cambia en cada operación de git, así que
 * vigilar ese directorio sería una tormenta de refrescos por el archivo que
 * menos cambia del panel.
 *
 * Pero hay un momento en que el panel miente sin esto: apretás *Create*, se
 * abre el archivo vacío, escribís las convenciones, Ctrl+S — y el badge sigue
 * diciendo `empty`, porque el estado sale del disco y nadie volvió a mirarlo.
 * El guardado es la señal exacta, no cuesta un watcher, y sólo dispara sobre
 * rutas que la CLI ya reportó.
 */
export function isReportedGuide(
    state: GuidePathSource,
    file: string,
    platform: string = process.platform
): boolean {
    const normalise = (p: string): string => {
        const slashed = p.replace(/\\/g, "/");
        return platform === "win32" ? slashed.toLowerCase() : slashed;
    };
    const target = normalise(file);
    if ((state.guides ?? []).some((guide) => normalise(guide.path) === target)) {
        return true;
    }
    return state.walkthrough !== undefined && normalise(state.walkthrough.path) === target;
}
