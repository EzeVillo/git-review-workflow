import * as vscode from "vscode";
import {CandidateBranch, parseConfigPorcelain} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
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
 */
async function confirmIntent(intent: ReviewIntent, args: string[]): Promise<boolean> {
    const branch = intent.branch ?? "the current branch";
    const answer = await vscode.window.showWarningMessage(
        `Start reviewing ${branch}, ${layoutSummary(intent.layout)}?`,
        {modal: true, detail: `git review start ${args.join(" ")}`},
        "Start the review"
    );
    return answer === "Start the review";
}

/**
 * Escape a terminal (research.md Decisión 5): manda el comando **exacto** que
 * se intentó a una terminal integrada, donde sí hay quién conteste un pedido
 * de credenciales interactivo — algo que la invocación capturada, sin TTY,
 * nunca puede ofrecer.
 */
function runInTerminal(args: string[], cwd: string): void {
    const terminal = vscode.window.createTerminal({name: "git review start", cwd});
    terminal.show();
    terminal.sendText(["git", "review", "start", ...args].map(quoteForTerminal).join(" "));
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
        await setBase(lock, stateManager, getInvokeOptions);
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

    // Capturado justo antes de la confirmación, revalidado justo después
    // (FR-038): si el repositorio cambió mientras el revisor elegía, la
    // premisa con la que arrancó el asistente ya no vale.
    const token = captureToken(stateManager.state);
    if (!(await confirmIntent(intent, args))) {
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
                    runInTerminal(args, options.cwd);
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
