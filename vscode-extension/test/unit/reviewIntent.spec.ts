import * as assert from "node:assert";
import {deltaForSource, parseConfigPorcelain} from "../../src/cli/configPorcelain";
import {intentToArgs, ReviewIntent, validateIntent} from "../../src/review/reviewIntent";

const BASE: ReviewIntent = {
    branch: "feature/checkout",
    layout: "walk",
    range: "full",
    source: "remote"
};

/**
 * Cadena real del asistente: porcelain → deltaForSource(source) → validateIntent.
 * Sin esto, un test de validateIntent a solas no prueba el bug (filtrar el
 * marker del origen equivocado ocurre antes de validar).
 */
function intentFromPorcelain(
    stdout: string,
    source: ReviewIntent["source"],
    range: ReviewIntent["range"] = "delta"
): {
    intent: ReviewIntent;
    check: ReturnType<typeof validateIntent>;
    delta: ReturnType<typeof deltaForSource>
} {
    const deltas = parseConfigPorcelain(stdout).deltas;
    const delta = deltaForSource(deltas, source);
    const intent: ReviewIntent = {branch: "feature/checkout", layout: "walk", range, source};
    return {intent, check: validateIntent(intent, {delta}), delta};
}

describe("validateIntent", () => {
    it("range delta without a delta present is rejected", () => {
        const result = validateIntent({...BASE, range: "delta"}, {});
        assert.strictEqual(result.ok, false);
        if (!result.ok) {
            assert.match(result.reason, /delta/i);
            assert.match(result.reason, /source/i);
        }
    });

    it("range delta with a delta present is accepted", () => {
        const result = validateIntent(
            {...BASE, range: "delta"},
            {delta: {name: "feature/checkout", tip: "abc123def456", origin: "remote"}}
        );
        assert.strictEqual(result.ok, true);
    });

    it("range full is accepted without a delta", () => {
        const result = validateIntent(BASE, {});
        assert.strictEqual(result.ok, true);
    });

    it("range full is accepted even when a delta is present", () => {
        const result = validateIntent(BASE, {
            delta: {name: "feature/checkout", tip: "abc123def456", origin: "remote"},
        });
        assert.strictEqual(result.ok, true);
    });

    it("range delta for offline is accepted when the local origin marker is present", () => {
        const result = validateIntent(
            {...BASE, range: "delta", source: "offline"},
            {delta: {name: "feature/checkout", tip: "abc123def456", origin: "local"}}
        );
        assert.strictEqual(result.ok, true);
    });
});

describe("delta x source composition (FR-015)", () => {
    const remoteOnly = [
        "config\tremote\torigin",
        "delta\tfeature/checkout\tabc123def456\tremote",
        "",
    ].join("\n");
    const localOnly = [
        "config\tremote\torigin",
        "delta\tfeature/checkout\tfedcba654321\tlocal",
        "",
    ].join("\n");
    const both = [
        "config\tremote\torigin",
        "delta\tfeature/checkout\tabc123def456\tremote",
        "delta\tfeature/checkout\tfedcba654321\tlocal",
        "",
    ].join("\n");

    it("remote-only marker does not enable offline or local --delta", () => {
        for (const source of ["offline", "local"] as const) {
            const {check, delta} = intentFromPorcelain(remoteOnly, source);
            assert.strictEqual(delta, undefined, `source=${source} must not see the remote marker`);
            assert.strictEqual(check.ok, false, `source=${source} + range delta must be rejected`);
        }
    });

    it("remote-only marker enables remote --delta with that tip", () => {
        const {check, delta} = intentFromPorcelain(remoteOnly, "remote");
        assert.deepStrictEqual(delta, {
            name: "feature/checkout",
            tip: "abc123def456",
            origin: "remote",
        });
        assert.strictEqual(check.ok, true);
    });

    it("local-only marker does not enable remote --delta", () => {
        const {check, delta} = intentFromPorcelain(localOnly, "remote");
        assert.strictEqual(delta, undefined);
        assert.strictEqual(check.ok, false);
        if (!check.ok) {
            assert.match(check.reason, /delta/i);
        }
    });

    it("local-only marker enables offline and local --delta with that tip", () => {
        for (const source of ["offline", "local"] as const) {
            const {check, delta} = intentFromPorcelain(localOnly, source);
            assert.deepStrictEqual(delta, {
                name: "feature/checkout",
                tip: "fedcba654321",
                origin: "local",
            });
            assert.strictEqual(check.ok, true, `source=${source}`);
        }
    });

    it("when both markers exist, each source binds to its own tip (never the other)", () => {
        const remote = intentFromPorcelain(both, "remote");
        assert.deepStrictEqual(remote.delta?.tip, "abc123def456");
        assert.strictEqual(remote.delta?.origin, "remote");
        assert.strictEqual(remote.check.ok, true);

        const offline = intentFromPorcelain(both, "offline");
        assert.deepStrictEqual(offline.delta?.tip, "fedcba654321");
        assert.strictEqual(offline.delta?.origin, "local");
        assert.strictEqual(offline.check.ok, true);
    });

    it("range full stays legal even when the chosen source has no marker", () => {
        const {check, delta} = intentFromPorcelain(remoteOnly, "offline", "full");
        assert.strictEqual(delta, undefined);
        assert.strictEqual(check.ok, true);
    });
});

describe("intentToArgs", () => {
    it("layout walk no agrega ningun flag de layout", () => {
        const args = intentToArgs(BASE, "develop");
        assert.deepStrictEqual(args, ["--", "feature/checkout"]);
    });

    it("layout step agrega --step", () => {
        const args = intentToArgs({...BASE, layout: "step"}, "develop");
        assert.deepStrictEqual(args, ["--step", "--", "feature/checkout"]);
    });

    it("layout whole agrega --no-walk", () => {
        const args = intentToArgs({...BASE, layout: "whole"}, "develop");
        assert.deepStrictEqual(args, ["--no-walk", "--", "feature/checkout"]);
    });

    it("layout keys agrega --keys", () => {
        const args = intentToArgs({...BASE, layout: "keys"}, "develop");
        assert.deepStrictEqual(args, ["--keys", "--", "feature/checkout"]);
    });

    it("source local agrega --local", () => {
        const args = intentToArgs({...BASE, source: "local"}, "develop");
        assert.deepStrictEqual(args, ["--local", "--", "feature/checkout"]);
    });

    it("source offline agrega --offline", () => {
        const args = intentToArgs({...BASE, source: "offline"}, "develop");
        assert.deepStrictEqual(args, ["--offline", "--", "feature/checkout"]);
    });

    it("range delta agrega --delta", () => {
        const args = intentToArgs({...BASE, range: "delta"}, "develop");
        assert.deepStrictEqual(args, ["--delta", "--", "feature/checkout"]);
    });

    it("nunca agrega --base, --from ni el <base> posicional", () => {
        const args = intentToArgs(
            {branch: "feature/checkout", layout: "step", range: "delta", source: "local"},
            "develop"
        );
        assert.ok(!args.includes("--base"));
        assert.ok(!args.includes("--from"));
        assert.ok(!args.includes("develop"));
    });

    it("sin branch cae al currentBranch dado", () => {
        const args = intentToArgs({layout: "walk", range: "full", source: "remote"}, "develop");
        assert.deepStrictEqual(args, ["--", "develop"]);
    });

    it("U1: una rama llamada -foo produce [..., '--', '-foo'], con -- justo antes del nombre", () => {
        const args = intentToArgs({...BASE, branch: "-foo", layout: "step"}, "develop");
        assert.deepStrictEqual(args, ["--step", "--", "-foo"]);
        // el -- va inmediatamente antes del nombre y despues de todos los flags:
        // el nombre nunca aparece en una posicion donde la CLI pudiera leerlo
        // como opcion.
        const dashIndex = args.indexOf("--");
        assert.strictEqual(dashIndex, args.length - 2);
        assert.strictEqual(args[args.length - 1], "-foo");
    });

    it("todos los flags posibles van antes del --, en el mismo orden en cualquier combinacion", () => {
        const args = intentToArgs({
            branch: "-weird",
            layout: "whole",
            range: "delta",
            source: "offline"
        }, "develop");
        assert.deepStrictEqual(args, ["--no-walk", "--delta", "--offline", "--", "-weird"]);
    });
});
