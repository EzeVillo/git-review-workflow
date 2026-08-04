import * as assert from "node:assert";
import {timeoutForClass} from "../../src/cli/invoke";

describe("timeoutForClass", () => {
    it("15000 para verbos de lectura", () => {
        for (const verb of ["status", "list", "config", "--why", "--version"]) {
            assert.strictEqual(timeoutForClass(verb, []), 15000, verb);
        }
    });

    it("120000 para mutaciones locales", () => {
        for (const verb of ["finish", "save", "abort", "continue", "next", "prev"]) {
            assert.strictEqual(timeoutForClass(verb, []), 120000, verb);
        }
    });

    it("300000 para start", () => {
        assert.strictEqual(timeoutForClass("start", []), 300000);
    });

    it("un verbo desconocido se trata como lectura, el default más conservador", () => {
        assert.strictEqual(timeoutForClass("walkthrough", []), 15000);
    });

    it("args no cambia la clasificación (depende sólo del verbo)", () => {
        assert.strictEqual(timeoutForClass("status", ["--porcelain", "some/branch"]), 15000);
        assert.strictEqual(timeoutForClass("start", ["--step", "--", "-foo"]), 300000);
    });
});
