import * as assert from "node:assert";
import {parsePorcelain} from "../../src/cli/porcelain";
import {buildPanelModel} from "../../src/views/panelModel";
import {panelHtml} from "../../src/views/panelHtml";
import {Script} from "node:vm";

describe("Comparison context", () => {
    for (const mode of ["whole", "walk", "step"] as const) {
        it(`projects both pinned endpoints in ${mode}`, () => {
            const parsed = parsePorcelain([
                `state\treview/feature\tfeature\t${"2".repeat(40)}\t${mode}\tnone\t1\t1\t1\tapp.txt\t0`,
                "comparison-target\trefs/remotes/upstream/feature",
                `comparison\t${"1".repeat(40)}\t${"2".repeat(40)}`,
                "comparison-base\trefs/heads/main",
            ].join("\n"));
            const model = buildPanelModel({situation: "review", state: parsed.state, entries: parsed.entries, files: parsed.files, branches: [], comparison: parsed.comparison}, {busy: false});
            assert.deepStrictEqual(model.comparison, {baseOid: "1".repeat(40), targetOid: "2".repeat(40), baseLabel: "refs/heads/main", targetLabel: "refs/remotes/upstream/feature"});
        });
    }
    it("does not invent an incomplete comparison", () => {
        const state = "state\treview/f\tf\tabc\twhole\tnone\n";
        for (const rest of ["", "comparison\tbad\tbad\ncomparison-base\tmain\ncomparison-target\tf", `comparison\t${"1".repeat(40)}\t${"2".repeat(40)}`]) {
            assert.strictEqual(parsePorcelain(state + rest).comparison, undefined);
        }
    });
    it("emits valid JavaScript for the comparison panel", () => {
        const script = panelHtml("test").match(/<script[^>]*>([\s\S]*?)<\/script>/)![1];
        assert.doesNotThrow(() => new Script(script));
    });
});

import {COMPARE_COPY, comparisonSummary, compareBasePrompt} from "../../src/review/userCopy";
describe("Compare UX", () => {
    it("keeps the selected revision visible and ref names literal", () => {
        assert.strictEqual(compareBasePrompt("refs/heads/{target}$&"), "Reviewing {target}$&.");
        assert.strictEqual(comparisonSummary("refs/heads/main", "refs/remotes/upstream/f"), "Review upstream/f against main");
        assert.strictEqual(COMPARE_COPY.targetTitle, "What do you want to review?");
        assert.strictEqual(COMPARE_COPY.baseTitle, "Compare against what?");
    });
    it("keeps Compare accessible before base configuration", () => {
        const html = panelHtml("test");
        const setup = html.slice(html.indexOf("function renderSetup("), html.indexOf("function renderEmptyStartBlock("));
        assert.ok(setup.includes("renderCompareSection(model)"));
        assert.ok(!html.includes("finish will refuse"));
    });
});
