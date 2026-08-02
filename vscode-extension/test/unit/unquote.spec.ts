import * as assert from "node:assert";
import {toPathRef, unquotePath} from "../../src/cli/unquote";

describe("unquotePath", () => {
    it("deja igual un path sin citar", () => {
        assert.strictEqual(unquotePath("src/core.ts"), "src/core.ts");
    });

    it("deja igual un path con espacios sin citar", () => {
        assert.strictEqual(unquotePath("src/my file.ts"), "src/my file.ts");
    });

    it("deja igual un path con acentos sin citar (core.quotePath=false)", () => {
        assert.strictEqual(unquotePath("src/café.ts"), "src/café.ts");
    });

    it("decodifica un backslash escapado", () => {
        assert.strictEqual(unquotePath('"a\\\\b.ts"'), "a\\b.ts");
    });

    it("decodifica una comilla doble escapada", () => {
        assert.strictEqual(unquotePath('"a\\"b.ts"'), 'a"b.ts');
    });

    it("decodifica escapes de control conocidos", () => {
        assert.strictEqual(unquotePath('"a\\tb\\nc.ts"'), "a\tb\nc.ts");
    });

    it("reensambla octales consecutivos como bytes UTF-8", () => {
        // "café" con la e acentuada codificada UTF-8: c3 a9 -> \303\251
        assert.strictEqual(unquotePath('"caf\\303\\251.ts"'), "café.ts");
    });

    it("mezcla texto literal y escapes en el mismo path", () => {
        assert.strictEqual(unquotePath('"dir/a\\"b\\\\c.ts"'), 'dir/a"b\\c.ts');
    });
});

describe("toPathRef", () => {
    it("conserva raw y calcula display", () => {
        const ref = toPathRef('"a\\"b.ts"');
        assert.strictEqual(ref.raw, '"a\\"b.ts"');
        assert.strictEqual(ref.display, 'a"b.ts');
    });

    it("raw === display cuando no hay cita", () => {
        const ref = toPathRef("src/core.ts");
        assert.strictEqual(ref.raw, "src/core.ts");
        assert.strictEqual(ref.display, "src/core.ts");
    });
});
