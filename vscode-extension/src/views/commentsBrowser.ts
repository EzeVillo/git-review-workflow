import * as vscode from "vscode";
import {commentsBrowserHtml} from "./commentsBrowserHtml";
import {CommentPresentation} from "../review/commentPresentation";
import {COMMENTS_COPY as copy} from "../review/userCopy";
import {confirmMutation} from "../review/confirm";

interface BrowserMessage {type?: string; ordinal?: number}
export interface CommentBrowserState {entries: CommentPresentation[]; canDelete: boolean; error?: string}
let current: {state: CommentBrowserState; send(message: BrowserMessage): Promise<void>} | undefined;
export function commentBrowserState(): CommentBrowserState | undefined {return current?.state;}
export async function sendCommentBrowserMessage(message: BrowserMessage): Promise<void> {await current?.send(message);}

/** Keep the list/detail view open after individual deletions. */
export function commentsBrowser(entries: CommentPresentation[], open: (ordinal: number) => Promise<void>, remove?: (ordinal: number) => Promise<CommentPresentation[]>): void {
    const panel = vscode.window.createWebviewPanel("gitReview.commentsBrowser", copy.title, vscode.ViewColumn.Active, {enableScripts: true, retainContextWhenHidden: true});
    const nonce = String(Date.now()) + String(Math.random()).slice(2);
    let busy = false;
    const state: CommentBrowserState = {entries, canDelete: !!remove};
    const publish = () => panel.webview.postMessage({type: "entries", entries: state.entries, canDelete: state.canDelete});
    const handleMessage = async (message: BrowserMessage): Promise<void> => {
        if (message.type === "close") {if (!busy) panel.dispose(); return;}
        if (message.type === "ready") {await publish(); return;}
        const entry = state.entries.find(e => e.ordinal === message.ordinal);
        if (busy || !entry || (message.type !== "open" && message.type !== "delete")) return;
        if ((message.type === "open" && !entry.canOpenDiff) || (message.type === "delete" && !remove)) return;
        busy = true;
        try {
            if (message.type === "delete") {
                if (await confirmMutation("deleteCommentEntry", copy.deleteEntryTitle, copy.deleteEntryDetail, copy.delete)) {
                    state.entries = await remove!(entry.ordinal);
                    await publish();
                }
            } else {await open(entry.ordinal); panel.dispose(); return;}
            state.error = undefined;
            await panel.webview.postMessage({type: "settled"});
        } catch (error) {
            state.error = error instanceof Error ? error.message : copy.failed;
            await panel.webview.postMessage({type: "settled", error: state.error});
        } finally {busy = false;}
    };
    const session = {state, send: handleMessage}; current = session;
    const listener = panel.webview.onDidReceiveMessage(handleMessage);
    panel.onDidDispose(() => {listener.dispose(); if (current === session) current = undefined;});
    panel.webview.html = commentsBrowserHtml(nonce);
}
