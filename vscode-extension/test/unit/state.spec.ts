import * as assert from "node:assert";
import { situationFor, situationForExitCode } from "../../src/review/situation";

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

// T042 (005 US3): la derivación ampliada con el registro `finish`
// (contracts/finish-state.md). `state.spec.ts` sigue siendo el dueño de la
// derivación de `Situation`, aunque la función viva en situation.ts junto a
// situationForExitCode.
describe("situationFor", () => {
	it("exit 0 con un registro finish conflict resuelve a finish-conflict, aunque el exit sea 0", () => {
		assert.strictEqual(situationFor(0, true, false), "finish-conflict");
	});

	it("exit 2 con el inventario reportando un finish pending resuelve a finish-pending", () => {
		assert.strictEqual(situationFor(2, false, true), "finish-pending");
	});

	it("sin ninguno de los dos registros, el comportamiento de antes de esta feature no cambia", () => {
		assert.strictEqual(situationFor(0, false, false), "review");
		assert.strictEqual(situationFor(2, false, false), "no-review");
		assert.strictEqual(situationFor(3, false, false), "out-of-range");
		assert.strictEqual(situationFor(1, false, false), "error");
		assert.strictEqual(situationFor(null, false, false), "error");
	});

	it("finish-conflict solo aplica sobre exit 0: un finish pending en otra review no lo cambia", () => {
		assert.strictEqual(situationFor(0, false, true), "review");
	});

	it("finish-pending solo aplica sobre exit 2: un finish conflict no cambia out-of-range/error/cli-*", () => {
		assert.strictEqual(situationFor(3, false, true), "out-of-range");
		assert.strictEqual(situationFor(1, false, true), "error");
		assert.strictEqual(situationFor(2, true, false), "no-review");
	});
});
