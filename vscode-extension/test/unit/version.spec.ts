import * as assert from "node:assert";
import { compareVersions, isOutdated, MIN_CLI_VERSION } from "../../src/cli/version";

describe("compareVersions", () => {
	it("igual", () => {
		assert.strictEqual(compareVersions("0.4.0", "0.4.0"), 0);
	});

	it("menor en major", () => {
		assert.ok((compareVersions("0.4.0", "1.0.0") as number) < 0);
	});

	it("menor en minor", () => {
		assert.ok((compareVersions("0.3.9", "0.4.0") as number) < 0);
	});

	it("menor en patch", () => {
		assert.ok((compareVersions("0.4.0", "0.4.1") as number) < 0);
	});

	it("mayor", () => {
		assert.ok((compareVersions("0.5.0", "0.4.0") as number) > 0);
	});

	it("formato inválido devuelve undefined", () => {
		assert.strictEqual(compareVersions("not-a-version", "0.4.0"), undefined);
		assert.strictEqual(compareVersions("0.4", "0.4.0"), undefined);
	});
});

describe("isOutdated", () => {
	it("false para la versión mínima exacta", () => {
		assert.strictEqual(isOutdated(MIN_CLI_VERSION), false);
		assert.strictEqual(MIN_CLI_VERSION, "0.7.0");
	});

	it("true para una versión menor (incluye 0.5.x)", () => {
		assert.strictEqual(isOutdated("0.2.1"), true);
		assert.strictEqual(isOutdated("0.3.0"), true);
		assert.strictEqual(isOutdated("0.3.9"), true);
		assert.strictEqual(isOutdated("0.4.0"), true);
		assert.strictEqual(isOutdated("0.4.9"), true);
		assert.strictEqual(isOutdated("0.5.0"), true);
		assert.strictEqual(isOutdated("0.5.9"), true);
		assert.strictEqual(isOutdated("0.6.0"), true);
		assert.strictEqual(isOutdated("0.6.9"), true);
	});

	it("false para una versión mayor", () => {
		assert.strictEqual(isOutdated("0.7.1"), false);
	});

	it("true para formato inválido", () => {
		assert.strictEqual(isOutdated("garbage"), true);
	});
});
