import * as assert from "node:assert";
import {parseComments} from "../../src/cli/commentsPorcelain";

describe("comments records", () => {
    it("keeps readable candidate details and accepts legacy candidates", () => {
        const report = parseComments("comments-candidate\tc1\tfeature\tReview 1 · shared: 2\ncomments-candidate\tc2\tfeature\tReview 2 · shared: 1\ncomments-candidate\tc3\tlegacy");
        assert.deepStrictEqual(report.candidates, [
            {id: "c1", label: "feature", description: "Review 1 · shared: 2"},
            {id: "c2", label: "feature", description: "Review 2 · shared: 1"},
            {id: "c3", label: "legacy"},
        ]);
    });
    const wire = [
        "future-tag\tignored",
        "comments-context\tc1\treview\tactive\tguard1\tFeature",
        "comments-context\tc2\tcompare\tresult\tguard2\tOther",
        "comments-guard\tcapture1",
        "comments-document\t/private/local.md\tc1\tlocal\tpresent\tunreadable",
        "comments-document\t/private/shared.md\tc1\tshared\tabsent\tabsent\textra",
        "comments-diagnostic\t/private/local.md\tread\tCannot read",
        "comments-identity\tambiguous\tChoose",
        "comments-candidate\tc1\tFeature",
        "comments-delivery\tc1\tpending\tDestination changed",
        "comments-capture\tcapture1\tbase1\thead1",
    ].join("\n");
    it("keeps both documents and every context without choosing the newest", () => {
        const report = parseComments(wire);
        assert.deepStrictEqual(report.contexts.map(c => c.id), ["c1", "c2"]);
        assert.deepStrictEqual(report.documents.map(d => [d.kind, d.presence, d.revision, d.count]), [
            ["local", "present", "unreadable", undefined], ["shared", "absent", "absent", undefined],
        ]);
        assert.strictEqual(report.guard, "capture1");
        assert.strictEqual(report.identity, "ambiguous");
        assert.strictEqual(report.diagnostics[0].code, "read");
        assert.strictEqual(report.deliveries[0].state, "pending");
        assert.strictEqual(report.candidates[0].id, "c1");
        assert.strictEqual(report.base, "base1");
        assert.strictEqual(report.head, "head1");
    });
    it("distinguishes a reported zero from an unreadable count", () => {
        const report = parseComments(wire + "\ncomments-count\t/private/shared.md\t0\ncomments-count\t/private/local.md\tbad");
        assert.strictEqual(report.documents[1].count, 0);
        assert.strictEqual(report.documents[0].count, undefined);
    });
    it("keeps physical ordinals and immutable recipe independently from visible numbering", () => {
        const report = parseComments("comment-entry\t2\t7\t12\tRepeated number\ncomment-entry\t1\t7\t2\tFirst\ncomment-diff\t2\tB1\tH1\ncomment-blob\told%25name\tbase\tpresent\tblob1\ncomment-blob\tnew\thead\tabsent\ncomment-location\t2\tbase\t3\t5\ncomments-delivery-file\t/tmp/prepared\tprepared\tpresent\trev");
        assert.deepStrictEqual(report.entries.map(e => [e.ordinal, e.number]), [[2, "7"], [1, "7"]]);
        assert.deepStrictEqual(report.range, {ordinal: 2, base: "B1", head: "H1"});
        assert.deepStrictEqual(report.blobs.map(b => [b.side, b.presence, b.oid]), [["base", "present", "blob1"], ["head", "absent", undefined]]);
        assert.strictEqual(report.locations[0].end, 5);
        assert.strictEqual(report.deliveryFiles[0].role, "prepared");
    });
});
