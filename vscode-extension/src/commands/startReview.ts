import * as vscode from "vscode";
import {CandidateBranch, parseConfigPorcelain} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions, resolveCommand} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {intentToArgs, ReviewIntent, ReviewLayout} from "../review/reviewIntent";
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
}

const LAYOUT_ITEMS: LayoutItem[] = [
    {label: "Automatic", description: "follow the PR's walkthrough, if it has one", layout: "auto"},
    {label: "Commit by commit", description: "review one commit at a time (--step)", layout: "step"},
    {label: "Ignore the walkthrough", description: "review the whole diff at once (--no-walk)", layout: "no-walk"},
];

function branchLabel(candidate: CandidateBranch): string {
    return candidate.current ? `${candidate.name}  (current)` : candidate.name;
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
        title: "Start a review — branch (step 1 of 3)",
        placeHolder: "Branch to review",
    });
    return picked?.candidate;
}

/** Paso 2 — cómo leerla: automático, commit por commit, o ignorar el walkthrough. */
async function pickLayout(): Promise<ReviewLayout | undefined> {
    const picked = await vscode.window.showQuickPick(LAYOUT_ITEMS, {
        title: "Start a review — how to read it (step 2 of 3)",
        placeHolder: "Automatic, commit by commit, or the whole diff at once",
    });
    return picked?.layout;
}

function layoutSummary(layout: ReviewLayout): string {
    switch (layout) {
        case "step":
            return "commit by commit";
        case "no-walk":
            return "as the whole diff, ignoring any walkthrough";
        default:
            return "automatically (following a walkthrough if the PR has one)";
    }
}

/**
 * Paso 3 — confirmación con la frase resumen (FR-017), en el mismo molde que
 * `continueReview.ts` usa para retomar una review pausada (research.md § "el
 * molde que 002 fijó"): `start` cambia de rama y mueve HEAD, así que cae bajo
 * FR-029 igual que esa acción.
 *
 * El `detail` nombra la base cuando hay una (US1 escenario 6 / FR-010: el
 * revisor tiene que ver contra qué se va a comparar antes de confirmar, sin
 * ir a buscarlo a un archivo de configuración). Sin base no hay línea que
 * agregar — un review completo fallaría pidiéndola, y eso ya lo resolvió el
 * paso anterior de este mismo asistente.
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
    terminal.sendText([command, ...commandArgs].map(quoteForTerminal).join(" "));
}

/**
 * `gitReview.startReview`: el asistente de inicio (T024, research.md Decisión
 * 9). Lee `config --porcelain` con `network: false` (research.md Decisión 5 —
 * la única invocación que toca la red es `start`), antepone T025 si falta la
 * base, recorre los tres pasos del `QuickPick` y, confirmado, invoca `start`
 * con `network: true` bajo el `MutationLock` compartido — mismo molde que
 * `continueReview.ts`: progreso no cancelable, refresco pase lo que pase,
 * stderr de advertencias mostrado aunque el exit sea 0 (FR-031).
 */
export async function startReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    if (stateManager.state.situation !== "no-review") {
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

    const layout = await pickLayout();
    if (!layout) {
        return;
    }

    const intent: ReviewIntent = {branch: branch.name, layout, range: "full", source: "remote"};
    const args = intentToArgs(intent, branch.name);

    // La base del reporte leído arriba, o — si hacía falta y setBase() la
    // fijó recién — la que quedó tras su refresh: parsed.config.base sigue
    // siendo el valor de ANTES de ese paso, así que no alcanza por sí solo.
    const base = parsed.config.base ?? stateManager.state.config?.base;

    // Capturado justo antes de la confirmación, revalidado justo después
    // (FR-038): si el repositorio cambió mientras el revisor elegía, la
    // premisa con la que arrancó el asistente ya no vale.
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
        const result = await vscode.window.withProgress(
            {location: vscode.ProgressLocation.Notification, title: `Starting the review of ${branch.name}…`},
            async () => {
                const invocation = await invokeGitReview("start", args, {...options, network: true});
                // Refrescar pase lo que pase: aunque start falle, es lo que dice
                // dónde quedó el repositorio — la salida humana no se parsea
                // nunca (FR-015/FR-024).
                await stateManager.refresh();
                return invocation;
            }
        );

        if (result.exitCode !== 0) {
            const text = flatten(result.stderr);
            if (classifyStartFailure(result.stderr) === "network") {
                const action = await vscode.window.showErrorMessage(
                    text.length > 0 ? text : "git review start failed.",
                    "Run in Terminal"
                );
                if (action === "Run in Terminal") {
                    runInTerminal(args, options);
                }
            } else if (text.length > 0) {
                void vscode.window.showErrorMessage(text);
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
