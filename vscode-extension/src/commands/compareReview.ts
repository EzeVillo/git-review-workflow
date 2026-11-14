import * as vscode from "vscode";
import {compareRevisionItems, parseConfigPorcelain} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {buildLayoutItems, layoutSummary} from "../review/layoutOffers";
import {ReviewStateManager} from "../review/state";
import {confirmMutation} from "../review/confirm";
import {PanelRevealer, revealPanel} from "../views/reveal";
import {parseMergedRecord} from "../review/draftFlow";
import {draftUpdated} from "../review/userCopy";
import {COMPARE_COPY, comparisonSummary, compareBasePrompt, compareConfirmTitle, comparingProgress} from "../review/userCopy";

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
    const options = getInvokeOptions();
    const loaded = await loadCandidates(options);
    if (!loaded) return;
    const {branches: candidates, legacy} = loaded;
    const upper = await pickCommitIsh(candidates, COMPARE_COPY.targetTitle);
    if (!upper) {
        return;
    }
    const lower = await pickCommitIsh(candidates, COMPARE_COPY.baseTitle, compareBasePrompt(upper));
    if (!lower) {
        return;
    }

    const network = [lower, upper].some(ref => ref.startsWith("fetch:"));
    if (legacy) {
        const report = await invokeGitReview("config", ["--porcelain", "--compare", "--", lower, upper], {...options, network: false});
        if (report.errorCode || report.exitCode !== 0) {
            void vscode.window.showErrorMessage(report.stderr.trim() || COMPARE_COPY.failed);
            return;
        }
        await readComparison(lower, upper, undefined, report.stdout, options, lock, stateManager, reveal);
        return;
    }
    const prepare = () => invokeGitReview("compare", ["--prepare", "--porcelain", "--", lower, upper], {...options, network, timeoutMs: network ? 300_000 : undefined});
    const report = network
        ? await vscode.window.withProgress({location: vscode.ProgressLocation.Notification, title: COMPARE_COPY.prepareProgress}, prepare)
        : await prepare();
    if (report.errorCode || report.exitCode !== 0) {
        void vscode.window.showErrorMessage(report.stderr.trim() || COMPARE_COPY.failed);
        return;
    }
    const token = report.stdout.match(/^comparison-prepared\t([0-9a-f]+)\r?$/m)?.[1];
    if (!token) {
        void vscode.window.showErrorMessage(COMPARE_COPY.failed);
        return;
    }
    try {
        await readComparison(lower, upper, token, report.stdout, options, lock, stateManager, reveal);
    } finally {
        await invokeGitReview("compare", ["--release", "--", token], {...options, network: false});
    }
}

async function readComparison(lower: string, upper: string, token: string | undefined, stdout: string,
    options: InvokeOptions, lock: MutationLock, stateManager: ReviewStateManager, reveal: PanelRevealer): Promise<void> {
    const prepared = token ? [`--prepared=${token}`] : [];
    const items = buildLayoutItems(parseConfigPorcelain(stdout).offers).map(item => ({
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
                const invocation = await invokeGitReview("walkthrough", ["draft", "--porcelain", "--compare", ...prepared, "--", lower, upper], {...options, network: false});
                await stateManager.refreshPrimary();
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
            await stateManager.refreshPrimary();
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
    args.push(...prepared, "--", lower, upper);

    await lock.run(async () => {
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: comparingProgress(lower, upper),
            },
            async () => {
                const invocation = await invokeGitReview("compare", args, {...options, network: false});
                await stateManager.refreshPrimary();
                return invocation;
            }
        );
        if (result && result.exitCode !== 0) {
            const text = result.stderr.trim() || COMPARE_COPY.failed;
            void vscode.window.showErrorMessage(text);
        }
    });
}

type BranchSource = {kind: "local" | "remote" | "cached" | "literal"; remote: string; value: string};

async function loadCandidates(options: InvokeOptions): Promise<{branches: Map<string, BranchSource[]>; legacy: boolean} | undefined> {
    const result = await invokeGitReview("compare", ["--sources", "--porcelain"], {...options, network: false});
    const branches = new Map<string, BranchSource[]>();
    if (result.exitCode !== 0 && result.stderr.includes("unknown option --sources")) {
        const config = await invokeGitReview("config", ["--porcelain"], {...options, network: false});
        for (const item of compareRevisionItems(parseConfigPorcelain(config.stdout).candidates)) {
            branches.set(item.label, [{kind: "literal", remote: "", value: item.value}]);
        }
        return {branches, legacy: true};
    }
    if (result.exitCode !== 0) {
        void vscode.window.showErrorMessage(result.stderr.trim() || COMPARE_COPY.failed);
        return;
    }
    for (const line of result.stdout.split(/\r?\n/)) {
        const [record, name, kind, remote, value] = line.split("\t");
        if (record !== "compare-source" || !name || !value || (kind !== "local" && kind !== "remote" && kind !== "cached")) continue;
        const sources = branches.get(name) ?? [];
        sources.push({kind, remote, value});
        branches.set(name, sources);
    }
    return {branches, legacy: false};
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
    candidates: Map<string, BranchSource[]>,
    title: string,
    context?: string
): Promise<string | undefined> {
    const branches = [...candidates.keys()].map(label => ({label}));
    if (branches.length === 0) {
        return inputCommitIsh(title, context);
    }

    const revision = await new Promise<string | undefined>((resolve) => {
        const quickPick = vscode.window.createQuickPick<vscode.QuickPickItem & {value?: string}>();
        quickPick.title = title;
        quickPick.placeholder = context ? `${context} ${COMPARE_COPY.revisionPrompt}` : COMPARE_COPY.revisionPrompt;
        quickPick.items = branches;
        quickPick.onDidChangeValue((value) => {
            const typed = value.trim();
            const known = typed === "" || branches.some((b) => b.label === typed);
            quickPick.items = known
                ? branches
                : [{label: typed, description: COMPARE_COPY.useAsTyped}, ...branches];
        });
        quickPick.onDidAccept(() => {
            const selected = quickPick.selectedItems[0];
            const picked = selected?.value ?? selected?.label ?? quickPick.value.trim();
            resolve(picked === "" ? undefined : picked);
            quickPick.hide();
        });
        // Cancelar (Esc, o el foco afuera) también pasa por acá; el resolve de
        // onDidAccept ya ganó la carrera, así que este solo cubre el descarte.
        quickPick.onDidHide(() => {
            quickPick.dispose();
            resolve(undefined);
        });
        quickPick.show();
    });
    if (!revision) return;
    const sources = candidates.get(revision);
    if (!sources) return revision;
    if (sources[0]?.kind === "literal") return sources[0].value;
    const items = sources.map(source => ({
        label: source.kind === "local" ? COMPARE_COPY.sourceLocal :
            (source.kind === "remote" ? COMPARE_COPY.sourceRemote : COMPARE_COPY.sourceCached).replace("{remote}", () => source.remote),
        value: source.value,
    }));
    return (await vscode.window.showQuickPick(items, {title: COMPARE_COPY.sourceTitle.replace("{branch}", () => revision)}))?.value;
}

async function inputCommitIsh(title: string, context?: string): Promise<string | undefined> {
    const typed = await vscode.window.showInputBox({
        title,
        prompt: context,
        placeHolder: COMPARE_COPY.revisionPrompt,
        validateInput: (v) => (v.trim() === "" ? "Required" : undefined),
    });
    return typed?.trim();
}
