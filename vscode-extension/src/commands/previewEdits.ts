import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {isReviewReadable} from "../review/situation";
import {ReviewStateManager} from "../review/state";

/**
 * `gitReview.previewEdits`: muestra `git review preview [--stat]` como
 * documento de solo lectura. No muta; sin confirmación modal.
 */
export async function previewEdits(
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions,
    stat: boolean
): Promise<void> {
    const state = stateManager.state;
    if (!isReviewReadable(state.situation) || !state.state) {
        void vscode.window.showInformationMessage("No active review to preview.");
        return;
    }

    const args = stat ? ["--stat"] : [];
    const result = await invokeGitReview("preview", args, getInvokeOptions());
    if (result.exitCode !== 0) {
        const text = result.stderr.trim() || result.stdout.trim() || "Could not preview your edits.";
        void vscode.window.showErrorMessage(text);
        return;
    }

    // Advertencias en éxito (p. ej. ediciones omitidas en step): no son estado.
    const note = result.stderr.trim();
    if (note.length > 0) {
        void vscode.window.showInformationMessage(note.split("\n")[0] ?? note);
    }

    const body = result.stdout.length > 0 ? result.stdout : "(no edits to preview)\n";
    // Documento untitled: no alimenta el view-model, solo muestra.
    const doc = await vscode.workspace.openTextDocument({
        language: stat ? "plaintext" : "diff",
        content: body,
    });
    await vscode.window.showTextDocument(doc, {preview: true, preserveFocus: false});
}
