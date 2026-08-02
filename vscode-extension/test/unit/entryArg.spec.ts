import * as assert from "node:assert";
import {EntryRecord} from "../../src/cli/porcelain";
import {resolveEntryArg} from "../../src/review/entryArg";

const first: EntryRecord = {position: 1, id: {raw: "src/a.ts", display: "src/a.ts"}, essential: true};
const second: EntryRecord = {position: 2, id: {raw: "src/b.ts", display: "src/b.ts"}, essential: false};
const entries = [first, second];

describe("resolveEntryArg", () => {
    it("devuelve el EntryRecord cuando el comando lo recibe directo (TreeItem.command)", () => {
        assert.strictEqual(resolveEntryArg(second, entries, 1), second);
    });

    it("desenvuelve el nodo del arbol que pasan los menus view/item/context", () => {
        assert.strictEqual(resolveEntryArg({kind: "entry", entry: second}, entries, 1), second);
    });

    it("sin argumento (paleta de comandos) cae en la entrada actual", () => {
        assert.strictEqual(resolveEntryArg(undefined, entries, 2), second);
        assert.strictEqual(resolveEntryArg(null, entries, 1), first);
    });

    it("sin argumento y sin posicion actual no inventa una entrada", () => {
        assert.strictEqual(resolveEntryArg(undefined, entries, undefined), undefined);
        assert.strictEqual(resolveEntryArg(undefined, entries, 99), undefined);
        assert.strictEqual(resolveEntryArg(undefined, [], 1), undefined);
    });

    it("los nodos que no son entradas dan undefined, no una entrada arbitraria", () => {
        assert.strictEqual(resolveEntryArg({kind: "uncoveredGroup"}, entries, 1), undefined);
        assert.strictEqual(
            resolveEntryArg({kind: "uncoveredFile", file: {id: {raw: "src/c.ts", display: "src/c.ts"}}}, entries, 1),
            undefined
        );
        assert.strictEqual(resolveEntryArg("src/a.ts", entries, 1), undefined);
    });

    it("modo step: el id es un string y se resuelve igual", () => {
        const stepEntry: EntryRecord = {position: 1, id: "abc1234", banked: true};
        assert.strictEqual(resolveEntryArg({kind: "entry", entry: stepEntry}, [stepEntry], 1), stepEntry);
    });
});
