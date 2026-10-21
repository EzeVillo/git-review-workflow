import * as vscode from "vscode";
import {CommentDocumentKind} from "../cli/commentsPorcelain";
import {CommentLocation, CommentScope} from "../review/commentsFlow";
import {COMMENTS_COPY as copy} from "../review/userCopy";
import {commentsComposerHtml} from "./commentsComposerHtml";

interface ComposerMessage {type?: string; kind?: string; text?: string; scope?: string}
export interface CommentComposerState {active: boolean; destination?: CommentDocumentKind; text: string; scope?: CommentScope; error?: string}
let current: {send(message: ComposerMessage): Promise<void>; state: CommentComposerState} | undefined;
export async function sendCommentComposerMessage(message: ComposerMessage): Promise<void> {await current?.send(message);}
export function commentComposerState(): CommentComposerState | undefined {return current ? {...current.state} : undefined;}

/** Code context is frozen before opening; changing scope preserves text and selection. */
export function commentsComposer(capture: CommentLocation | undefined, destinations: readonly CommentDocumentKind[], submit: (kind: CommentDocumentKind, text: string, scope: CommentScope) => Promise<string | undefined>, warning?: string): void {
    if (!destinations.length) return;
    const panel = vscode.window.createWebviewPanel("gitReview.commentsComposer", copy.add, vscode.ViewColumn.Active, {enableScripts: true, retainContextWhenHidden: true});
    const scopes: CommentScope[] = capture ? [...(capture.hasSelection ? ["selection" as const] : []), "file", "general"] : ["general"];
    const nonce = String(Date.now()) + String(Math.random()).slice(2);
    let busy = false;
    const state: CommentComposerState = {active: true, destination: destinations.length === 1 ? destinations[0] : undefined, text: "", scope: scopes[0]};
    const handleMessage = async (msg: ComposerMessage): Promise<void> => {
        if (msg.type === "ready") {await panel.webview.postMessage({type: "capture", capture, scopes, destinations, copy, warning}); return;}
        if (msg.type === "cancel") {if (!busy) panel.dispose(); return;}
        const kind = msg.kind ?? (destinations.length === 1 ? destinations[0] : undefined);
        if (busy || msg.type !== "save" || ((kind !== "local" && kind !== "shared") || !destinations.includes(kind)) || typeof msg.text !== "string" || !msg.text.trim()) return;
        const scope = msg.scope ?? scopes[0];
        if (!scopes.includes(scope as CommentScope)) return;
        busy = true;
        state.destination = kind as CommentDocumentKind; state.text = msg.text; state.scope = scope as CommentScope;
        try {
            const error = await submit(kind as CommentDocumentKind, msg.text, state.scope);
            if (!error) panel.dispose();
            else {state.error = error; await panel.webview.postMessage({type: "error", text: error});}
        } catch (error) {state.error = error instanceof Error ? error.message : copy.failed; await panel.webview.postMessage({type: "error", text: state.error});}
        finally {busy = false;}
    };
    const session = {send: handleMessage, state}; current = session;
    const listener = panel.webview.onDidReceiveMessage(handleMessage);
    panel.onDidDispose(() => {listener.dispose(); state.active = false; state.text = ""; if (current === session) current = undefined;});
    panel.webview.html = commentsComposerHtml(nonce);
}
