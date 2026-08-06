import * as assert from "node:assert";
import {parseListPorcelain} from "../../src/cli/porcelain";
import {
    argsForHousekeeping,
    confirmCopyFor,
    housekeepingNeedsNetwork,
    pendingFinishInfo,
    pendingFinishSource,
    sourceFromReviewName,
    verbForHousekeeping,
} from "../../src/review/housekeeping";
import type {ReviewState} from "../../src/review/state";

describe("sourceFromReviewName", () => {
    it("strips review-saved/ review/ review-fixes/", () => {
        assert.strictEqual(sourceFromReviewName("review-saved/feature/x"), "feature/x");
        assert.strictEqual(sourceFromReviewName("review/feature/x"), "feature/x");
        assert.strictEqual(sourceFromReviewName("review-fixes/feature/x"), "feature/x");
        assert.strictEqual(sourceFromReviewName("feature/x"), "feature/x");
    });
});

describe("pendingFinishSource", () => {
    function stateWith(
        situation: ReviewState["situation"],
        listStdout: string
    ): ReviewState {
        return {
            situation,
            entries: [],
            branches: parseListPorcelain(listStdout),
        };
    }

    const PENDING_LIST = [
        "branch\treview/feature/shipping\t0\t0\t0\twhole",
        "finish\treview/feature/shipping\tpending\t0",
        "branch\treview-saved/other\t1\t0\t0\tstep\t1\t2",
        "",
    ].join("\n");

    it("en finish-pending devuelve el source del pending, no el HEAD ni otra fila", () => {
        // No mira la rama actual: el source sale del registro finish pending
        // del inventario (mismo criterio que list --porcelain / abort resiliente).
        assert.strictEqual(
            pendingFinishSource(stateWith("finish-pending", PENDING_LIST)),
            "feature/shipping"
        );
    });

    it("ignora filas finish conflict y filas de otro source", () => {
        const list = [
            "branch\treview/feature/a\t0\t0\t0\twhole",
            "finish\treview/feature/a\tconflict\t0",
            "branch\treview/feature/b\t0\t0\t0\twhole",
            "finish\treview/feature/b\tpending\t1",
            "",
        ].join("\n");
        assert.strictEqual(pendingFinishSource(stateWith("finish-pending", list)), "feature/b");
    });

    it("ausente fuera de finish-pending aunque el inventario tenga pending", () => {
        assert.strictEqual(pendingFinishSource(stateWith("no-review", PENDING_LIST)), undefined);
        assert.strictEqual(pendingFinishSource(stateWith("review", PENDING_LIST)), undefined);
        assert.strictEqual(
            pendingFinishSource(stateWith("finish-conflict", PENDING_LIST)),
            undefined
        );
    });

    it("ausente en finish-pending sin fila pending (no inventa un source)", () => {
        const list = "branch\treview/feature/shipping\t0\t0\t0\twhole\n";
        assert.strictEqual(pendingFinishSource(stateWith("finish-pending", list)), undefined);
    });

    it("confirm clean-one nombra review/ y review-fixes/ y no el delta", () => {
        const c = confirmCopyFor({kind: "clean-one", source: "feature/shipping"});
        assert.strictEqual(c.button, "Clean");
        assert.ok(c.title.includes("feature/shipping"));
        assert.ok(c.detail.includes("review/feature/shipping"));
        assert.ok(c.detail.includes("review-fixes/feature/shipping"));
        assert.ok(
            c.detail.toLowerCase().includes("delta"),
            "tiene que decir que el delta no se toca"
        );
        assert.ok(
            /does not touch|not touch/i.test(c.detail),
            "tiene que afirmar que el delta queda"
        );
    });

    it("confirm clean-keep-fixes sin onto nombra review-fixes y pide commit/push", () => {
        const c = confirmCopyFor({kind: "clean-keep-fixes", source: "feature/shipping"});
        assert.strictEqual(c.button, "Clean");
        assert.ok(c.detail.includes("--keep-fixes"));
        assert.ok(c.detail.includes("review/feature/shipping"));
        assert.ok(
            c.detail.includes("review-fixes/feature/shipping"),
            "sin onto las edits staged viven en review-fixes"
        );
        assert.ok(
            !c.detail.includes("stay on feature/shipping;"),
            "sin onto no debe nombrar la rama del PR como destino de las edits"
        );
        assert.ok(
            /commit and push/i.test(c.detail),
            "tiene que recordar commitear y pushear"
        );
        assert.ok(
            !/Deletes review\/feature\/shipping and review-fixes/i.test(c.detail),
            "no debe prometer borrar review-fixes"
        );
    });

    it("confirm clean-keep-fixes con onto nombra la rama del PR, no review-fixes", () => {
        const c = confirmCopyFor({
            kind: "clean-keep-fixes",
            source: "feature/shipping",
            onto: true,
        });
        assert.strictEqual(c.button, "Clean");
        assert.ok(c.detail.includes("review/feature/shipping"));
        assert.ok(
            c.detail.includes("feature/shipping"),
            "con onto las edits staged viven en la rama del PR"
        );
        assert.ok(
            /stay on feature\/shipping/i.test(c.detail),
            "tiene que decir que las edits se quedan en la rama del PR"
        );
        assert.ok(
            !c.detail.includes("review-fixes/feature/shipping"),
            "con onto no debe inventar review-fixes como destino de las edits"
        );
        assert.ok(/commit and push/i.test(c.detail), "tiene que recordar commitear y pushear");
    });

    it("pendingFinishInfo devuelve source y onto del pending", () => {
        const list = [
            "branch\treview/feature/shipping\t0\t0\t0\twhole",
            "finish\treview/feature/shipping\tpending\t1",
            "",
        ].join("\n");
        assert.deepStrictEqual(pendingFinishInfo(stateWith("finish-pending", list)), {
            source: "feature/shipping",
            onto: true,
        });
        assert.strictEqual(pendingFinishInfo(stateWith("no-review", list)), undefined);
    });
});

describe("argsForHousekeeping", () => {
    it("maps each kind to the closed arg list", () => {
        assert.deepStrictEqual(argsForHousekeeping({kind: "clean-one", source: "f/x"}), ["f/x"]);
        assert.deepStrictEqual(argsForHousekeeping({kind: "clean-keep-fixes", source: "f/x"}), [
            "--keep-fixes",
            "f/x",
        ]);
        assert.deepStrictEqual(argsForHousekeeping({kind: "clean-all"}), []);
        assert.deepStrictEqual(argsForHousekeeping({kind: "forget-saved-one", source: "f/x"}), [
            "--saved",
            "f/x",
        ]);
        assert.deepStrictEqual(argsForHousekeeping({kind: "forget-saved-all"}), ["--saved", "--all"]);
        assert.deepStrictEqual(argsForHousekeeping({kind: "forget-delta-one", source: "f/x"}), [
            "--delta",
            "f/x",
        ]);
        assert.deepStrictEqual(argsForHousekeeping({kind: "forget-delta-all"}), ["--delta", "--all"]);
        assert.deepStrictEqual(argsForHousekeeping({kind: "forget-delta-stale"}), [
            "--delta",
            "--stale",
        ]);
    });

    it("verbs are clean or forget only", () => {
        assert.strictEqual(verbForHousekeeping({kind: "clean-all"}), "clean");
        assert.strictEqual(verbForHousekeeping({kind: "clean-keep-fixes", source: "f/x"}), "clean");
        assert.strictEqual(verbForHousekeeping({kind: "forget-saved-all"}), "forget");
    });

    it("only forget-delta-stale needs network", () => {
        assert.strictEqual(housekeepingNeedsNetwork({kind: "forget-delta-stale"}), true);
        assert.strictEqual(housekeepingNeedsNetwork({kind: "forget-delta-all"}), false);
        assert.strictEqual(housekeepingNeedsNetwork({kind: "clean-all"}), false);
    });

    it("confirm copy names the effect", () => {
        const c = confirmCopyFor({kind: "forget-saved-one", source: "feat"});
        assert.ok(c.title.includes("feat"));
        assert.ok(c.detail.includes("review-saved"));
        assert.strictEqual(c.button, "Discard");
    });
});
