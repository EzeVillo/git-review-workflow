import * as assert from "node:assert";
import {isContinueReply, parseContinueGuard} from "../../src/review/continueReply";
import {captureToken, tokenStillValid} from "../../src/review/staleGuard";

describe("Continue authoritative response", () => {
    const guard = "a".repeat(40);
    const body = `state\treview/feature\tfeature\tdeadbeef\twhole\tnone\nguard\t${guard}\n`;
    const wire = `continue-state\t1\n${body}continue-state\tcomplete\n`;
    it("requires both a capability and an unambiguous valid inventory token", () => {
        const inventory = `capability\tcontinue-state\ncontinue-guard\t${guard}\n`;
        assert.strictEqual(parseContinueGuard(inventory), guard);
        assert.strictEqual(parseContinueGuard(inventory.replace(/\n/g,"\r\n")), guard);
        for (const bad of ["", `continue-guard\t${guard}\n`, inventory + inventory,
            inventory.replace(guard,"bad"), inventory.replace(guard,guard + " ")]) {
            assert.strictEqual(parseContinueGuard(bad), undefined);
        }
        const state = {situation: "no-review" as const, entries: [], files: [], branches: [], continueGuard: guard};
        assert.strictEqual(tokenStillValid(captureToken(state), {...state, continueGuard: "b".repeat(40)}),false);
    });
    it("requires a complete frame and exactly one authoritative review", () => {
        assert.strictEqual(isContinueReply(wire), true);
        assert.strictEqual(isContinueReply(wire.replace(/\n/g,"\r\n")), true);
        for (const bad of ["", body, wire.replace("continue-state\tcomplete\n",""), wire + "continue-state\tcomplete\n",
            wire.replace("review/feature", "main"), wire.replace(`guard\t${guard}\n`,""),
            wire.replace(body, body + body), wire.replace("continue-state\tcomplete", "finish\tconflict\t0\ncontinue-state\tcomplete")]) {
            assert.strictEqual(isContinueReply(bad),false,bad);
        }
    });
});
