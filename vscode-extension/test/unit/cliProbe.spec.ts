import * as assert from "node:assert";
import {CLI_PROBE_INTERVAL_MS, shouldProbeCli} from "../../src/review/cliProbe";
import type {Situation} from "../../src/review/situation";

describe("shouldProbeCli", () => {
    it("solo en cli-missing o cli-outdated con el panel visible", () => {
        assert.strictEqual(shouldProbeCli("cli-missing", true), true);
        assert.strictEqual(shouldProbeCli("cli-outdated", true), true);
    });

    it("no sondea si el panel no es visible", () => {
        assert.strictEqual(shouldProbeCli("cli-missing", false), false);
        assert.strictEqual(shouldProbeCli("cli-outdated", false), false);
    });

    it("no sondea en ninguna otra situacion, aunque el panel este abierto", () => {
        const others: Situation[] = [
            "review",
            "no-review",
            "out-of-range",
            "error",
            "finish-conflict",
            "finish-pending",
        ];
        for (const situation of others) {
            assert.strictEqual(
                shouldProbeCli(situation, true),
                false,
                `no debe sondear en ${situation}`,
            );
        }
    });

    it("el intervalo es de 10 segundos", () => {
        assert.strictEqual(CLI_PROBE_INTERVAL_MS, 10_000);
    });
});
