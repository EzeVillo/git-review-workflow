import * as vscode from "vscode";

const record = "review-checkout\t";

export function reviewCheckoutPath(stdout: string): string | undefined {
    return stdout.split(/\r?\n/).find(line => line.startsWith(record))?.slice(record.length) || undefined;
}

export async function openReviewCheckout(path: string): Promise<void> {
    await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(path), {forceNewWindow: true});
}
