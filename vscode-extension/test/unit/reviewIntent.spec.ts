import * as assert from "node:assert";
import {intentToArgs, ReviewIntent} from "../../src/review/reviewIntent";

const BASE: ReviewIntent = {branch: "feature/checkout", layout: "auto", range: "full", source: "remote"};

describe("intentToArgs", () => {
    it("layout auto no agrega ningun flag de layout", () => {
        const args = intentToArgs(BASE, "develop");
        assert.deepStrictEqual(args, ["--", "feature/checkout"]);
    });

    it("layout step agrega --step", () => {
        const args = intentToArgs({...BASE, layout: "step"}, "develop");
        assert.deepStrictEqual(args, ["--step", "--", "feature/checkout"]);
    });

    it("layout no-walk agrega --no-walk", () => {
        const args = intentToArgs({...BASE, layout: "no-walk"}, "develop");
        assert.deepStrictEqual(args, ["--no-walk", "--", "feature/checkout"]);
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
        const args = intentToArgs({layout: "auto", range: "full", source: "remote"}, "develop");
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
        const args = intentToArgs({branch: "-weird", layout: "no-walk", range: "delta", source: "offline"}, "develop");
        assert.deepStrictEqual(args, ["--no-walk", "--delta", "--offline", "--", "-weird"]);
    });
});
