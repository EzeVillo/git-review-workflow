import * as path from "node:path";
import * as vscode from "vscode";
import {
    CandidateBranch,
    deltaForSource,
    DeltaRecord,
    parseConfigPorcelain,
    ReadingOffer,
} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions, resolveCommand} from "../cli/invoke";
import {
    advanceDraftFlow,
    DraftFlowEvent,
    DraftFlowState,
    draftWaitMessage,
    gitdirFromLink,
    initialDraftFlowState,
} from "../review/draftFlow";
import {MutationLock} from "../review/mutationLock";
import {buildLayoutItems, DraftStep, layoutSummary, offerConfigFlags,} from "../review/layoutOffers";
import {
    draftArgs,
    intentToArgs,
    ReviewIntent,
    ReviewLayout,
    ReviewRange,
    ReviewSource,
    validateIntent,
} from "../review/reviewIntent";
import {resolveDefaultSource} from "../review/sourcePreference";
import {captureToken, tokenStillValid} from "../review/staleGuard";
import {classifyStartFailure, quoteForTerminal} from "../review/startFailure";
import {ReviewStateManager} from "../review/state";
import {setBase} from "./setBase";

/** El stderr de la CLI, aplanado a una línea para el toast del editor (mismo criterio que continueReview.ts). */
function flatten(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

interface BranchItem extends vscode.QuickPickItem {
    candidate: CandidateBranch;
}

interface LayoutItem extends vscode.QuickPickItem {
    layout: ReviewLayout;
    /** Presente sólo en las ofertas `draft` / `draft-resume` (011). */
    draft?: DraftStep;
}

interface SourceItem extends vscode.QuickPickItem {
    source: ReviewSource;
}

interface RangeItem extends vscode.QuickPickItem {
    range: ReviewRange;
}

/**
 * Origen (FR-014): remoto / local / offline. Las dos últimas se explican
 * en la descripción porque deciden red y resolución de la base.
 */
const SOURCE_ITEMS: SourceItem[] = [
    {
        label: "Remote",
        description: "fetch and review the remote tip of the branch",
        source: "remote",
    },
    {
        label: "Local",
        description: "review the local branch without fetching; base may still use the remote",
        source: "local",
    },
    {
        label: "Offline",
        description: "review the local branch with no network; base is resolved locally",
        source: "offline",
    },
];

const RANGE_ITEMS: RangeItem[] = [
    {
        label: "Full range",
        description: "everything since the base branch",
        range: "full",
    },
    {
        label: "Only what is new",
        description: "commits since your last review of this branch (--delta)",
        range: "delta",
    },
];

function branchLabel(candidate: CandidateBranch): string {
    return candidate.current ? `${candidate.name}  (current)` : candidate.name;
}

/**
 * Lee `gitReview.defaultSource` con la precedencia user/workspace que ya
 * resuelve el host (research.md Decisión 11). Sólo preselección — nunca
 * decide sola el argv (FR-016a / T074).
 */
function readDefaultSource(): ReviewSource {
    const inspected = vscode.workspace.getConfiguration("gitReview").inspect<string>("defaultSource");
    return resolveDefaultSource({
        workspaceValue: inspected?.workspaceValue,
        globalValue: inspected?.globalValue,
    });
}

/**
 * Paso 1 — rama a revisar. La actual va primera (research.md Decisión 9,
 * FR-011); `showQuickPick` filtra incrementalmente por su cuenta, así que un
 * repositorio con cientos de ramas sigue siendo navegable sin nada extra acá.
 */
async function pickBranch(candidates: CandidateBranch[]): Promise<CandidateBranch | undefined> {
    const items: BranchItem[] = [...candidates]
        .sort((a, b) => (a.current === b.current ? 0 : a.current ? -1 : 1))
        .map((candidate) => ({label: branchLabel(candidate), candidate}));
    const picked = await vscode.window.showQuickPick(items, {
        title: "Start a review — branch",
        placeHolder: "Branch to review",
    });
    return picked?.candidate;
}

/**
 * Paso 4 — cómo leerla (008): ítems dinámicos desde `offer` de la CLI.
 * Sin Automatic; solo lo viable para tip+rango (o fallback whole+step).
 *
 * 011: entre los ítems puede venir el de armarse el orden de lectura. Devuelve
 * el ítem entero y no sólo el layout porque esa distinción —leer ya, o escribir
 * primero lo que se va a leer— es la que decide el camino siguiente.
 */
async function pickLayout(offers: readonly ReadingOffer[] | undefined): Promise<LayoutItem | undefined> {
    const items: LayoutItem[] = buildLayoutItems(offers).map((item) => {
        const entry: LayoutItem = {
            label: item.label,
            description: item.description,
            layout: item.layout,
        };
        if (item.draft !== undefined) {
            entry.draft = item.draft;
        }
        return entry;
    });
    return vscode.window.showQuickPick(items, {
        title: "Start a review — how to read it",
        placeHolder: "Walkthrough, commit by commit, keys only, or whole diff",
    });
}

/**
 * Recorrido completo vs sólo esenciales, tras validar un borrador que marcó
 * entradas con `key`. Sólo se pregunta cuando la CLI volvió a ofrecer `keys`
 * (FR-019): sin entradas esenciales no hay dos recorridos que elegir.
 */
async function pickDraftKeys(): Promise<boolean | undefined> {
    const picked = await vscode.window.showQuickPick(
        [
            {label: "Walkthrough", description: "the whole reading order you wrote", keysOnly: false},
            {label: "Walkthrough — keys only", description: "only the entries you marked key", keysOnly: true},
        ],
        {
            title: "Start a review — how to read it",
            placeHolder: "Your draft marks key entries: read all of them, or only those",
        }
    );
    return picked?.keysOnly;
}

/**
 * Origen: el ítem de `defaultSource` va primero para preseleccionarlo (el
 * QuickPick activa el primer ítem al abrir). El valor que llega a la CLI es
 * el que el usuario confirma acá o en el modal final, no el ajuste solo
 * (FR-016 / FR-016a).
 */
async function pickSource(defaultSource: ReviewSource): Promise<ReviewSource | undefined> {
    const preferred = SOURCE_ITEMS.find((item) => item.source === defaultSource) ?? SOURCE_ITEMS[0];
    const rest = SOURCE_ITEMS.filter((item) => item.source !== preferred.source);
    const items = [preferred, ...rest];
    const picked = await vscode.window.showQuickPick(items, {
        title: "Start a review — origin",
        placeHolder: "Remote, local, or offline",
    });
    return picked?.source;
}

/**
 * Rango incremental: sólo se llama cuando hay un `delta` del origin que
 * corresponde al source elegido (FR-015). Sin ese registro este paso no se
 * ofrece.
 */
async function pickRange(): Promise<ReviewRange | undefined> {
    const picked = await vscode.window.showQuickPick(RANGE_ITEMS, {
        title: "Start a review — range",
        placeHolder: "Full range, or only what is new since the last review",
    });
    return picked?.range;
}

/**
 * Deltas + ofertas para la rama en el contexto source/range (008).
 * Misma invocación: `config --porcelain [--local|--offline] [--delta] -- <branch>`.
 * Siempre `network: false` (el tip remoto es el tracking ref local).
 */
async function loadBranchContext(
    branch: CandidateBranch,
    source: ReviewSource,
    range: ReviewRange,
    options: InvokeOptions
): Promise<{
    deltas: DeltaRecord[] | undefined;
    offers: ReadingOffer[] | undefined;
    error?: string
}> {
    const flags = offerConfigFlags(source, range);
    const report = await invokeGitReview(
        "config",
        ["--porcelain", ...flags, "--", branch.name],
        {...options, network: false}
    );
    if (report.errorCode || report.exitCode !== 0) {
        const text = flatten(report.stderr);
        return {
            deltas: undefined,
            offers: undefined,
            error: text.length > 0 ? text : "Could not read reading options for this branch.",
        };
    }
    const parsed = parseConfigPorcelain(report.stdout);
    return {deltas: parsed.deltas, offers: parsed.offers};
}

/**
 * Abre el borrador en el editor. La ruta se arma, no se lee de la salida de la
 * CLI (que la imprime para el humano, no para parsearla): el borrador vive en
 * `<gitdir>/review-walkthrough/<branch>.md`, y `<gitdir>` es `<root>/.git`
 * salvo en worktrees y submódulos, donde `.git` es un archivo que apunta al de
 * verdad.
 *
 * Abrirlo es mostrarlo, no leerlo: la extensión no interpreta un byte de su
 * contenido, igual que ya hace con `.review/walkthrough.md` tras un
 * `walkthrough init`.
 */
async function openDraft(cwd: string, branch: string): Promise<{opened: boolean; file?: string}> {
    if (!cwd) {
        return {opened: false};
    }
    let file: string | undefined;
    try {
        const dotGit = vscode.Uri.file(path.join(cwd, ".git"));
        const stat = await vscode.workspace.fs.stat(dotGit);
        let gitdir = dotGit.fsPath;
        if (stat.type !== vscode.FileType.Directory) {
            const raw = await vscode.workspace.fs.readFile(dotGit);
            const target = gitdirFromLink(Buffer.from(raw).toString("utf8"));
            if (target === undefined) {
                return {opened: false};
            }
            gitdir = path.isAbsolute(target) ? target : path.join(cwd, target);
        }
        file = path.join(gitdir, "review-walkthrough", `${branch}.md`);
        const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(file));
        await vscode.window.showTextDocument(doc, {preview: false});
        return {opened: true, file};
    } catch {
        // No se pudo abrir: el bucle sigue igual — un borrador que existe y no se
        // mostró es menos malo que un asistente que se corta por no poder
        // mostrarlo. Pero el aviso que sigue pide llenarlo, así que la ruta se
        // devuelve para que la diga: la CLI la imprime por **stdout** y acá sólo
        // se muestra stderr, de modo que sin esto el revisor no tiene por dónde
        // encontrar el archivo.
        return {opened: false, file};
    }
}

/** Una invocación de `walkthrough draft`, con su progreso y bajo el lock. */
async function invokeDraft(
    lock: MutationLock,
    branch: string,
    source: ReviewSource,
    range: ReviewRange,
    build: boolean,
    options: InvokeOptions
): Promise<{ok: boolean; text: string}> {
    const result = await lock.run(async () =>
        vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: build ? `Validating your draft for ${branch}…` : `Drafting a walkthrough for ${branch}…`,
            },
            async () =>
                invokeGitReview("walkthrough", draftArgs(branch, source, range, build), {
                    ...options,
                    network: false,
                })
        )
    );
    const text = flatten(result?.stderr ?? "");
    return {ok: result !== undefined && !result.errorCode && result.exitCode === 0, text};
}

/**
 * El bucle del borrador (011, contracts/client-draft-flow.md). Las decisiones
 * viven en `draftFlow`; acá sólo está el vehículo de cada paso.
 *
 * El aviso de espera es una notificación **con acciones** y nunca un modal: el
 * revisor tiene que poder editar el borrador mientras está a la vista, que es
 * literalmente lo que se le está pidiendo que haga.
 */
async function runDraftFlow(
    step: DraftStep,
    branch: CandidateBranch,
    source: ReviewSource,
    range: ReviewRange,
    lock: MutationLock,
    options: InvokeOptions
): Promise<{kind: "done"; layout: ReviewLayout} | {kind: "back"; error?: string}> {
    let state: DraftFlowState = initialDraftFlowState(step);
    // Sólo definido mientras el borrador NO esté a la vista: es lo que hace que
    // el aviso diga dónde quedó el archivo en vez de pedir que se llene algo
    // invisible. Se recalcula en cada paso `open`.
    let unopened: {file?: string} | undefined;

    for (;;) {
        switch (state.kind) {
            case "create": {
                const outcome = await invokeDraft(lock, branch.name, source, range, false, options);
                if (outcome.ok && outcome.text.length > 0) {
                    // Nota de un verbo exitoso (el borrador tapa el walkthrough
                    // del autor): se muestra, como las de start.
                    void vscode.window.showInformationMessage(outcome.text);
                }
                state = advanceDraftFlow(state, {
                    kind: "created",
                    ok: outcome.ok,
                    error: outcome.ok
                        ? undefined
                        : outcome.text.length > 0
                            ? outcome.text
                            : "git review walkthrough draft failed.",
                });
                break;
            }

            case "open": {
                const shown = await openDraft(options.cwd, branch.name);
                unopened = shown.opened ? undefined : {file: shown.file};
                state = advanceDraftFlow(state, {kind: "opened"});
                break;
            }

            case "wait": {
                const message = draftWaitMessage(branch.name, state.error, unopened);
                const answer =
                    state.error !== undefined
                        ? await vscode.window.showWarningMessage(message, "Continue", "Cancel")
                        : await vscode.window.showInformationMessage(message, "Continue", "Cancel");
                // `undefined` es la notificación descartada, no Cancel: se cierra
                // sola con la X o con "clear all notifications", que es fácil de
                // hacer sin querer mientras se edita el borrador — justo lo que
                // el aviso pide hacer. Se vuelve a mostrar; sólo Cancel sale.
                let event: DraftFlowEvent = {kind: "dismiss"};
                if (answer === "Continue") {
                    event = {kind: "continue"};
                } else if (answer === "Cancel") {
                    event = {kind: "cancel"};
                }
                state = advanceDraftFlow(state, event);
                break;
            }

            case "build": {
                const outcome = await invokeDraft(lock, branch.name, source, range, true, options);
                state = advanceDraftFlow(state, {
                    kind: "built",
                    ok: outcome.ok,
                    error: outcome.ok
                        ? undefined
                        : outcome.text.length > 0
                            ? outcome.text
                            : "git review walkthrough draft --build failed.",
                });
                break;
            }

            case "reload": {
                // El borrador ya es legible: lo que se relee es si marcó
                // entradas esenciales, y eso sólo lo sabe la CLI.
                const ctx = await loadBranchContext(branch, source, range, options);
                state = advanceDraftFlow(state, {kind: "offers", offers: ctx.offers});
                break;
            }

            case "pickKeys": {
                const keysOnly = await pickDraftKeys();
                state = advanceDraftFlow(state, {kind: "keysPicked", keysOnly});
                break;
            }

            case "done":
                return {kind: "done", layout: state.layout};

            case "back":
                return state.error !== undefined ? {kind: "back", error: state.error} : {kind: "back"};
        }
    }
}

/**
 * Confirmación con la frase resumen (FR-017 / FR-011), en el mismo molde que
 * `continueReview.ts`. Nombra la forma real (walk / keys / step / whole), no
 * “automatically…”.
 */
async function confirmIntent(intent: ReviewIntent, args: string[], base: string | undefined): Promise<boolean> {
    const branch = intent.branch ?? "the current branch";
    const detailLines = [`git review start ${args.join(" ")}`];
    if (base !== undefined) {
        detailLines.push(`Comparing against ${base}.`);
    }
    const answer = await vscode.window.showWarningMessage(
        `Start reviewing ${branch}, ${layoutSummary(intent.layout)}?`,
        {modal: true, detail: detailLines.join("\n")},
        "Start the review"
    );
    return answer === "Start the review";
}

/**
 * Escape a terminal (research.md Decisión 5): manda el comando **exacto** que
 * se intentó a una terminal integrada, donde sí hay quién conteste un pedido
 * de credenciales interactivo — algo que la invocación capturada, sin TTY,
 * nunca puede ofrecer. "Exacto" incluye respetar `gitReview.path`: reusa
 * `resolveCommand`, el mismo punto que `invokeGitReview` usa para decidir qué
 * ejecutable corre, en vez de hardcodear `git review start` — con ese ajuste
 * seteado (el caso que la Decisión 5 existe para cubrir) `git review` no
 * necesariamente existe como subcomando de git (I1, revisión Fase 3).
 */
function runInTerminal(args: string[], options: InvokeOptions): void {
    const {command, args: commandArgs} = resolveCommand("start", args, options.gitReviewPath);
    const terminal = vscode.window.createTerminal({name: "git review start", cwd: options.cwd});
    terminal.show();
    terminal.sendText([command, ...commandArgs].map((arg) => quoteForTerminal(arg)).join(" "));
}

/**
 * `gitReview.startReview`: asistente de inicio (005 + 008).
 * Orden (008): rama → origen → rango (si hay delta) → forma de lectura
 * (desde `offer`) → confirmación → start con network: true.
 */
export async function startReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    // finish-pending is still an empty working branch: a leftover finish of
    // another source must not block starting a different review (CLI start only
    // refuses when review/<that-source> already exists).
    const situation = stateManager.state.situation;
    if (situation !== "no-review" && situation !== "finish-pending") {
        return;
    }

    const options = getInvokeOptions();
    const report = await invokeGitReview("config", ["--porcelain"], {...options, network: false});
    if (report.errorCode || report.exitCode !== 0) {
        // Un fallo acá deja el asistente sin abrirse, con el stderr a la vista
        // (contracts/cli-invocation.md § config --porcelain): no se abre "con
        // lo que había" en el estado cacheado del panel.
        const text = flatten(report.stderr);
        void vscode.window.showErrorMessage(text.length > 0 ? text : "Could not read the review configuration.");
        return;
    }
    const parsed = parseConfigPorcelain(report.stdout);

    if (parsed.config.base === undefined) {
        await setBase(lock, stateManager, getInvokeOptions, parsed.candidates);
        if (stateManager.state.config?.base === undefined) {
            // Cancelado, o el propio config falló (ya mostró su error): sin
            // base no hay como seguir, y el asistente no insiste dos veces —
            // el revisor lo vuelve a abrir cuando quiera reintentar.
            return;
        }
    }

    const branch = await pickBranch(parsed.candidates);
    if (!branch) {
        return;
    }

    // Origen siempre visible (FR-016): defaultSource sólo preselecciona.
    // 008: origen y rango ANTES de la forma de lectura (ofertas dependen del tip).
    const defaultSource = readDefaultSource();
    const source = await pickSource(defaultSource);
    if (!source) {
        return;
    }

    // Primera lectura por rama: deltas de ambos orígenes (sin flags de
    // origen) para decidir si hay paso de rango. Las ofertas se piden después
    // con el contexto completo (source + range).
    const deltaProbe = await invokeGitReview(
        "config",
        ["--porcelain", "--", branch.name],
        {...options, network: false}
    );
    let deltas: DeltaRecord[] | undefined;
    if (!deltaProbe.errorCode && deltaProbe.exitCode === 0) {
        deltas = parseConfigPorcelain(deltaProbe.stdout).deltas;
    }

    const delta = deltaForSource(deltas, source);
    let range: ReviewRange = "full";
    if (delta !== undefined) {
        const pickedRange = await pickRange();
        if (!pickedRange) {
            return;
        }
        range = pickedRange;
    }

    const ctx = await loadBranchContext(branch, source, range, options);
    if (ctx.error !== undefined) {
        void vscode.window.showErrorMessage(ctx.error);
        return;
    }
    // Prefer deltas from the contextual call when present (same markers).
    if (ctx.deltas !== undefined) {
        deltas = ctx.deltas;
    }

    // Forma de lectura. El paso se repite —y sólo por eso es un bucle— cuando
    // el revisor entra al armado del borrador y vuelve: sale de ahí con el
    // borrador intacto y la oferta convertida en `draft-resume`, así que lo
    // honesto es devolverlo a este mismo paso con las ofertas al día (FR-018a).
    let offers = ctx.offers;
    let layout: ReviewLayout;
    for (;;) {
        const picked = await pickLayout(offers);
        if (!picked) {
            return;
        }
        if (picked.draft === undefined) {
            layout = picked.layout;
            break;
        }

        const outcome = await runDraftFlow(picked.draft, branch, source, range, lock, options);
        if (outcome.kind === "done") {
            layout = outcome.layout;
            break;
        }
        if (outcome.error !== undefined) {
            void vscode.window.showErrorMessage(outcome.error);
        }
        const reloaded = await loadBranchContext(branch, source, range, options);
        if (reloaded.error === undefined) {
            offers = reloaded.offers;
        }
    }

    const intent: ReviewIntent = {branch: branch.name, layout, range, source};
    const check = validateIntent(intent, {delta: deltaForSource(deltas, source)});
    if (!check.ok) {
        // Defensa en profundidad: la UI no ofrece delta sin registro del
        // origin del source, pero si algo se desfasó no mandamos un intent
        // ilegal a la CLI.
        void vscode.window.showErrorMessage(check.reason);
        return;
    }

    const args = intentToArgs(intent, branch.name);

    // La base del reporte leído arriba, o — si hacía falta y setBase() la
    // fijó recién — la que quedó tras su refresh: parsed.config.base sigue
    // siendo el valor de ANTES de ese paso, así que no alcanza por sí solo.
    const base = parsed.config.base ?? stateManager.state.config?.base;

    // Capturado justo antes de la confirmación (FR-038). Check externo: UX
    // si el modal ya quedó obsoleto. Check **dentro** del lock (como abort/
    // save/continue): cierra la ventana entre "Start the review" y el spawn
    // (otro proceso arrancó una review, HEAD cambió, watcher refresh).
    const token = captureToken(stateManager.state);
    if (!(await confirmIntent(intent, args, base))) {
        return;
    }
    if (!tokenStillValid(token, stateManager.state)) {
        void vscode.window.showInformationMessage(
            "The repository changed while the wizard was open; nothing was started."
        );
        return;
    }

    await lock.run(async () => {
        let stale = false;
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Starting the review of ${branch.name}…`
            },
            async () => {
                // Re-check situation inside the lock: empty-state tokens only
                // carry situation (no branch/tip), so a concurrent start of
                // another review still invalidates via situation change.
                if (!tokenStillValid(token, stateManager.state)) {
                    stale = true;
                    return undefined;
                }
                const situation = stateManager.state.situation;
                if (situation !== "no-review" && situation !== "finish-pending") {
                    stale = true;
                    return undefined;
                }
                const invocation = await invokeGitReview("start", args, {
                    ...options,
                    network: true
                });
                // Refrescar pase lo que pase: aunque start falle, es lo que dice
                // dónde quedó el repositorio — la salida humana no se parsea
                // nunca (FR-015/FR-024).
                await stateManager.refresh();
                return invocation;
            }
        );

        if (stale) {
            void vscode.window.showInformationMessage(
                "The repository changed before the start ran; nothing was started."
            );
            return;
        }

        if (!result || result.exitCode !== 0) {
            const text = flatten(result?.stderr ?? "");
            if (result && classifyStartFailure(result.stderr) === "network") {
                const action = await vscode.window.showErrorMessage(
                    text.length > 0 ? text : "git review start failed.",
                    "Run in Terminal"
                );
                if (action === "Run in Terminal") {
                    runInTerminal(args, options);
                }
            } else {
                // Mismo fallback que el camino de red: exit ≠ 0 sin stderr
                // (CLI matada / rota) no debe ser un fallo silencioso.
                void vscode.window.showErrorMessage(
                    text.length > 0 ? text : "git review start failed."
                );
            }
            return;
        }

        // start emite notas a stderr en invocaciones EXITOSAS (rama local
        // desactualizada, review previa con commits nuevos): se muestran
        // aunque el exit sea 0 (FR-031) — descartarlas sería tirar
        // información que la CLI decidió dar.
        const note = flatten(result.stderr);
        if (note.length > 0) {
            void vscode.window.showInformationMessage(note);
        }
    });
}
