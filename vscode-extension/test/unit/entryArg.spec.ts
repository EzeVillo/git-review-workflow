import * as assert from "node:assert";
import {EntryRecord} from "../../src/cli/porcelain";
import {resolveEntryArg} from "../../src/review/entryArg";

const first: EntryRecord = {position: 1, id: {raw: "src/a.ts", display: "src/a.ts"}, essential: true};
const second: EntryRecord = {position: 2, id: {raw: "src/b.ts", display: "src/b.ts"}, essential: false};
const entries = [first, second];

describe("resolveEntryArg", () => {
    it("devuelve el EntryRecord cuando el comando lo recibe directo", () => {
        assert.strictEqual(resolveEntryArg(second, entries, 1), second);
    });

    it("sin argumento (panel y paleta de comandos) cae en la entrada actual", () => {
        assert.strictEqual(resolveEntryArg(undefined, entries, 2), second);
        assert.strictEqual(resolveEntryArg(null, entries, 1), first);
    });

    it("sin argumento y sin posicion actual no inventa una entrada", () => {
        assert.strictEqual(resolveEntryArg(undefined, entries, undefined), undefined);
        assert.strictEqual(resolveEntryArg(undefined, entries, 99), undefined);
        assert.strictEqual(resolveEntryArg(undefined, [], 1), undefined);
    });

    it("un argumento que no es una entrada da undefined, no una entrada arbitraria", () => {
        assert.strictEqual(resolveEntryArg({kind: "entry", entry: second}, entries, 1), undefined);
        assert.strictEqual(resolveEntryArg({file: {id: {raw: "src/c.ts", display: "src/c.ts"}}}, entries, 1), undefined);
        assert.strictEqual(resolveEntryArg("src/a.ts", entries, 1), undefined);
        assert.strictEqual(resolveEntryArg(2, entries, 1), undefined);
    });

    it("modo step: el id es un string y se resuelve igual", () => {
        const stepEntry: EntryRecord = {position: 1, id: "abc1234", banked: true};
        assert.strictEqual(resolveEntryArg(stepEntry, [stepEntry], 1), stepEntry);
    });
});
