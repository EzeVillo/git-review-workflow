import * as vscode from "vscode";
import {EntryRecord, UncoveredRecord} from "../cli/porcelain";
import {PathRef} from "../cli/unquote";
import {InvokeOptions} from "../cli/invoke";
import {ReviewState} from "../review/state";
import {fetchWhy} from "./whyContentProvider";

export type WalkthroughNode =
    | { kind: "entry"; entry: EntryRecord }
    | { kind: "uncoveredGroup" }
    | { kind: "uncoveredFile"; file: UncoveredRecord };

function displayOf(id: string | PathRef): string {
    return typeof id === "string" ? id : id.display;
}

/**
 * `TreeDataProvider` del panel: entradas en el orden de lectura (FR-005), la
 * actual marcada por `position` (FR-006, nunca por `id`), esenciales (walk) y
 * con ediciones guardadas (step) distinguidas por ícono + texto (FR-007,
 * FR-027), y los archivos sin cobertura agrupados aparte (FR-008).
 */
export class WalkthroughTreeProvider implements vscode.TreeDataProvider<WalkthroughNode> {
    private readonly changeEmitter = new vscode.EventEmitter<void>();
    readonly onDidChangeTreeData = this.changeEmitter.event;

    constructor(
        private readonly getState: () => ReviewState,
        private readonly getInvokeOptions: () => InvokeOptions
    ) {
    }

    refresh(): void {
        this.changeEmitter.fire();
    }

    getChildren(element?: WalkthroughNode): WalkthroughNode[] {
        const state = this.getState();
        if (state.situation !== "review") {
            return [];
        }

        if (element === undefined) {
            const nodes: WalkthroughNode[] = state.entries.map((entry) => ({kind: "entry", entry}));
            if (state.uncovered.length > 0) {
                nodes.push({kind: "uncoveredGroup"});
            }
            return nodes;
        }

        if (element.kind === "uncoveredGroup") {
            return state.uncovered.map((file) => ({kind: "uncoveredFile", file}));
        }

        return [];
    }

    getTreeItem(element: WalkthroughNode): vscode.TreeItem {
        if (element.kind === "uncoveredGroup") {
            return this.uncoveredGroupItem();
        }
        if (element.kind === "uncoveredFile") {
            return this.uncoveredFileItem(element.file);
        }
        return this.entryItem(element.entry);
    }

    async resolveTreeItem(item: vscode.TreeItem, element: WalkthroughNode): Promise<vscode.TreeItem> {
        if (element.kind !== "entry") {
            return item;
        }
        const state = this.getState();
        if (state.state?.mode !== "walk" || !isPathRef(element.entry.id)) {
            return item;
        }
        const why = await fetchWhy(element.entry.id.raw, this.getInvokeOptions());
        if (why === undefined) {
            return item;
        }
        item.tooltip = why.present ? new vscode.MarkdownString(why.text) : "(sin explicación)";
        return item;
    }

    private uncoveredGroupItem(): vscode.TreeItem {
        const item = new vscode.TreeItem("Sin cobertura", vscode.TreeItemCollapsibleState.Collapsed);
        item.contextValue = "uncoveredGroup";
        item.iconPath = new vscode.ThemeIcon("files");
        return item;
    }

    private uncoveredFileItem(file: UncoveredRecord): vscode.TreeItem {
        const item = new vscode.TreeItem(file.id.display, vscode.TreeItemCollapsibleState.None);
        item.contextValue = "uncoveredFile";
        item.iconPath = new vscode.ThemeIcon("file");
        return item;
    }

    private entryItem(entry: EntryRecord): vscode.TreeItem {
        const state = this.getState();
        const mode = state.state?.mode;
        const label = displayOf(entry.id);
        const item = new vscode.TreeItem(label, vscode.TreeItemCollapsibleState.None);
        item.contextValue = mode === "walk" ? "entry-walk" : "entry-step";

        const isCurrent = state.state?.position === entry.position;
        const descriptors: string[] = [];

        if (isCurrent) {
            item.iconPath = new vscode.ThemeIcon("arrow-right", new vscode.ThemeColor("charts.blue"));
        } else if (mode === "walk" && entry.essential) {
            item.iconPath = new vscode.ThemeIcon("star-full");
        } else if (mode === "step" && entry.banked) {
            item.iconPath = new vscode.ThemeIcon("check");
        } else {
            item.iconPath = new vscode.ThemeIcon("circle-outline");
        }

        if (mode === "walk" && entry.essential) {
            descriptors.push("esencial");
        }
        if (mode === "step" && entry.banked) {
            descriptors.push("con ediciones guardadas");
        }
        if (descriptors.length > 0) {
            item.description = descriptors.join(" · ");
        }

        item.command = {
            command: "gitReview.openEntry",
            title: mode === "step" ? "Ver cambios" : "Abrir entrada",
            arguments: [entry],
        };

        return item;
    }
}

function isPathRef(id: string | PathRef): id is PathRef {
    return typeof id !== "string";
}
