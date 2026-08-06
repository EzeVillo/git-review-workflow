import * as assert from "node:assert";
import {formatCommandLine, shellQuoteArg} from "../../src/cli/cliLog";

describe("shellQuoteArg", () => {
    it("deja intacto un arg sin espacios ni comillas", () => {
        assert.strictEqual(shellQuoteArg("--porcelain"), "--porcelain");
        assert.strictEqual(shellQuoteArg("feature/x"), "feature/x");
    });

    it("cita el string vacio", () => {
        assert.strictEqual(shellQuoteArg(""), '""');
    });

    it("cita args con espacios o comillas", () => {
        assert.strictEqual(shellQuoteArg("a b"), '"a b"');
        assert.strictEqual(shellQuoteArg('say "hi"'), '"say \\"hi\\""');
    });
});

describe("formatCommandLine", () => {
    it("arma git review status --porcelain", () => {
        assert.strictEqual(
            formatCommandLine("git", ["review", "status", "--porcelain"]),
            "git review status --porcelain"
        );
    });

    it("cita el path del dispatcher y el raw del why", () => {
        assert.strictEqual(
            formatCommandLine("sh", ["/home/me/bin/git-review", "status", "--why", "src/a b.ts"]),
            'sh /home/me/bin/git-review status --why "src/a b.ts"'
        );
    });
});
