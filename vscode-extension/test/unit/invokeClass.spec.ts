import * as assert from "node:assert";
import {resolveCommand, timeoutForClass} from "../../src/cli/invoke";

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

describe("resolveCommand", () => {
    it("sin gitReviewPath invoca git review <verbo> ...args", () => {
        assert.deepStrictEqual(resolveCommand("start", ["--step", "--", "feature/x"], undefined), {
            command: "git",
            args: ["review", "start", "--step", "--", "feature/x"],
        });
    });

    it("gitReviewPath vacio (sólo espacios) se trata igual que ausente", () => {
        assert.deepStrictEqual(resolveCommand("config", ["--porcelain"], "   "), {
            command: "git",
            args: ["review", "config", "--porcelain"],
        });
    });

    it("gitReviewPath .exe/.cmd se invoca directo, con el verbo primero (sin 'review')", () => {
        assert.deepStrictEqual(resolveCommand("start", ["--", "feature/x"], "C:\\tools\\git-review.cmd"), {
            command: "C:\\tools\\git-review.cmd",
            args: ["start", "--", "feature/x"],
        });
    });

    it("gitReviewPath sin extension nativa en win32 se envuelve con sh", function () {
        if (process.platform !== "win32") {
            this.skip();
        }
        assert.deepStrictEqual(resolveCommand("start", ["--", "feature/x"], "/home/me/bin/git-review"), {
            command: "sh",
            args: ["/home/me/bin/git-review", "start", "--", "feature/x"],
        });
    });
});
