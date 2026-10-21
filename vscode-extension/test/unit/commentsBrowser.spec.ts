import * as assert from "node:assert";
import {runInNewContext} from "node:vm";
import {commentsBrowserHtml} from "../../src/views/commentsBrowserHtml";

class Element {
    children: Element[] = [];
    dataset: Record<string, unknown> = {};
    hidden = false; disabled = false; textContent = ""; title = ""; open = false; scrollTop = 0;
    onclick = () => {};
    attributes: Record<string, string> = {};
    appendChild(child: Element) {this.children.push(child);}
    replaceChildren() {this.children = [];}
    setAttribute(key: string, value: string) {this.attributes[key] = value;}
}
function browser() {
    const elements = new Map<string, Element>();
    const element = (id: string) => {if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id)!;};
    const messages: {type: string; ordinal?: number}[] = [];
    const handlers = new Map<string, (event: object) => void>();
    const script = commentsBrowserHtml("TEST").match(/<script[^>]*>([\s\S]*?)<\/script>/)![1];
    runInNewContext(script, {
        acquireVsCodeApi: () => ({postMessage: (message: {type: string; ordinal?: number}) => messages.push(message)}),
        document: {getElementById: element, createElement: () => new Element()},
        window: {addEventListener: (type: string, handler: (event: object) => void) => {handlers.set(type, handler);}},
    });
    const entries = (values: object[], canDelete = true) => handlers.get("message")!({data: {type: "entries", entries: values, canDelete}});
    const settled = () => handlers.get("message")!({data: {type: "settled"}});
    const escape = () => handlers.get("keydown")!({key: "Escape", preventDefault() {}});
    return {element, entries, settled, escape, messages};
}
const general = {ordinal: 1, label: "7. General", body: "General observation", version: "", warning: "", preview: "General observation", canOpenDiff: false};
const file = {...general, ordinal: 2, label: "9. File", body: "File observation", canOpenDiff: true};

describe("comment browser controls", () => {
    it("hides diff for general comments and only emits a file diff for a selected file", () => {
        const b = browser(); b.entries([general, file]);
        assert.strictEqual(b.element("open").hidden, true);
        b.element("open").onclick();
        assert.deepStrictEqual(b.messages.map(m => m.type), ["ready"]);
        b.element("list").children[1].onclick();
        assert.strictEqual(b.element("open").hidden, false);
        b.element("open").onclick();
        assert.strictEqual(JSON.stringify(b.messages.at(-1)), JSON.stringify({type: "open", ordinal: 2}));
    });
    it("locks controls during deletion and selects the next entry without rewriting labels", () => {
        const b = browser(); b.entries([general, file, {...file, ordinal: 3, label: "42. Last", body: "Last observation"}]);
        b.element("list").children[1].onclick(); b.element("delete").onclick();
        assert.strictEqual(JSON.stringify(b.messages.at(-1)), JSON.stringify({type: "delete", ordinal: 2}));
        b.escape(); assert.strictEqual(b.messages.length, 2);
        assert.ok(b.element("list").children.every(e => e.disabled));
        b.element("delete").onclick();
        assert.strictEqual(b.messages.length, 2);
        b.entries([general, {...file, label: "42. Last", body: "Last observation"}]); b.settled();
        assert.strictEqual(b.element("body").textContent, "Last observation");
        assert.deepStrictEqual(b.element("list").children.map(e => e.children[0].textContent), ["7. General", "42. Last"]);
        assert.strictEqual(b.element("delete").disabled, false);
        b.entries([general]); b.settled();
        assert.strictEqual(b.element("body").textContent, "General observation");
        b.entries([]); b.settled();
        assert.strictEqual(b.element("body").textContent, "No comments are available.");
        assert.strictEqual(b.element("delete").disabled, true);
        assert.strictEqual(b.element("open").hidden, true);
        b.escape(); assert.strictEqual(b.messages.at(-1)?.type, "close");
    });
    it("does not offer deletion for archived preparations", () => {
        const b = browser(); b.entries([general], false);
        assert.strictEqual(b.element("delete").hidden, true);
        b.element("delete").onclick(); assert.strictEqual(b.messages.length, 1);
    });
});
