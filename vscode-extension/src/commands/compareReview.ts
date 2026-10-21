import * as vscode from "vscode";
import {parseConfigPorcelain, CandidateBranch, compareRevisionItems} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {buildLayoutItems, layoutSummary} from "../review/layoutOffers";
import {ReviewStateManager} from "../review/state";
import {confirmMutation} from "../review/confirm";
import {PanelRevealer, revealPanel} from "../views/reveal";
import {parseMergedRecord} from "../review/draftFlow";
import {draftUpdated} from "../review/userCopy";
import {COMPARE_COPY, comparisonSummary, compareTargetPrompt, compareTargetTitle, compareConfirmTitle, comparingProgress} from "../review/userCopy";

/**
 * `gitReview.compareReview`: monta `git review compare <a> <b> [--step|--no-walk|--keys]`
 * con confirmación. Sin layout "auto" / "Automatic".
 */
export async function compareReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions,
    reveal: PanelRevealer
): Promise<void> {
    const candidates = await loadCandidates(stateManager, getInvokeOptions());
    const lower = await pickCommitIsh(candidates, COMPARE_COPY.baseTitle, COMPARE_COPY.basePrompt);
    if (!lower) {
        return;
    }
    const upper = await pickCommitIsh(candidates, compareTargetTitle(lower), compareTargetPrompt(lower));
    if (!upper) {
        return;
    }

    const options = getInvokeOptions();
    const report = await invokeGitReview("config", ["--porcelain", "--compare", "--", lower, upper], {...options, network: false});
    if (report.errorCode || report.exitCode !== 0) {
        void vscode.window.showErrorMessage(report.stderr.trim() || COMPARE_COPY.failed);
        return;
    }
    const items = buildLayoutItems(parseConfigPorcelain(report.stdout).offers).map(item => ({
        ...item,
        description: item.draft === "create" ? COMPARE_COPY.draftDetail
            : item.draft === "update" ? COMPARE_COPY.draftUpdateDetail
            : item.draft ? item.description : COMPARE_COPY[`${item.layout}Detail`],
    }));
    const layoutPick = await vscode.window.showQuickPick(items, {
        title: comparisonSummary(lower, upper),
        placeHolder: COMPARE_COPY.layoutTitle,
    });
    if (!layoutPick) return;
    if (layoutPick.draft) {
        if (layoutPick.draft !== "resume") {
            const result = await lock.run(async () => {
                const invocation = await invokeGitReview("walkthrough", ["draft", "--porcelain", "--compare", "--", lower, upper], {...options, network: false});
                await stateManager.refresh();
                return invocation;
            });
            if (!result) return;
            if (result.errorCode || result.exitCode !== 0) {
                void vscode.window.showErrorMessage(result.stderr.trim() || COMPARE_COPY.failed);
                return;
            }
            if (layoutPick.draft === "update") {
                const merged = parseMergedRecord(result.stdout);
                if (merged) void vscode.window.showInformationMessage(draftUpdated(merged.kept, merged.added, merged.dropped));
            }
        } else {
            await stateManager.refresh();
        }
        revealPanel("compareReview", reveal);
        return;
    }

    const summary = compareConfirmTitle(lower, upper, layoutSummary(layoutPick.layout));
    const confirmed = await confirmMutation(
        "compareReview",
        summary,
        COMPARE_COPY.confirmDetail,
        COMPARE_COPY.button
    );
    if (!confirmed) {
        return;
    }

    const args: string[] = [];
    if (layoutPick.layout === "step") {
        args.push("--step");
    } else if (layoutPick.layout === "whole") {
        args.push("--no-walk");
    } else if (layoutPick.layout === "keys") {
        args.push("--keys");
    }
    // walk: sin flag de layout (la CLI detecta walkthrough en el tip)
    // Separador -- antes de posicionales: commit-ish que empiezan con - no se
    // confunden con flags (misma disciplina que start).
    args.push("--", lower, upper);

    await lock.run(async () => {
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: comparingProgress(lower, upper),
            },
            async () => {
                const invocation = await invokeGitReview("compare", args, getInvokeOptions());
                await stateManager.refresh();
                return invocation;
            }
        );
        if (result && result.exitCode !== 0) {
            const text = result.stderr.trim() || COMPARE_COPY.failed;
            void vscode.window.showErrorMessage(text);
        }
    });
}

async function loadCandidates(
    stateManager: ReviewStateManager,
    options: InvokeOptions
): Promise<CandidateBranch[]> {
    const cached = stateManager.state.candidates;
    if (cached && cached.length > 0) {
        return cached;
    }
    const result = await invokeGitReview("config", ["--porcelain"], {...options, network: false});
    if (result.exitCode !== 0) {
        return [];
    }
    return parseConfigPorcelain(result.stdout).candidates;
}

/**
 * El único picker que no se cierra sobre su lista: `compare` toma un commit-ish,
 * y un tag o un SHA son respuestas legítimas que ninguna lista de ramas trae. Lo
 * que sí cambia es dónde se escribe — en la caja del propio QuickPick, que
 * además filtra las candidatas, en vez de un ítem "Enter commit-ish…" que sacaba
 * a otro diálogo y perdía la lista de vista. Lo tipeado se ofrece como primera
 * fila mientras no coincida con una candidata, así que aceptar es siempre elegir
 * una fila y nunca adivinar si el texto contaba.
 */
async function pickCommitIsh(
    candidates: CandidateBranch[],
    title: string,
    context: string
): Promise<string | undefined> {
    const branches = compareRevisionItems(candidates);
    if (branches.length === 0) {
        return inputCommitIsh(title, context);
    }

    return await new Promise<string | undefined>((resolve) => {
        const quickPick = vscode.window.createQuickPick<vscode.QuickPickItem & {value?: string}>();
        quickPick.title = title;
        quickPick.placeholder = context + " " + COMPARE_COPY.revisionPrompt;
        quickPick.items = branches;
        quickPick.onDidChangeValue((value) => {
            const typed = value.trim();
            const known = typed === "" || branches.some((b) => b.label === typed);
            quickPick.items = known
                ? branches
                : [{label: typed, description: "use as typed"}, ...branches];
        });
        quickPick.onDidAccept(() => {
            const selected = quickPick.selectedItems[0];
            const picked = selected?.value ?? selected?.label ?? quickPick.value.trim();
            quickPick.hide();
            resolve(picked === "" ? undefined : picked);
        });
        // Cancelar (Esc, o el foco afuera) también pasa por acá; el resolve de
        // onDidAccept ya ganó la carrera, así que este solo cubre el descarte.
        quickPick.onDidHide(() => {
            quickPick.dispose();
            resolve(undefined);
        });
        quickPick.show();
    });
}

async function inputCommitIsh(title: string, context: string): Promise<string | undefined> {
    const typed = await vscode.window.showInputBox({
        title,
        prompt: context,
        placeHolder: COMPARE_COPY.revisionPrompt,
        validateInput: (v) => (v.trim() === "" ? "Required" : undefined),
    });
    return typed?.trim();
}
