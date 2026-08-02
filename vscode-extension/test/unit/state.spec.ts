import * as assert from "node:assert";
import { situationForExitCode } from "../../src/review/situation";

describe("situationForExitCode", () => {
	it("0 -> review", () => {
		assert.strictEqual(situationForExitCode(0), "review");
	});

	it("2 -> no-review", () => {
		assert.strictEqual(situationForExitCode(2), "no-review");
	});

	it("3 -> out-of-range", () => {
		assert.strictEqual(situationForExitCode(3), "out-of-range");
	});

	it("1 -> error", () => {
		assert.strictEqual(situationForExitCode(1), "error");
	});

	it("un exit code desconocido (>3) -> error, nunca review", () => {
		assert.strictEqual(situationForExitCode(4), "error");
		assert.strictEqual(situationForExitCode(127), "error");
	});

	it("null (proceso no corrio) -> error", () => {
		assert.strictEqual(situationForExitCode(null), "error");
	});
});
