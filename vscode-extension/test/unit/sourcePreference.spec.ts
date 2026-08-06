import * as assert from "node:assert";
import {resolveDefaultSource} from "../../src/review/sourcePreference";

describe("resolveDefaultSource", () => {
    it("workspace local beats user remote: effective value is local", () => {
        // Models what the assistant reads after the host resolves scopes:
        // workspace value wins over user (global) value (FR-016a).
        assert.strictEqual(
            resolveDefaultSource({workspaceValue: "local", globalValue: "remote"}),
            "local"
        );
    });

    it("without any setting the effective value is remote", () => {
        assert.strictEqual(resolveDefaultSource({}), "remote");
    });

    it("user remote alone yields remote", () => {
        assert.strictEqual(resolveDefaultSource({globalValue: "remote"}), "remote");
    });

    it("user offline alone yields offline", () => {
        assert.strictEqual(resolveDefaultSource({globalValue: "offline"}), "offline");
    });

    it("workspace offline beats user local", () => {
        assert.strictEqual(
            resolveDefaultSource({workspaceValue: "offline", globalValue: "local"}),
            "offline"
        );
    });

    it("an unknown value falls back to remote", () => {
        assert.strictEqual(resolveDefaultSource({globalValue: "somewhere-else"}), "remote");
        assert.strictEqual(resolveDefaultSource({workspaceValue: ""}), "remote");
    });
});
