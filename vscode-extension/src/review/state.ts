import * as vscode from "vscode";
import {
    CandidateBranch,
    CandidateRemote,
    DraftRecord,
    EffectiveConfig,
    parseConfigPorcelain,
} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {
    BranchRecord,
    EntryRecord,
    parseListPorcelain,
    parsePorcelain,
    StateRecord,
    StatusFinishRecord,
} from "../cli/porcelain";
import {isOutdated} from "../cli/version";
import {Situation, situationFor, situationForExitCode} from "./situation";

export type {Situation} from "./situation";

export interface ReviewState {
    situation: Situation;
    /** Sólo presente cuando situation === "review". */
    state?: StateRecord;
    entries: EntryRecord[];
    /**
     * Inventario de reviews del repositorio (`list --porcelain`). Se puebla
     * con `no-review` (el panel lo dibuja) y con `finish-pending` (deriva la
     * situación y el source del Clean / Undo; el panel no lista filas).
     * Dentro de una review activa no se invoca: un proceso extra por refresco
     * iría contra SC-002 (contracts/cli-invocation.md § `list --porcelain`).
     */
    branches: BranchRecord[];
    /**
     * La config efectiva y las ramas candidatas de `git review config
     * --porcelain` — lo que el asistente de inicio necesita antes de que
     * exista una review (contracts/config-porcelain.md). Se puebla con
     * `no-review` y con `finish-pending` (Start sigue en la paleta), con el
     * mismo criterio que `branches`: con una review activa esto no se invoca
     * (T022a), así que en cualquier otra situación quedan ausentes, nunca un
     * reporte viejo.
     */
    config?: EffectiveConfig;
    /** Ver `config`; ausente (no `[]`) cuando el reporte no llegó, para no confundirlo con "cero candidatas". */
    candidates?: CandidateBranch[];
    /**
     * Remotos del repositorio (`remote-candidate`). Ausente cuando el reporte
     * no llegó; `[]` si llegó sin remotes (repositorio sin `git remote`).
     */
    remotes?: CandidateRemote[];
    /**
     * Borradores de walkthrough sueltos del working tree (registro `draft` de
     * `config --porcelain`, 012). Se pueblan en el mismo reporte que `config`,
     * sin invocaciones nuevas. Ausente cuando ese reporte no llegó; `[]` si
     * llegó y no hay ninguno.
     */
    drafts?: DraftRecord[];
    /**
     * Asunto y autor de cada commit de la secuencia, por `position`. Sólo en
     * modo step, y sólo con una CLI que los reporte: ausentes significa "esta
     * CLI no los provee", no "esta review no los tiene" (FR-003/FR-004).
     */
    subjects?: Map<number, string>;
    authors?: Map<number, string>;
    /**
     * Base contra la que se armó el rango. Sólo en modo whole, y sólo si hay
     * una registrada: sin base el registro no llega, y eso no es un error.
     */
    base?: string;
    /**
     * Archivos del commit actual en modo step (registros `file`). Ausente o
     * vacío fuera de step o cuando el commit no toca paths. No son las
     * entradas de la secuencia (`entries` sigue siendo commits).
     */
    files?: EntryRecord[];
    /**
     * El cierre trabado que llevó a `situation === "finish-conflict"`
     * (contracts/finish-state.md). Ausente en cualquier otra situación — el
     * cierre `pending` que lleva a `finish-pending` no vive acá, sino en la
     * fila `finish` del `BranchRecord` correspondiente dentro de `branches`,
     * que es donde `list --porcelain` lo reporta.
     */
    finish?: StatusFinishRecord;
    /**
     * Compare de solo lectura (`status --porcelain` → registro `readonly`).
     * Ausente cuando la CLI no lo emitió; no se inventa `false`.
     */
    readonly?: true;
    /**
     * Walk solo-keys (`status --porcelain` → registro `keys`). Ausente cuando
     * la CLI no lo emitió; no se inventa `false`.
     */
    keysOnly?: true;
    /**
     * El orden de lectura es el borrador del revisor (`status --porcelain` →
     * registro `draft`, 011). Ausente cuando la CLI no lo emitió.
     */
    draft?: true;
    /**
     * Ruta absoluta de ese borrador, tal como la reportó la CLI (012). Aparte
     * del booleano: la presencia es la presencia, y el cliente abre esta ruta
     * en vez de armarla.
     */
    draftPath?: string;
    /** stderr crudo de la CLI; presente en error/out-of-range/cli-missing/cli-outdated. */
    stderr?: string;
}

export type ReviewStateOptions = InvokeOptions;

const EMPTY_ARRAYS = {
    entries: [] as EntryRecord[],
    branches: [] as BranchRecord[],
};

/**
 * Corre `--version` y traduce el resultado a `cli-missing`/`cli-outdated`, o
 * `undefined` si la CLI está presente y al día (contracts/cli-invocation.md
 * § "git review --version").
 */
async function checkCliVersion(options: ReviewStateOptions): Promise<Situation | undefined> {
    const result = await invokeGitReview("--version", [], options);
    if (result.errorCode || result.exitCode !== 0) {
        return "cli-missing";
    }
    const version = result.stdout.trim();
    if (isOutdated(version)) {
        return "cli-outdated";
    }
    return undefined;
}

/**
 * Corre `list --porcelain` para el inventario del estado vacío. Su fallo **no**
 * es una situación: un inventario que no se pudo leer deja el estado vacío como
 * era antes de existir esta superficie, no lo convierte en un error — la
 * situación ya la fijó `status --porcelain`, que es quien la reporta.
 */
async function listBranches(options: ReviewStateOptions): Promise<BranchRecord[]> {
    const result = await invokeGitReview("list", ["--porcelain"], options);
    if (result.errorCode || result.exitCode !== 0) {
        return [];
    }
    return parseListPorcelain(result.stdout);
}

/**
 * Corre `config --porcelain` para el asistente de inicio y el estado vacío
 * (contracts/cli-invocation.md § `config --porcelain`). Mismo criterio que
 * `listBranches`: su fallo **no** es una situación — deja el estado vacío
 * como estaba, sin `config` ni `candidates`, en vez de convertirlo en un error
 * que ya decidió `status --porcelain`.
 */
async function loadConfigReport(
    options: ReviewStateOptions
): Promise<{
    config?: EffectiveConfig;
    candidates: CandidateBranch[];
    remotes: CandidateRemote[];
    drafts: DraftRecord[];
}> {
    const result = await invokeGitReview("config", ["--porcelain"], options);
    if (result.errorCode || result.exitCode !== 0) {
        return {candidates: [], remotes: [], drafts: []};
    }
    const parsed = parseConfigPorcelain(result.stdout);
    return {
        config: parsed.config,
        candidates: parsed.candidates,
        remotes: parsed.remotes,
        drafts: parsed.drafts,
    };
}

/**
 * Dueño del `ReviewState` derivado de la CLI (data-model.md). Nunca deriva
 * estado por su cuenta: cada `refresh()` reinvoca `git review --version` (sólo
 * cuando hace falta) y `status --porcelain`, y descarta el resultado anterior
 * (FR-001, FR-002). Aplica las dos políticas de concurrencia de research.md
 * Decisión 9: acá, coalescencia de lecturas — un refresco pedido mientras hay
 * uno en vuelo se marca "sucio" y se re-corre una sola vez al terminar.
 */
export class ReviewStateManager {
    // Generación en vez de booleano: invalidar mientras un checkCliVersion
    // viejo está en vuelo (p. ej. gitReview.path editado dos veces seguidas)
    // no puede dejar que ese resultado obsoleto marque la generación NUEVA
    // como verificada al volver — sería la misma clase de dato caduco que
    // Decisión 9 evita del lado de las lecturas coalescidas.
    private versionCheckGeneration = 0;
    private versionCheckedGeneration = -1;
    private current: ReviewState = {situation: "no-review", ...EMPTY_ARRAYS};
    private inFlight: Promise<ReviewState> | undefined;
    private dirty = false;
    private waiters: Array<(state: ReviewState) => void> = [];

    private readonly changeEmitter = new vscode.EventEmitter<ReviewState>();
    readonly onDidChange = this.changeEmitter.event;

    constructor(private readonly getOptions: () => ReviewStateOptions) {
    }

    get state(): ReviewState {
        return this.current;
    }

    /**
     * Fuerza que el próximo `refresh()` vuelva a correr `--version` aunque ya
     * se haya verificado antes en esta activación — para cuando cambió lo que
     * `--version` podría reportar (`gitReview.path` editado en caliente).
     */
    invalidateVersionCheck(): void {
        this.versionCheckGeneration++;
    }

    /**
     * Coalescencia de lecturas: un refresco pedido mientras hay uno en vuelo
     * se marca "sucio" y espera al re-run que corre una sola vez al terminar
     * — nunca al resultado del refresco que ya estaba en vuelo cuando llegó,
     * que para ese momento puede haber quedado obsoleto.
     */
    async refresh(): Promise<ReviewState> {
        if (this.inFlight) {
            this.dirty = true;
            return new Promise<ReviewState>((resolve) => this.waiters.push(resolve));
        }

        let result: ReviewState;
        do {
            this.dirty = false;
            this.inFlight = this.doRefresh();
            result = await this.inFlight;
            this.inFlight = undefined;
        } while (this.dirty);

        const waiters = this.waiters;
        this.waiters = [];
        for (const resolve of waiters) {
            resolve(result);
        }
        return result;
    }

    dispose(): void {
        this.changeEmitter.dispose();
    }

    private setState(next: ReviewState): ReviewState {
        this.current = next;
        this.changeEmitter.fire(next);
        return next;
    }

    private async doRefresh(): Promise<ReviewState> {
        const options = this.getOptions();
        // Sin cwd no hay `git review` que invocar (multi-root ambiguo o workspace
        // sin carpeta): no inventar un proceso en process.cwd() del host.
        if (!options.cwd) {
            return this.setState({
                situation: "error",
                ...EMPTY_ARRAYS,
                stderr:
                    "Open a single-folder workspace that is a git repository. git review uses one root (like the CLI cwd); multi-root is not supported.",
            });
        }
        const generation = this.versionCheckGeneration;

        if (this.versionCheckedGeneration !== generation || this.current.situation === "cli-missing") {
            const versionIssue = await checkCliVersion(options);
            if (versionIssue) {
                return this.setState({situation: versionIssue, ...EMPTY_ARRAYS});
            }
            // No marcar la generación como verificada si alguien invalidó
            // mientras este chequeo estaba en vuelo: ese resultado ya es
            // sobre un `gitReview.path` que dejó de ser el vigente.
            if (this.versionCheckGeneration === generation) {
                this.versionCheckedGeneration = generation;
            }
        }

        const result = await invokeGitReview("status", ["--porcelain"], options);
        if (result.errorCode) {
            this.invalidateVersionCheck();
            return this.setState({
                situation: "cli-missing", ...EMPTY_ARRAYS,
                stderr: result.stderr
            });
        }
        // Un timeout llega con exitCode null y sin errorCode, o sea que caería
        // en `error` con el stderr vacío: el panel diría que algo falló sin
        // decir qué, que es lo peor que puede decir de una CLI que está sana y
        // sólo tardó. La situación sigue siendo `error` (no hay estado que
        // mostrar), pero con un diagnóstico que apunta a dónde mirar.
        if (result.timedOut) {
            return this.setState({
                situation: "error", ...EMPTY_ARRAYS,
                stderr:
                    "`git review status --porcelain` did not finish in time and was stopped. " +
                    "Run it in a terminal to see how long it takes; if the CLI is an old " +
                    "version, updating it may be enough. See the Git Review CLI output channel.",
            });
        }

        const baseSituation = situationForExitCode(result.exitCode);
        if (baseSituation !== "review") {
            // El inventario y la config son contenido del estado vacío de
            // `no-review` y de ningún otro: en out-of-range o error lo que hay
            // para mostrar es el stderr, y en cli-missing no hay CLI a la que
            // preguntarle. `finish-pending` se apoya en ESTE mismo inventario
            // (contracts/finish-state.md) — no agrega una invocación nueva:
            // ya se llama a `listBranches` con exit 2, sólo falta mirar si
            // trae una fila `finish … pending`.
            const branches = baseSituation === "no-review" ? await listBranches(options) : [];
            const hasFinishPending = branches.some((branch) => branch.finish?.state === "pending");
            const situation = situationFor(result.exitCode, false, hasFinishPending);
            const next: ReviewState = {situation, ...EMPTY_ARRAYS, branches, stderr: result.stderr};
            if (situation === "no-review" || situation === "finish-pending") {
                const report = await loadConfigReport(options);
                // La señal de "el reporte llegó" es config, no el largo de
                // candidates: con esa condición, un reporte exitoso con cero
                // candidatas (un repositorio sin ramas elegibles) era
                // indistinguible de un reporte que falló (M1, revisión Fase 3).
                if (report.config !== undefined) {
                    next.config = report.config;
                    next.candidates = report.candidates;
                    next.remotes = report.remotes;
                    next.drafts = report.drafts;
                }
            }
            return this.setState(next);
        }

        let parsed;
        try {
            parsed = parsePorcelain(result.stdout);
        } catch (err) {
            const message =
                err instanceof Error ? err.message : "failed to parse git review status --porcelain";
            return this.setState({
                situation: "error",
                ...EMPTY_ARRAYS,
                stderr: result.stderr.trim().length > 0 ? result.stderr : message,
            });
        }
        const situation = situationFor(result.exitCode, parsed.finish !== undefined, false);
        const next: ReviewState = {
            situation,
            state: parsed.state,
            entries: parsed.entries,
            files: parsed.files,
            branches: [],
        };
        // Se copian sólo si llegaron: asignar `undefined` explícito daría lo
        // mismo hoy, pero la ausencia es un dato y conviene que se lea como tal.
        if (parsed.subjects) {
            next.subjects = parsed.subjects;
        }
        if (parsed.authors) {
            next.authors = parsed.authors;
        }
        if (parsed.base !== undefined) {
            next.base = parsed.base;
        }
        if (parsed.finish !== undefined) {
            next.finish = parsed.finish;
        }
        if (parsed.readonly) {
            next.readonly = true;
        }
        if (parsed.keysOnly) {
            next.keysOnly = true;
        }
        if (parsed.draft) {
            next.draft = true;
        }
        if (parsed.draftPath !== undefined) {
            next.draftPath = parsed.draftPath;
        }
        return this.setState(next);
    }
}
