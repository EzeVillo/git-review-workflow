import * as assert from "node:assert";
import {runInNewContext} from "node:vm";
import {panelHtml} from "../../src/views/panelHtml";

// Only the DOM operations used when rendering comment rows. The production script
// supplies all button handlers, SVGs, accessibility names and message payloads.
class Element {
    children: Element[] = [];
    attributes: Record<string, string> = {};
    listeners: Record<string, () => void> = {};
    textContent = "";
    id = "";
    className = "";
    title = "";
    disabled = false;
    constructor(readonly tag: string) {}
    appendChild(child: Element) { this.children.push(child); return child; }
    setAttribute(name: string, value: string) { this.attributes[name] = value; }
    addEventListener(name: string, listener: () => void) { this.listeners[name] = listener; }
}

function commentRows(documents: object[], pending = false, capture?: {target?: string; busy?: boolean; readonly?: boolean}, state = "result") {
    const messages: object[] = [];
    const saved: any[] = [];
    const elements: Element[] = [];
    const root = new Element("root");
    const create = (tag: string) => {const node = new Element(tag); elements.push(node); return node;};
    let receive: (event: object) => void;
    const script = panelHtml("TEST").match(/<script[^>]*>([\s\S]*?)<\/script>/)![1];
    const context: any = {
        acquireVsCodeApi: () => ({getState: () => undefined, setState: (state: object) => saved.push(state), postMessage: (message: object) => messages.push(message)}),
        document: {getElementById: (id: string) => id === "root" ? root : elements.find(node => node.id === id), createElement: create, createElementNS: (_ns: string, tag: string) => create(tag)},
        window: {addEventListener: (_name: string, listener: (event: object) => void) => {receive = listener;}},
    };
    runInNewContext(script.replace(/\}\(\)\);\s*$/, "globalThis.footerForTest = renderPaneFooter; globalThis.commentsForTest = function(next) { model = painted = next; return renderComments(next); };}());"), context);
    const section: Element = context.commentsForTest({situation: "review", commentTarget: capture?.target, busy: capture?.busy ?? false, readonly: capture?.readonly, comments: {
        guard: capture ? "guard" : undefined,
        documents, contexts: [{id: "c", kind: "review", state, label: "Feature"}],
        deliveries: pending ? [{context: "c", state: "pending"}] : [], diagnostics: [],
    }});
    messages.length = 0;
    return {section, rows: section.children.filter(c => c.className === "comments-row"), messages, saved,
        footer: (comments: object | null = {documents, contexts: [{id: "c", state}], deliveries: [], diagnostics: []}) => context.footerForTest({busy: false, comments}) as Element,
        updateTarget: (text?: string) => receive({data: {type: "commentTarget", text}})};
}

describe("comment row buttons", () => {
    function footerRows(footer: Element) {
        const comments = footer.children.find(section => section.children[0].textContent === "Comments");
        const rows: Element[] = [];
        function visit(node: Element) {
            if (node.className === "comments-row") rows.push(node);
            node.children.forEach(visit);
        }
        if (comments) visit(comments);
        return {comments, rows};
    }
    it("keeps the main Comments section with independent Local and Shared empty states", () => {
        const {footer} = commentRows([]);
        const {comments, rows} = footerRows(footer());
        assert.ok(comments);
        assert.deepStrictEqual(rows.map(row => row.children.map(child => child.textContent)), [
            ["Local", "No local comments."], ["Shared", "No shared comments."],
        ]);
        assert.ok(rows.every(row => row.children.every(child => child.tag !== "button")));
    });
    for (const kind of ["local", "shared"]) it("keeps the other empty state beside existing " + kind, () => {
        const {footer} = commentRows([{context: "c", kind, presence: "present", revision: "r"}]);
        const {rows} = footerRows(footer());
        assert.strictEqual(rows.length, 2);
        assert.strictEqual(rows[kind === "local" ? 1 : 0].children[1].textContent, kind === "local" ? "No shared comments." : "No local comments.");
        assert.strictEqual(rows[kind === "local" ? 0 : 1].children.find(child => child.tag === "strong")?.textContent, kind === "local" ? "Local" : "Shared");
    });
    it("does not report empty comments before reading or when reading fails", () => {
        const {footer} = commentRows([]);
        assert.strictEqual(footerRows(footer(null)).comments, undefined);
        const {comments, rows} = footerRows(footer({documents: [], contexts: [], deliveries: [], diagnostics: [{code: "read", message: "Cannot read comments"}]}));
        assert.ok(comments);
        assert.deepStrictEqual(rows, []);
    });
    it("places Comments after Walkthrough and before Compare in the main footer", () => {
        const {footer} = commentRows([{context: "c", kind: "shared", presence: "present", revision: "r"}], false, undefined, "repository");
        const titles = footer().children.map(section => section.children[0].textContent);
        assert.ok(titles.indexOf("Walkthrough") < titles.indexOf("Comments"));
        assert.ok(titles.indexOf("Comments") < titles.indexOf("Compare"));
    });
    it("shows only reading controls for repository Shared outside a review", () => {
        const {rows} = commentRows([{context: "c", kind: "shared", presence: "present", revision: "r"}], false, undefined, "repository");
        assert.deepStrictEqual(rows[0].children.filter(c => c.tag === "button").map(b => b.attributes["aria-label"]), ["Open", "View changes"]);
    });
    it("keeps General and Add comment available before any document exists", () => {
        const {section, messages} = commentRows([], false, {});
        assert.deepStrictEqual(section.children.map(child => child.tag), ["p", "div"]);
        assert.strictEqual(section.children[0].textContent, "General comment");
        const actions = section.children[1];
        assert.strictEqual(actions.className, "comments-actions");
        assert.strictEqual(actions.children.length, 1);
        const add = actions.children[0];
        assert.strictEqual(add.children[0].textContent, "Add comment");
        assert.strictEqual(add.disabled, false);
        add.listeners.click();
        assert.strictEqual(JSON.stringify(messages), JSON.stringify([{type: "addComment"}]));
    });
    it("updates and persists the target without replacing the comment action", () => {
        const {section, saved, updateTarget} = commentRows([], false, {target: "File · src/file.ts (New version)"});
        const hint = section.children[0], actions = section.children[1];
        updateTarget("General comment");
        assert.strictEqual(hint.textContent, "General comment");
        assert.strictEqual(saved.at(-1).commentTarget, "General comment");
        updateTarget("Selected code · src/file.ts:2–3 (New version)");
        assert.strictEqual(hint.textContent, "Selected code · src/file.ts:2–3 (New version)");
        assert.strictEqual(saved.at(-1).commentTarget, hint.textContent);
        assert.strictEqual(section.children[1], actions);
    });
    it("offers Add without an explicit Save even in compare", () => {
        const {section} = commentRows([], false, {readonly: true, busy: true});
        const buttons = section.children[1].children;
        assert.deepStrictEqual(buttons.map(button => button.children[0].textContent), ["Add comment"]);
        assert.deepStrictEqual(buttons.map(button => button.disabled), [true]);
    });
    it("sends each visible row's physical document index from accessible icon buttons", () => {
        const {rows, messages} = commentRows([
            {context: "c", kind: "local", presence: "absent", revision: "absent"},
            {context: "c", kind: "local", presence: "present", revision: "r1"},
            {context: "c", kind: "shared", presence: "present", revision: "r2"},
        ]);
        assert.strictEqual(rows.length, 2);
        rows.forEach((row, rowIndex) => {
            const names = rowIndex === 0 ? ["Open", "Copy path", "Renumber", "View changes", "Delete"] : ["Open", "Renumber", "View changes", "Delete"];
            const actions = rowIndex === 0 ? ["openComments", "copyCommentPath", "renumberComments", "openCommentDiff", "deleteComments"] : ["openComments", "renumberComments", "openCommentDiff", "deleteComments"];
            const buttons = row.children.filter(c => c.tag === "button");
            assert.deepStrictEqual(buttons.map(b => b.attributes["aria-label"]), names);
            buttons.forEach((button, actionIndex) => {
                assert.ok(button.title);
                assert.strictEqual(button.disabled, false);
                assert.deepStrictEqual(button.children.map(c => c.tag), ["svg"]);
                assert.strictEqual(button.children[0].attributes["aria-hidden"], "true");
                button.listeners.click();
                assert.strictEqual(JSON.stringify(messages.pop()), JSON.stringify({type: actions[actionIndex], index: rowIndex + 1}));
            });
        });
    });

    it("keeps Open and Copy path enabled for an unreadable Local document", () => {
        const {rows} = commentRows([{context: "c", kind: "local", presence: "present", revision: "unreadable"}]);
        assert.deepStrictEqual(rows[0].children.filter(c => c.tag === "button").map(b => b.disabled), [false, false, true, true, true]);
    });

    for (const state of ["active", "result", "repository"]) it("offers Copy path only for existing Local documents in " + state, () => {
        const {rows, footer} = commentRows([
            {context: "c", kind: "local", presence: "absent", revision: "absent"},
            {context: "c", kind: "shared", presence: "present", revision: "s"},
            {context: "c", kind: "local", presence: "present", revision: "l"},
        ], false, undefined, state);
        for (const rendered of [rows, footerRows(footer()).rows]) {
            const copies = rendered.flatMap(row => row.children.filter(button => button.attributes["aria-label"] === "Copy path"));
            assert.strictEqual(copies.length, 1);
            assert.strictEqual(copies[0].title, "Copy this document's path");
            assert.strictEqual(copies[0].disabled, false);
        }
    });

    it("disables Copy path while the panel is busy", () => {
        const {rows} = commentRows([{context: "c", kind: "local", presence: "present", revision: "r"}], false, {busy: true});
        assert.strictEqual(rows[0].children.find(b => b.attributes["aria-label"] === "Copy path")?.disabled, true);
    });

    it("preserves text and document indices for Create and Prepare", () => {
        const {rows, messages} = commentRows([{context: "c", kind: "shared", presence: "absent", revision: "absent"}], true);
        const buttons = rows[0].children.filter(c => c.tag === "button");
        assert.deepStrictEqual(buttons.map(b => b.children[0].textContent), ["Create", "Prepare"]);
        buttons.forEach(b => b.listeners.click());
        assert.strictEqual(JSON.stringify(messages), JSON.stringify([{type: "initComments", index: 0}, {type: "prepareSharedComments", index: 0}]));
    });
});
