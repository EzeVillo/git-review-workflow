import * as vscode from "vscode";
import {InvokeOptions} from "./cli/invoke";
import {EntryRecord} from "./cli/porcelain";
import {PathRef} from "./cli/unquote";
import {installOrUpdateCli, showOutOfRangeHelp} from "./commands/installOrUpdateCli";
import {navigate} from "./commands/navigate";
import {openChange, openEntry} from "./commands/openEntry";
import {
    getGitApi,
    GitApi,
    listRepositoryTargets,
    RepositoryTarget,
    watchGitApiChanges,
    watchGitDirFallback,
    workspaceFolderTargets,
} from "./review/repository";
import {MutationLock} from "./review/mutationLock";
import {resolveEntryArg} from "./review/entryArg";
import {ReviewState, ReviewStateManager} from "./review/state";
import {WHY_SCHEME, WhyContentProvider, whyUri} from "./views/whyContentProvider";
import {WalkthroughTreeProvider} from "./views/walkthroughTreeProvider";

function isPathRef(id: string | PathRef): id is PathRef {
    return typeof id !== "string";
}

function configuredGitReviewPath(): string | undefined {
    const value = vscode.workspace.getConfiguration("gitReview").get<string>("path", "");
    return value.trim() === "" ? undefined : value;
}

/**
 * Superficie mínima expuesta vía `extensions.getExtension(id).exports` para
 * los tests de integración: no hay API pública para leer el contenido
 * renderizado de un `TreeView`, así que las specs inspeccionan el
 * `TreeDataProvider` y el `ReviewState` directamente en vez de reabrir una
 * ventana de VS Code por cada estado de fixture.
 */
export interface GitReviewTestApi {
    refresh(): Promise<ReviewState>;

    getState(): ReviewState;

    getTreeProvider(): WalkthroughTreeProvider;

    /** Fuerza el re-chequeo de `--version` en el próximo refresh (ver ReviewStateManager). */
    invalidateVersionCheck(): void;
}

export function activate(context: vscode.ExtensionContext): GitReviewTestApi {
    let target: RepositoryTarget | undefined;
    let allTargets: RepositoryTarget[] = [];
    let gitApi: GitApi | undefined;

    function getInvokeOptions(): InvokeOptions {
        return {cwd: target?.rootUri.fsPath ?? "", gitReviewPath: configuredGitReviewPath()};
    }

    const stateManager = new ReviewStateManager(getInvokeOptions);
    const lock = new MutationLock();
    const treeProvider = new WalkthroughTreeProvider(() => stateManager.state, getInvokeOptions);
    const whyProvider = new WhyContentProvider(getInvokeOptions);

    const treeView = vscode.window.createTreeView("gitReview.walkthrough", {
        treeDataProvider: treeProvider,
        showCollapseAll: false,
    });

    function updateContextKeys(state: ReviewState): void {
        void vscode.commands.executeCommand("setContext", "gitReview.situation", state.situation);
        void vscode.commands.executeCommand("setContext", "gitReview.mode", state.state?.mode);
        void vscode.commands.executeCommand("setContext", "gitReview.busy", lock.isBusy);
    }

    function multiRootSuffix(): string {
        return allTargets.length > 1 && target ? ` — ${target.label}` : "";
    }

    function updateView(state: ReviewState): void {
        treeProvider.refresh();
        updateContextKeys(state);

        if (lock.isBusy) {
            treeView.message = "trabajando…";
        } else if (state.situation === "review" && state.state?.mode === "whole" && state.state.walkthrough === "degraded") {
            treeView.message = "El walkthrough no cubre el rango actual de la review; se muestra el diff completo del rango.";
        } else {
            treeView.message = undefined;
        }

        const s = state.state;
        if (state.situation === "review" && s && (s.mode === "step" || s.mode === "walk") && s.position !== undefined && s.total !== undefined) {
            let description = `${s.position}/${s.total}`;
            if (s.recorded !== undefined && s.total !== s.recorded) {
                description += " (la base se movió)";
            }
            treeView.description = description + multiRootSuffix();
        } else if (allTargets.length > 1 && target) {
            treeView.description = target.label;
        } else {
            treeView.description = undefined;
        }
    }

    /** Ver `resolveEntryArg`: los íconos inline pasan el nodo, la paleta no pasa nada. */
    function resolveArgEntry(arg: unknown): EntryRecord | undefined {
        const state = stateManager.state;
        if (state.situation !== "review" || !state.state) {
            return undefined;
        }
        return resolveEntryArg(arg, state.entries, state.state.position);
    }

    async function refresh(): Promise<ReviewState> {
        const state = await stateManager.refresh();
        updateView(state);
        return state;
    }

    lock.onDidChangeBusy(() => updateView(stateManager.state));
    stateManager.onDidChange((state) => updateView(state));

    context.subscriptions.push(
        vscode.workspace.onDidChangeConfiguration((e) => {
            if (e.affectsConfiguration("gitReview.path")) {
                stateManager.invalidateVersionCheck();
                void refresh();
            }
        })
    );

    function resolveTargets(): void {
        allTargets = gitApi ? listRepositoryTargets(gitApi) : [];
        // La extensión git puede no haber terminado de escanear los repos del
        // workspace todavía (activación perezosa, o justo después de abrir la
        // ventana): mientras tanto, cada carpeta del workspace es un target
        // razonable por sí sola — es el mismo `cwd` que usaría un `git review`
        // corrido a mano ahí. `watchGitApiChanges` re-resuelve cuando la API
        // se pone al día.
        if (allTargets.length === 0) {
            allTargets = workspaceFolderTargets();
        }
        if (!target || !allTargets.some((t) => t.rootUri.toString() === target?.rootUri.toString())) {
            target = allTargets[0];
        }
    }

    gitApi = getGitApi();
    resolveTargets();
    if (gitApi) {
        context.subscriptions.push(
            watchGitApiChanges(gitApi, () => {
                resolveTargets();
                void refresh();
            })
        );
    } else if (target) {
        context.subscriptions.push(watchGitDirFallback(target.rootUri, () => void refresh()));
    }

    context.subscriptions.push(
        treeView,
        vscode.workspace.registerTextDocumentContentProvider(WHY_SCHEME, whyProvider),

        vscode.commands.registerCommand("gitReview.openEntry", async (arg?: unknown) => {
            const state = stateManager.state;
            const entry = resolveArgEntry(arg);
            if (!target || !entry || state.situation !== "review" || !state.state) {
                return;
            }
            await openEntry(target.rootUri, state.state.mode, entry, gitApi);
        }),

        vscode.commands.registerCommand("gitReview.openChange", async (arg?: unknown) => {
            const state = stateManager.state;
            const entry = resolveArgEntry(arg);
            if (!target || !entry || state.situation !== "review" || !state.state) {
                return;
            }
            await openChange(target.rootUri, state.state.mode, entry, gitApi);
        }),

        vscode.commands.registerCommand("gitReview.showWhy", async (arg?: unknown) => {
            const entry = resolveArgEntry(arg);
            if (!entry || !isPathRef(entry.id)) {
                return;
            }
            const uri = whyUri(entry.id.display, entry.id.raw);
            await vscode.commands.executeCommand("markdown.showPreview", uri);
        }),

        vscode.commands.registerCommand("gitReview.next", () => navigate("next", lock, stateManager, getInvokeOptions, gitApi)),
        vscode.commands.registerCommand("gitReview.prev", () => navigate("prev", lock, stateManager, getInvokeOptions, gitApi)),
        vscode.commands.registerCommand("gitReview.refresh", () => refresh()),
        vscode.commands.registerCommand("gitReview.installCli", () => installOrUpdateCli()),
        vscode.commands.registerCommand("gitReview.showOutOfRangeHelp", () => showOutOfRangeHelp(stateManager.state.stderr))
    );

    updateContextKeys(stateManager.state);
    void refresh();

    return {
        refresh,
        getState: () => stateManager.state,
        getTreeProvider: () => treeProvider,
        invalidateVersionCheck: () => stateManager.invalidateVersionCheck(),
    };
}

export function deactivate(): void {
    // Nada que liberar más allá de context.subscriptions: sin timers, sin
    // estado persistente propio (FR-001/FR-002).
}
