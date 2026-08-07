import * as assert from "node:assert";
import {pickSoleTarget} from "../../src/review/soleTarget";

describe("pickSoleTarget", () => {
    it("sin targets devuelve undefined", () => {
        assert.strictEqual(pickSoleTarget([]), undefined);
    });

    it("con exactamente uno devuelve ese", () => {
        const only = {label: "repo"};
        assert.strictEqual(pickSoleTarget([only]), only);
    });

    it("con dos o mas no adivina el primero", () => {
        assert.strictEqual(pickSoleTarget([{label: "a"}, {label: "b"}]), undefined);
        assert.strictEqual(pickSoleTarget([{label: "a"}, {label: "b"}, {label: "c"}]), undefined);
    });
});
