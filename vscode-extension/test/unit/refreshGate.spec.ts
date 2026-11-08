import * as assert from "node:assert";
import {RefreshGate} from "../../src/review/refreshGate";

describe("mutation-aware watcher refresh", () => {
    it("lets the final primary read cover all earlier mutation signals", () => {
        const gate = new RefreshGate();
        gate.mutationChanged(true);
        for (let i=0;i<4;i++) { gate.request(); assert.strictEqual(gate.tryStart(),false); }
        gate.primaryStarting();
        gate.mutationChanged(false);
        assert.strictEqual(gate.tryStart(),false);
    });
    it("preserves later changes in one followup without parallel reads", () => {
        const gate = new RefreshGate();
        gate.mutationChanged(true);
        gate.primaryStarting();
        for (let i=0;i<4;i++) gate.request();
        assert.strictEqual(gate.tryStart(),false);
        gate.mutationChanged(false);
        assert.strictEqual(gate.tryStart(),true);
        assert.strictEqual(gate.tryStart(),false);
        gate.finished();
        assert.strictEqual(gate.tryStart(),false);
    });
    it("retains queued signals if the mutation exits without a primary read", () => {
        const gate = new RefreshGate();
        gate.request(); gate.mutationChanged(true);
        assert.strictEqual(gate.tryStart(),false);
        gate.mutationChanged(false);
        assert.strictEqual(gate.tryStart(),true);
        gate.request(); gate.mutationChanged(true); gate.finished();
        assert.strictEqual(gate.tryStart(),false);
        gate.mutationChanged(false);
        assert.strictEqual(gate.tryStart(),true);
        gate.request(); assert.strictEqual(gate.tryStart(),false);
        gate.finished(); assert.strictEqual(gate.tryStart(),true);
    });
});
