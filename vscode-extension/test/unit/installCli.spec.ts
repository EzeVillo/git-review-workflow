import * as assert from "node:assert/strict";
import {
    NPM_INSTALL_CMD,
    NPM_UPDATE_CMD,
    npmCommandFor,
} from "../../src/cli/installHint";

describe("npmCommandFor", () => {
    it("resuelve install y update a los comandos npm globales", () => {
        assert.strictEqual(npmCommandFor("install"), NPM_INSTALL_CMD);
        assert.strictEqual(npmCommandFor("update"), NPM_UPDATE_CMD);
        assert.strictEqual(NPM_INSTALL_CMD, "npm install -g git-review-workflow");
        assert.strictEqual(NPM_UPDATE_CMD, "npm install -g git-review-workflow@latest");
    });
});
