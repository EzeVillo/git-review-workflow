import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {
    BranchRecord,
    EntryRecord,
    parseListPorcelain,
    parsePorcelain,
    StateRecord,
} from "../cli/porcelain";
import {isOutdated} from "../cli/version";
import {Situation, situationForExitCode} from "./situation";

export type {Situation} from "./situation";

export interface ReviewState {
    situation: Situation;
    /** Sólo presente cuando situation === "review". */
    state?: StateRecord;
    entries: EntryRecord[];
    /**
     * Inventario de reviews del repositorio. Se puebla **sólo** con
     * `no-review`: es el único estado que lo muestra, y estando dentro de una
     * review agregar un proceso por refresco iría contra SC-002
     * (contracts/cli-invocation.md § `list --porcelain`).
     */
    branches: BranchRecord[];
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

        const situation = situationForExitCode(result.exitCode);
        if (situation !== "review") {
            // El inventario es contenido del estado vacío de `no-review` y de
            // ningún otro: en out-of-range o error lo que hay para mostrar es
            // el stderr, y en cli-missing no hay CLI a la que preguntarle.
            const branches = situation === "no-review" ? await listBranches(options) : [];
            return this.setState({situation, ...EMPTY_ARRAYS, branches, stderr: result.stderr});
        }

        const parsed = parsePorcelain(result.stdout);
        const next: ReviewState = {
            situation: "review",
            state: parsed.state,
            entries: parsed.entries,
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
        return this.setState(next);
    }
}
