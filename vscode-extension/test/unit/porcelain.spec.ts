import * as assert from "node:assert";
import {parsePorcelain} from "../../src/cli/porcelain";
import {PathRef} from "../../src/cli/unquote";

describe("parsePorcelain", () => {
    it("parsea state en modo whole (6 campos)", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "whole");
        assert.strictEqual(result.state.walkthrough, "none");
        assert.strictEqual(result.state.position, undefined);
        assert.strictEqual(result.state.essential, undefined);
        assert.deepStrictEqual(result.entries, []);
    });

    it("parsea state en modo step (10 campos), current como string", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t2\t9\t9\t9fe1c0d\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "step");
        assert.strictEqual(result.state.position, 2);
        assert.strictEqual(result.state.total, 9);
        assert.strictEqual(result.state.recorded, 9);
        assert.strictEqual(result.state.current, "9fe1c0d");
        assert.strictEqual(result.state.essential, undefined);
    });

    it("parsea state en modo walk (11 campos), current como PathRef", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\twalk\tapplied\t3\t7\t7\tsrc/core.ts\t1\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "walk");
        assert.strictEqual(result.state.essential, true);
        const current = result.state.current as PathRef;
        assert.strictEqual(current.raw, "src/core.ts");
        assert.strictEqual(current.display, "src/core.ts");
    });

    it("entry en modo walk trae essential, no banked", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twalk\tapplied\t1\t2\t2\tsrc/a.ts\t0",
            "entry\t1\tsrc/a.ts\t0",
            "entry\t2\tsrc/b.ts\t1",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.entries.length, 2);
        assert.strictEqual(result.entries[0].essential, false);
        assert.strictEqual(result.entries[0].banked, undefined);
        assert.strictEqual(result.entries[1].essential, true);
    });

    it("entry en modo step trae banked, no essential", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\tstep\tnone\t1\t2\t2\t1111111",
            "entry\t1\t1111111\t1",
            "entry\t2\t2222222\t0",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.entries[0].banked, true);
        assert.strictEqual(result.entries[0].essential, undefined);
        assert.strictEqual(result.entries[1].banked, false);
    });

    it("ignora etiquetas desconocidas", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone",
            "future-tag\tsome\tfields",
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.mode, "whole");
        assert.deepStrictEqual(result.entries, []);
    });

    it("ignora campos extra al final de un registro conocido", () => {
        const out = "state\treview/feat-x\torigin/feat-x\tabc123\twhole\tnone\textra1\textra2\n";
        const result = parsePorcelain(out);
        assert.strictEqual(result.state.branch, "review/feat-x");
        assert.strictEqual(result.state.mode, "whole");
    });

    it("uncovered produce PathRef con raw/display correctos", () => {
        const out = [
            "state\treview/feat-x\torigin/feat-x\tabc123\twalk\tapplied\t1\t1\t1\tsrc/a.ts\t0",
            "entry\t1\tsrc/a.ts\t0",
            'uncovered\t"caf\\303\\251.ts"',
        ].join("\n");
        const result = parsePorcelain(out);
        assert.strictEqual(result.uncovered.length, 1);
        assert.strictEqual(result.uncovered[0].id.raw, '"caf\\303\\251.ts"');
        assert.strictEqual(result.uncovered[0].id.display, "café.ts");
    });

    it("lanza si no hay registro state", () => {
        assert.throws(() => parsePorcelain(""));
    });
});
