import * as vscode from "vscode";
import {
    branchPickerItems,
    CandidateBranch,
    deltaForSource,
    DeltaRecord,
    DraftRecord,
    parseConfigPorcelain,
    ReadingOffer,
} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions, resolveCommand} from "../cli/invoke";
import {
    advanceDraftFlow,
    DraftFlowState,
    DraftStep,
    initialDraftFlowState,
    parseMergedRecord,
} from "../review/draftFlow";
import {MutationLock} from "../review/mutationLock";
import {
    buildLayoutItems,
    offerConfigFlags,
} from "../review/layoutOffers";
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
import {STALE, draftUpdated, startLayoutTitle} from "../review/userCopy";

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
        description: "commits since your last review of this branch",
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
    const items: BranchItem[] = branchPickerItems(candidates)
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
async function pickLayout(
    offers: readonly ReadingOffer[] | undefined,
    branch: string
): Promise<LayoutItem | undefined> {
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
        // El ÚLTIMO paso, y por eso nombra la rama: elegir acá ya arranca la
        // review — la pantalla de confirmación que seguía a este paso repetía
        // las cuatro respuestas del asistente y agregaba el comando.
        title: startLayoutTitle(branch),
        placeHolder: "Walkthrough, commit by commit, keys only, or whole diff",
    });
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
    /** Los del namespace activo, para saber en qué estado está el de esta rama. */
    drafts: DraftRecord[] | undefined;
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
            drafts: undefined,
            error: text.length > 0 ? text : "Could not read reading options for this branch.",
        };
    }
    const parsed = parseConfigPorcelain(report.stdout);
    return {deltas: parsed.deltas, offers: parsed.offers, drafts: parsed.drafts};
}

/**
 * La creación del borrador, con su progreso y bajo el lock. Sólo la creación:
 * validarlo es cosa del panel desde 012, con los flags que la CLI grabó en el
 * archivo y devuelve por el registro `draft`.
 */
async function invokeDraft(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    branch: string,
    source: ReviewSource,
    range: ReviewRange,
    options: InvokeOptions,
    force: boolean,
    update: boolean
): Promise<{ ok: boolean; text: string }> {
    const result = await lock.run(async () =>
        vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Drafting a walkthrough for ${branch}…`,
            },
            async () => {
                const invocation = await invokeGitReview(
                    "walkthrough",
                    draftArgs(branch, source, range, false, force),
                    {...options, network: false}
                );
                // Refrescar acá, y pase lo que pase, por lo mismo que start:
                // es lo que dice dónde quedó el repositorio. Y hace falta más
                // que en start, porque ninguna otra señal ve esta mutación —
                // el borrador se escribe en el gitdir, así que no mueve HEAD,
                // no toca el índice y no escribe config, y el watcher de
                // borradores sólo mira directorios que la CLI YA reportó: el
                // primero de una rama estrena su carpeta, de modo que sin
                // esto la fila no aparecía hasta que algo ajeno refrescara.
                await stateManager.refresh();
                return invocation;
            }
        )
    );
    const ok = result !== undefined && !result.errorCode && result.exitCode === 0;
    // En rojo, sólo el error: es lo que la CLI pone en stderr y lo único que
    // hay que decir.
    if (!ok) {
        return {ok, text: flatten(result?.stderr ?? "")};
    }
    // En verde el acuse depende del paso, y un `create` NO TIENE NINGUNO: el
    // refresco de arriba acaba de dibujar la fila del borrador, y todo lo que
    // el verbo dice ahí tiene su propia fila en el panel — el archivo y el
    // comando siguiente (la fila y su botón *Validate and start*), el
    // walkthrough del autor al que tapa (su fila, con su badge) y la guía de
    // autoría que falta (las dos filas de guías, con su Create). Notificarlo
    // era repetir el panel entero en un párrafo.
    //
    // Un `update` sí: qué se conservó, qué entró y qué se cayó no está en
    // ninguna fila, porque la del borrador muestra el par NUEVO. Los tres
    // números llegan por el registro `merged` y la frase es nuestra; sin
    // registro (una CLI vieja) el acuse se cae entero, que es mejor que
    // reenviar la prosa que trae la ruta y el comando siguiente.
    if (!update) {
        return {ok, text: ""};
    }
    const merged = parseMergedRecord(result?.stdout ?? "");
    return {
        ok,
        text: merged === undefined ? "" : draftUpdated(merged.kept, merged.added, merged.dropped),
    };
}

/**
 * Lo que queda del camino del borrador dentro del asistente (012,
 * contracts/client-draft-panel.md § 3). Las decisiones viven en `draftFlow`;
 * acá sólo está el vehículo: una invocación, y el asistente termina.
 *
 * No abre el borrador y no deja ningún aviso esperando. La continuación —
 * llenarlo, validarlo, arrancar la review— vive en el bloque de borradores del
 * panel, sobre un estado que sobrevive a cerrar el editor.
 */
async function runDraftFlow(
    step: DraftStep,
    branch: CandidateBranch,
    source: ReviewSource,
    range: ReviewRange,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    options: InvokeOptions
): Promise<{ kind: "done" } | { kind: "back"; error?: string }> {
    let state: DraftFlowState = initialDraftFlowState(step);

    for (; ;) {
        switch (state.kind) {
            case "create": {
                const outcome = await invokeDraft(
                    lock, stateManager, branch.name, source, range, options, state.force, state.update
                );
                // Sólo lo que el panel no dice. Sobre un `update` eso incluye
                // el resultado del verbo —el panel muestra el par nuevo pero no
                // qué se conservó ni qué entró—; sobre un `create`, únicamente
                // las notas: el refresco que acaba de correr ya dibujó la fila
                // del borrador, que es el acuse, y el comando con el que el
                // stdout cierra es el botón de esa misma fila.
                if (outcome.ok && outcome.text.length > 0) {
                    void vscode.window.showInformationMessage(outcome.text);
                }
                state = advanceDraftFlow(state, {
                    kind: "created",
                    ok: outcome.ok,
                    error: outcome.ok
                        ? undefined
                        : outcome.text.length > 0
                            ? outcome.text
                            : "Could not draft a reading order.",
                });
                break;
            }

            case "done":
                return {kind: "done"};

            case "back":
                return state.error !== undefined ? {
                    kind: "back",
                    error: state.error
                } : {kind: "back"};
        }
    }
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
    // borrador intacto y la oferta ya recalculada por la CLI, así que lo honesto
    // es devolverlo a este mismo paso con las ofertas al día (FR-018a).
    let offers = ctx.offers;
    let layout: ReviewLayout;
    for (; ;) {
        const picked = await pickLayout(offers, branch.name);
        if (!picked) {
            return;
        }
        if (picked.draft === undefined) {
            layout = picked.layout;
            break;
        }

        // Sin preguntar nada: cuál de los tres caminos del borrador corresponde
        // ya lo decidió la CLI al elegir qué oferta emitir, que es la única que
        // puede —la pregunta es si el orden sigue cubriendo el rango, y para eso
        // hacen falta los dos tips.
        const outcome = await runDraftFlow(picked.draft, branch, source, range, lock, stateManager, options);
        if (outcome.kind === "done") {
            // El asistente termina acá: no arranca ninguna review y no deja
            // ningún aviso abierto. El refresco que invokeDraft ya hizo dejó la
            // fila del borrador en el panel, con su ruta, y la continuación
            // vive ahí (Open / Validate and start).
            return;
        }
        // Falló la creación: se dice por qué y se vuelve a ESTE paso, sin
        // rehacer la elección de rama, con las ofertas al día.
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

    // Capturado antes del spawn (FR-038). El asistente pudo estar abierto un
    // rato: el check externo evita el progreso cuando el estado ya quedó
    // obsoleto, y el de adentro del lock cierra la ventana entre este punto y
    // el spawn (otro proceso arrancó una review, HEAD cambió, watcher refresh).
    const token = captureToken(stateManager.state);
    if (!tokenStillValid(token, stateManager.state)) {
        void vscode.window.showInformationMessage(
            STALE
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
                STALE
            );
            return;
        }

        if (!result || result.exitCode !== 0) {
            const text = flatten(result?.stderr ?? "");
            if (result && classifyStartFailure(result.stderr) === "network") {
                const action = await vscode.window.showErrorMessage(
                    text.length > 0 ? text : "Could not start the review.",
                    "Run in Terminal"
                );
                if (action === "Run in Terminal") {
                    runInTerminal(args, options);
                }
            } else {
                // Mismo fallback que el camino de red: exit ≠ 0 sin stderr
                // (CLI matada / rota) no debe ser un fallo silencioso.
                void vscode.window.showErrorMessage(
                    text.length > 0 ? text : "Could not start the review."
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
