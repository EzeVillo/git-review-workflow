import * as assert from "node:assert";
import {parseComments} from "../../src/cli/commentsPorcelain";
import {presentComment} from "../../src/review/commentPresentation";

describe("comment presentation", () => {
    it("keeps multiline prose and literal escapes separate from the original location", () => {
        const report = parseComments("comment-entry\t2\t7\t4\tsame.txt\ncomment-scope\t2\tselection\tbase\ncomment-path\t2\tbase\told%25name\ncomment-location\t2\tbase\t3\t5\ncomment-version\t2\tabcdef123456\t123456abcdef\ncomment-body\t2\t    100%25 with %2509\ncomment-body\t2\t\ncomment-body\t2\tSecond%09paragraph");
        const view = presentComment(report, report.entries[0]);
        assert.strictEqual(view.body, "    100% with %09\n\nSecond\tparagraph");
        assert.strictEqual(view.location, "old%name:3–5 · Previous version");
        assert.strictEqual(view.ordinal, 2);
        assert.strictEqual(view.canOpenDiff, true);
        assert.strictEqual(view.label, "7. same.txt · old%name:3–5 · Previous version");
        assert.strictEqual(view.version, "Original changes · abcdef12 → 123456ab");
    });
    it("does not invent a location for manually authored entries", () => {
        const report = parseComments("comment-entry\t1\t1\t1\tManual\ncomment-entry\t2\t1\t4\tGeneral\ncomment-scope\t2\tgeneral\t\ncomment-body\t2\tWhole review");
        assert.strictEqual(presentComment(report, report.entries[0]).location, "Location unavailable");
        assert.strictEqual(presentComment(report, report.entries[1]).location, "General comment");
        assert.strictEqual(presentComment(report, report.entries[0]).canOpenDiff, false);
        assert.strictEqual(presentComment(report, report.entries[1]).canOpenDiff, false);
        assert.strictEqual(presentComment(report, report.entries[1]).body, "Whole review");
    });
    it("keeps the full comment, marks a long Unicode preview, and separates warnings from history", () => {
        const body = "🙂".repeat(161);
        const report = parseComments("comment-entry\t1\t1\t1\tsrc/file.ts\ncomment-scope\t1\tselection\thead\ncomment-path\t1\thead\tsrc/file.ts\ncomment-location\t1\thead\t3\t7\ncomment-version\t1\tabcdef123456\t123456abcdef\ncomment-unversioned\t1\ncomment-body\t1\t" + body);
        const view = presentComment(report, report.entries[0]);
        assert.strictEqual(view.body, body);
        assert.strictEqual(view.preview, "🙂".repeat(159) + "…");
        assert.strictEqual(view.label, "1. src/file.ts:3–7 · New version");
        assert.strictEqual(view.version, "Original changes · abcdef12 → 123456ab");
        assert.strictEqual(view.warning, "The captured lines included unsaved changes; this view shows the recorded Git version.");
    });
});
