import * as vscode from "vscode";
import {initCliLog, showCliLog} from "./cli/cliLog";
import {InvokeOptions} from "./cli/invoke";
import {EntryRecord} from "./cli/porcelain";
import {PathRef} from "./cli/unquote";
import {abortReview} from "./commands/abortReview";
import {cleanReview} from "./commands/cleanReview";
import {compareReview} from "./commands/compareReview";
import {continueReview} from "./commands/continueReview";
import {discardInventoryReview, forgetReview} from "./commands/forgetReview";
import {finishReview, resumeFinish, undoFinish} from "./commands/finishReview";
import {saveReview} from "./commands/saveReview";
import {
    copyCliInstallCommand,
    installOrUpdateCli,
    showOutOfRangeHelp,
} from "./commands/installOrUpdateCli";
import {navigate} from "./commands/navigate";
import {openChange, openEntry, openRangeChanges} from "./commands/openEntry";
import {pickEntry} from "./commands/pickEntry";
import {previewEdits} from "./commands/previewEdits";
import {setBase} from "./commands/setBase";
import {setRemote} from "./commands/setRemote";
import {startReview} from "./commands/startReview";
import {walkthroughBuild, walkthroughInit} from "./commands/walkthrough";
import {
    ensureGitApi,
    GitApi,
    listRepositoryTargets,
    peekGitApi,
    pickSoleTarget,
    RepositoryTarget,
    watchGitApiChanges,
    watchGitDirFallback,
    workspaceFolderTargets,
} from "./review/repository";
import {CLI_PROBE_INTERVAL_MS, shouldProbeCli} from "./review/cliProbe";
import {MutationLock} from "./review/mutationLock";
import {resolveEntryArg} from "./review/entryArg";
import {isReviewReadable} from "./review/situation";
import {ReviewState, ReviewStateManager} from "./review/state";
import {buildPanelModel, currentEntry, PanelModel, PanelWhy} from "./views/panelModel";
import {fetchWhy, WHY_SCHEME, WhyContentProvider, whyUri} from "./views/whyContentProvider";
import {
    PanelMessage,
    SUPPORT_URLS,
    SupportLinkId,
    WalkthroughViewProvider,
} from "./views/walkthroughViewProvider";

function isPathRef(id: string | PathRef): id is PathRef {
    return typeof id !== "string";
}

function configuredGitReviewPath(): string | undefined {
    const value = vscode.workspace.getConfiguration("gitReview").get<string>("path", "");
    return value.trim() === "" ? undefined : value;
}

/**
 * Lo único que la extensión guarda de una sesión a la otra: por rama de review,
 * el `display` del último archivo que se abrió desde la lista de `whole`.
 *
 * No contradice FR-001/FR-002 —seguir sin derivar estado del review—: la lista
 * de whole no tiene cursor, ni la CLI uno que consultar, así que "por dónde
 * iba" no es un dato que exista del lado del review. Lo sabe únicamente el
 * editor, que es quien abrió el diff, y sin persistirlo la marca moriría cada
 * vez que se cierra la ventana. Nada de esto influye en lo que la CLI reporta:
 * si el archivo dejó de estar en el rango, el modelo descarta la marca.
 */
const LAST_OPENED_KEY = "gitReview.lastOpened";

/**
 * Cuántas reviews se recuerdan. No hay evento de "review terminada" que
 * escuchar, así que el mapa sobreviviría a las ramas que lo poblaron; se lo
 * acota por uso, que es la única señal disponible desde acá.
 */
const LAST_OPENED_LIMIT = 20;

/**
 * Superficie mínima expuesta vía `extensions.getExtension(id).exports` para
 * los tests de integración: un webview corre en su propio contexto y no hay API
 * para inspeccionarlo desde el host, así que las specs afirman sobre el
 * `PanelModel` que se le postea y sobre el `ReviewState` (research.md Decisión
 * 11, "dónde se corta la integración").
 */
export interface GitReviewTestApi {
    refresh(): Promise<ReviewState>;

    getState(): ReviewState;

    /** El modelo que ve el panel, con el *why* de la entrada actual ya resuelto. */
    getPanelModel(): Promise<PanelModel>;

    /** Fuerza el re-chequeo de `--version` en el próximo refresh (ver ReviewStateManager). */
    invalidateVersionCheck(): void;
}

export function activate(context: vscode.ExtensionContext): GitReviewTestApi {
    let target: RepositoryTarget | undefined;
    let allTargets: RepositoryTarget[] = [];
    let gitApi: GitApi | undefined;

    // Log de cada `git review …` (invokeGitReview). Siempre on; no se auto-abre.
    initCliLog(context.subscriptions);

    function getInvokeOptions(): InvokeOptions {
        return {cwd: target?.rootUri.fsPath ?? "", gitReviewPath: configuredGitReviewPath()};
    }

    const stateManager = new ReviewStateManager(getInvokeOptions);
    const lock = new MutationLock();
    const whyProvider = new WhyContentProvider(getInvokeOptions);
    const panelProvider = new WalkthroughViewProvider(handlePanelMessage);

    // El *why* de la entrada actual: una invocación aparte, para UNA entrada,
    // que llega después del `status --porcelain` (FR-018a, SC-009). `whyKey`
    // evita repedirlo en cada refresco del watcher mientras el cursor no se
    // mueve; `whyGeneration` descarta la respuesta de una entrada que dejó de
    // ser la actual — el revisor puede avanzar dos veces antes de que la
    // primera explicación vuelva.
    let whyGeneration = 0;
    let whyKey: string | undefined;
    let currentWhy: PanelWhy | undefined;
    let whyPending: Promise<void> | undefined;

    function multiRootLabel(): string | undefined {
        // Solo hay target cuando hay exactamente un root; la etiqueta multi-root
        // del panel no aplica (no se elige entre N). Se deja por si el modelo
        // la pide con un único repo abierto en un workspace multi-folder.
        return allTargets.length > 1 && target ? target.label : undefined;
    }

    /** Clave de la entrada cuyo *why* corresponde mostrar, o `undefined` si no hay. */
    function whyTarget(state: ReviewState): { key: string; raw: string } | undefined {
        const review = state.state;
        if (!isReviewReadable(state.situation) || !review || review.mode !== "walk") {
            return undefined;
        }
        const entry = currentEntry(state.entries, review.position);
        if (!entry || !isPathRef(entry.id)) {
            return undefined;
        }
        return {key: `${review.branch}${entry.id.raw}`, raw: entry.id.raw};
    }

    function loadWhy(raw: string): void {
        const generation = ++whyGeneration;
        whyPending = (async () => {
            const why = await fetchWhy(raw, getInvokeOptions());
            if (generation !== whyGeneration) {
                return;
            }
            if (why === undefined) {
                currentWhy = {state: "failed"};
            } else if (why.present) {
                currentWhy = {state: "present", text: why.text};
            } else {
                currentWhy = {state: "absent"};
            }
            panelProvider.update(buildModel());
        })();
    }

    function lastOpenedMap(): Record<string, string> {
        return {...context.workspaceState.get<Record<string, string>>(LAST_OPENED_KEY, {})};
    }

    function lastOpenedFor(state: ReviewState): string | undefined {
        const branch = state.state?.branch;
        return branch === undefined ? undefined : lastOpenedMap()[branch];
    }

    /**
     * Registra la fila que se acaba de abrir y redibuja el panel con la marca.
     * Sólo en whole: en step/walk la entrada abierta es siempre la del cursor,
     * que ya está en pantalla, y una marca ahí sería una copia.
     */
    function rememberOpened(state: ReviewState, entry: EntryRecord): void {
        const review = state.state;
        if (state.situation !== "review" || !review || review.mode !== "whole") {
            return;
        }
        const map = lastOpenedMap();
        // Se borra antes de escribir para que la clave quede al final del orden
        // de inserción: es lo que hace que el recorte de abajo saque las reviews
        // menos usadas y no la que se acaba de tocar.
        delete map[review.branch];
        map[review.branch] = isPathRef(entry.id) ? entry.id.display : entry.id;
        const keys = Object.keys(map);
        for (const key of keys.slice(0, Math.max(0, keys.length - LAST_OPENED_LIMIT))) {
            delete map[key];
        }
        void context.workspaceState.update(LAST_OPENED_KEY, map);
        panelProvider.update(buildModel());
    }

    function buildModel(): PanelModel {
        return buildPanelModel(stateManager.state, {
            busy: lock.isBusy,
            repoLabel: multiRootLabel(),
            why: currentWhy,
            lastOpened: lastOpenedFor(stateManager.state),
        });
    }

    function updateContextKeys(state: ReviewState): void {
        void vscode.commands.executeCommand("setContext", "gitReview.situation", state.situation);
        void vscode.commands.executeCommand("setContext", "gitReview.mode", state.state?.mode);
        void vscode.commands.executeCommand("setContext", "gitReview.busy", lock.isBusy);
        // Compare: finish se oculta en view/title y palette (package.json when).
        void vscode.commands.executeCommand("setContext", "gitReview.readonly", state.readonly === true);
    }

    function updateView(state: ReviewState): void {
        const wanted = whyTarget(state);
        if (wanted?.key !== whyKey) {
            whyKey = wanted?.key;
            currentWhy = undefined;
            whyGeneration++;
            whyPending = undefined;
            if (wanted) {
                loadWhy(wanted.raw);
            }
        }
        panelProvider.update(buildModel());
        updateContextKeys(state);
    }

    /**
     * El webview no ejecuta comandos: postea uno de un conjunto cerrado y acá se
     * decide (contracts/extension-surface.md § Protocolo).
     */
    function handlePanelMessage(message: PanelMessage, extra?: unknown): void {
        // Support: no hay comando de paleta; el host resuelve el id contra el
        // allowlist y abre el browser. Un id desconocido se ignora.
        if (message === "openSupport") {
            if (typeof extra === "string" && extra in SUPPORT_URLS) {
                void vscode.env.openExternal(
                    vscode.Uri.parse(SUPPORT_URLS[extra as SupportLinkId]),
                );
            }
            return;
        }
        // Copy del empty state cli-*: el webview manda kind; el host resuelve
        // el string npm allowlisteado (no se confía texto del panel).
        if (message === "copyCliInstall") {
            void copyCliInstallCommand(extra);
            return;
        }
        const commands: Record<Exclude<PanelMessage, "openSupport" | "copyCliInstall">, string> = {
            openEntry: "gitReview.openEntry",
            openChange: "gitReview.openChange",
            openAllChanges: "gitReview.openAllChanges",
            showWhy: "gitReview.showWhy",
            next: "gitReview.next",
            prev: "gitReview.prev",
            refresh: "gitReview.refresh",
            installCli: "gitReview.installCli",
            outOfRangeHelp: "gitReview.showOutOfRangeHelp",
            continueReview: "gitReview.continueReview",
            startReview: "gitReview.startReview",
            setBase: "gitReview.setBase",
            setRemote: "gitReview.setRemote",
            undoFinish: "gitReview.undoFinish",
            resumeFinish: "gitReview.resumeFinish",
            discardInventory: "gitReview.discardInventory",
            cleanReview: "gitReview.cleanReview",
            compareReview: "gitReview.compareReview",
            walkthroughInit: "gitReview.walkthroughInit",
            walkthroughBuild: "gitReview.walkthroughBuild",
        };
        // El índice viaja tal cual y lo valida el comando contra el estado del
        // host (extension-surface.md § Protocolo): en el inventario resuelve una
        // fila, acá una entrada por `position` — la fila de whole no tiene una
        // "actual" a la que resolverArgEntry pueda caer por default.
        // cleanReview desde finish-pending no lleva índice: el comando resuelve
        // el source del pending desde state.
        if (message === "continueReview" || message === "discardInventory") {
            void vscode.commands.executeCommand(commands[message], extra);
            return;
        }
        if (message === "openEntry" || message === "openChange") {
            const state = stateManager.state;
            const entry = typeof extra === "number" ? currentEntry(state.entries, extra) : undefined;
            if (entry) {
                void vscode.commands.executeCommand(commands[message], entry);
                return;
            }
        }
        void vscode.commands.executeCommand(commands[message]);
    }

    /** Ver `resolveEntryArg`: la paleta no pasa nada, y ahí la entrada es la actual. */
    function resolveArgEntry(arg: unknown): EntryRecord | undefined {
        const state = stateManager.state;
        if (!isReviewReadable(state.situation) || !state.state) {
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
    // FR-036: palette/atajos no ven gitReview.busy del panel; avisar el descarte.
    context.subscriptions.push(
        lock.onDidDiscard((reason) => {
            void vscode.window.showInformationMessage(reason);
        })
    );
    stateManager.onDidChange((state) => {
        updateView(state);
        syncCliProbe();
    });

    /**
     * Mientras el panel está abierto y la CLI falta o es vieja, reintenta
     * `--version` cada 10s: instalar/actualizar fuera de VS Code no emite
     * evento al host. Fuera de esos dos estados (o con el panel oculto) el
     * timer no corre — no es el polling general de estado que se descartó.
     */
    let cliProbeTimer: ReturnType<typeof setInterval> | undefined;

    function stopCliProbe(): void {
        if (cliProbeTimer !== undefined) {
            clearInterval(cliProbeTimer);
            cliProbeTimer = undefined;
        }
    }

    function syncCliProbe(): void {
        const want = shouldProbeCli(stateManager.state.situation, panelProvider.isVisible);
        if (!want) {
            stopCliProbe();
            return;
        }
        if (cliProbeTimer !== undefined) {
            return;
        }
        cliProbeTimer = setInterval(() => {
            if (!shouldProbeCli(stateManager.state.situation, panelProvider.isVisible)) {
                stopCliProbe();
                return;
            }
            stateManager.invalidateVersionCheck();
            void refresh();
        }, CLI_PROBE_INTERVAL_MS);
    }

    context.subscriptions.push(
        panelProvider.onDidChangeVisibility(() => syncCliProbe()),
        {dispose: () => stopCliProbe()},
        vscode.workspace.onDidChangeConfiguration((e) => {
            if (e.affectsConfiguration("gitReview.path")) {
                stateManager.invalidateVersionCheck();
                void refresh();
            }
        })
    );

    function resolveTargets(): void {
        // Como la CLI: un solo cwd. Nunca allTargets[0] a ciegas cuando hay
        // varios repos (finish/abort en el repo equivocado).
        const fromGit = gitApi ? listRepositoryTargets(gitApi) : [];
        if (fromGit.length > 0) {
            allTargets = fromGit;
        } else {
            // Git API ausente o aún sin repos: fallback a carpetas del workspace
            // solo si hay exactamente una (ventana single-folder). Con multi-folder
            // y API aún no lista, no inventamos root — se re-resuelve al activar.
            const folders = workspaceFolderTargets();
            allTargets = folders.length === 1 ? folders : [];
        }
        target = pickSoleTarget(allTargets);
    }

    // Señal de refresco: la API de git si está, el watcher de `.git` si no
    // (research.md Decisión 7). Se guarda para poder cambiar de una a la otra:
    // `vscode.git` se activa de forma asíncrona, así que el arranque puede
    // encontrarla ausente y tenerla un instante después.
    let gitWatcher: vscode.Disposable | undefined;

    function watchWithGitApi(api: GitApi): void {
        gitWatcher?.dispose();
        gitWatcher = watchGitApiChanges(api, () => {
            resolveTargets();
            void refresh();
        });
    }

    gitApi = peekGitApi();
    resolveTargets();
    if (gitApi) {
        watchWithGitApi(gitApi);
    } else {
        if (target) {
            gitWatcher = watchGitDirFallback(target.rootUri, () => void refresh());
        }
        // La extensión git no había terminado de activarse: se la espera y, si
        // llega, se pasa a su señal de cambio y se re-resuelven los targets con
        // los repos que ella conoce.
        void ensureGitApi().then((api) => {
            if (!api || gitApi) {
                return;
            }
            gitApi = api;
            watchWithGitApi(api);
            resolveTargets();
            void refresh();
        });
    }
    context.subscriptions.push({dispose: () => gitWatcher?.dispose()});

    context.subscriptions.push(
        // `retainContextWhenHidden`: el panel es un formulario chico de una sola
        // entrada, así que mantenerlo vivo cuesta nada y evita reconstruirlo
        // entero cada vez que el revisor cambia de vista en la barra lateral —
        // que es lo normal mientras se lee un PR.
        vscode.window.registerWebviewViewProvider(WalkthroughViewProvider.viewId, panelProvider, {
            webviewOptions: {retainContextWhenHidden: true},
        }),
        vscode.workspace.registerTextDocumentContentProvider(WHY_SCHEME, whyProvider),

        vscode.commands.registerCommand("gitReview.openEntry", async (arg?: unknown) => {
            const state = stateManager.state;
            const entry = resolveArgEntry(arg);
            if (!target || !entry || !isReviewReadable(state.situation) || !state.state) {
                return;
            }
            rememberOpened(state, entry);
            await openEntry(target.rootUri, state.state.mode, entry);
        }),

        vscode.commands.registerCommand("gitReview.openChange", async (arg?: unknown) => {
            const state = stateManager.state;
            const entry = resolveArgEntry(arg);
            if (!target || !entry || !isReviewReadable(state.situation) || !state.state) {
                return;
            }
            rememberOpened(state, entry);
            await openChange(target.rootUri, state.state.mode, entry);
        }),

        // Sin entrada y sin índice: la unidad acá es el rango, no una fila. Por
        // eso tampoco marca nada — abrir todo no es haber llegado a ninguna
        // parte de la lista. En la práctica finish-conflict nunca coincide con
        // whole (el conflicto sólo ocurre en el replay de --step), así que
        // aceptarlo acá es simetría con el resto de los comandos de lectura,
        // no un caso que vaya a dispararse.
        vscode.commands.registerCommand("gitReview.openAllChanges", async () => {
            const state = stateManager.state;
            const review = state.state;
            if (!target || !isReviewReadable(state.situation) || !review || review.mode !== "whole") {
                return;
            }
            await openRangeChanges(target.rootUri, review.source);
        }),

        vscode.commands.registerCommand("gitReview.showWhy", async (arg?: unknown) => {
            const entry = resolveArgEntry(arg);
            if (!entry || !isPathRef(entry.id)) {
                return;
            }
            const uri = whyUri(entry.id.display, entry.id.raw);
            await vscode.commands.executeCommand("markdown.showPreview", uri);
        }),

        vscode.commands.registerCommand("gitReview.goToEntry", async () => {
            const state = stateManager.state;
            if (!target || !isReviewReadable(state.situation) || !state.state || state.entries.length === 0) {
                return;
            }
            const entry = await pickEntry(state.entries, state.state.mode, state.state.position, state.subjects);
            if (entry) {
                await openEntry(target.rootUri, state.state.mode, entry);
            }
        }),

        vscode.commands.registerCommand("gitReview.next", () => navigate("next", lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.prev", () => navigate("prev", lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.refresh", () => refresh()),
        vscode.commands.registerCommand("gitReview.continueReview", (index?: unknown) =>
            continueReview(index, lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.startReview", () =>
            startReview(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.setBase", () =>
            setBase(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.setRemote", () =>
            setRemote(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.abortReview", () =>
            abortReview(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.finishReview", () =>
            finishReview(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.saveReview", () =>
            saveReview(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.undoFinish", () =>
            undoFinish(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.resumeFinish", () =>
            resumeFinish(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.discardInventory", (index?: unknown) =>
            discardInventoryReview(index, lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.cleanReview", (target?: unknown) =>
            cleanReview(lock, stateManager, getInvokeOptions, target)),
        vscode.commands.registerCommand("gitReview.forgetReview", () =>
            forgetReview(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.previewEdits", () =>
            previewEdits(stateManager, getInvokeOptions, false)),
        vscode.commands.registerCommand("gitReview.previewEditsStat", () =>
            previewEdits(stateManager, getInvokeOptions, true)),
        vscode.commands.registerCommand("gitReview.compareReview", () =>
            compareReview(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.walkthroughInit", () =>
            walkthroughInit(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.walkthroughBuild", () =>
            walkthroughBuild(lock, stateManager, getInvokeOptions)),
        vscode.commands.registerCommand("gitReview.installCli", () => installOrUpdateCli()),
        vscode.commands.registerCommand("gitReview.showOutOfRangeHelp", () => showOutOfRangeHelp(stateManager.state.stderr)),
        // Diagnóstico: abre el canal Output "Git Review CLI" (nunca se abre solo).
        vscode.commands.registerCommand("gitReview.showCliLog", () => showCliLog())
    );

    updateContextKeys(stateManager.state);
    void refresh();

    return {
        refresh,
        getState: () => stateManager.state,
        getPanelModel: async () => {
            await whyPending;
            return buildModel();
        },
        invalidateVersionCheck: () => stateManager.invalidateVersionCheck(),
    };
}

export function deactivate(): void {
    // El timer de sondeo de CLI se limpia vía context.subscriptions al
    // desactivar. No hay más estado en memoria que merezca cierre: la marca
    // de `LAST_OPENED_KEY` vive en el `workspaceState` del host.
}
