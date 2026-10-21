import * as assert from "node:assert";
import {invokeGitReview} from "../../src/cli/invoke";
describe("comments stdin", () => {
    it("writes UTF-8 and closes stdin with exact multiline EOF", async () => {
        const body = "línea uno\n\nsecond `$(echo secret)`";
        const result = await invokeGitReview("-e", ["process.stdin.setEncoding('utf8');let s='';process.stdin.on('data',c=>s+=c);process.stdin.on('end',()=>process.stdout.write(s))"], {cwd: process.cwd(), gitReviewPath: process.execPath, stdin: body, timeoutMs: 1500});
        assert.strictEqual(result.exitCode, 0);
        assert.strictEqual(result.stdout, body);
    });
});
