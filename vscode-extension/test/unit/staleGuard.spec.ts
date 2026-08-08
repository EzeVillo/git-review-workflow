import * as assert from "node:assert";
import {captureToken, tokenStillValid} from "../../src/review/staleGuard";
// `import type`: `review/state.ts` importa `vscode`, que no existe fuera del
// host — el tipo se borra en compilación y el módulo no llega a cargarse.
import type {ReviewState} from "../../src/review/state";

function reviewState(branch: string, tip: string): ReviewState {
    return {
        situation: "review",
        state: {branch, source: "origin/" + branch, tip, mode: "whole", walkthrough: "none"},
        entries: [],
        files: [],
        branches: [],
    };
}

function noReviewState(): ReviewState {
    return {situation: "no-review", entries: [], files: [], branches: []};
}

describe("staleGuard", () => {
    it("revalidado contra el mismo testigo, aprueba", () => {
        const state = reviewState("review/feat", "abc123");
        const token = captureToken(state);
        assert.strictEqual(tokenStillValid(token, state), true);
    });

    it("un tip distinto rechaza (la review se rehizo sobre otro snapshot)", () => {
        const state = reviewState("review/feat", "abc123");
        const token = captureToken(state);
        const later = reviewState("review/feat", "def456");
        assert.strictEqual(tokenStillValid(token, later), false);
    });

    it("una situation distinta rechaza (el diálogo ya no describe la realidad)", () => {
        const state = reviewState("review/feat", "abc123");
        const token = captureToken(state);
        assert.strictEqual(tokenStillValid(token, noReviewState()), false);
    });

    it("una rama distinta rechaza (no es la review sobre la que se decidió)", () => {
        const state = reviewState("review/feat", "abc123");
        const token = captureToken(state);
        const later = reviewState("review/other", "abc123");
        assert.strictEqual(tokenStillValid(token, later), false);
    });

    it("captureToken sobre no-review captura branch/tip ausentes", () => {
        const token = captureToken(noReviewState());
        assert.strictEqual(token.situation, "no-review");
        assert.strictEqual(token.branch, undefined);
        assert.strictEqual(token.tip, undefined);
    });
});
