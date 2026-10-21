import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import {parseComments} from "../../src/cli/commentsPorcelain";
import {commentsOwnedBy} from "../../src/review/commentsFlow";
describe("shared comments fixture", () => {
    it("consumes all wire tags and saves only the selected session's Markdown", () => {
        let root=__dirname;
        while (!fs.existsSync(path.join(root,"tests/fixtures/comments/client-records.tsv"))) {const parent=path.dirname(root);assert.notStrictEqual(parent,root);root=parent;}
        const report=parseComments(fs.readFileSync(path.join(root,"tests/fixtures/comments/client-records.tsv"),"utf8"));
        assert.strictEqual(report.documents.length,4);
        assert.strictEqual(report.documents[0].count,undefined);assert.strictEqual(report.documents[1].count,0);
        const tags=new Set(report.rows.map(r=>r.tag));
        for (const tag of ["comments-owner","comments-context","comments-guard","comments-document","comments-count","comments-diagnostic","comments-identity","comments-candidate","comments-delivery","comments-capture","comment-entry","comment-body","comment-scope","comment-version","comment-path","comment-location","comment-unversioned","comment-diagnostic","comment-diff","comment-blob","comments-delivery-file"]) assert.ok(tags.has(tag),tag);
        assert.ok(!tags.has("future-tag"));
        assert.deepStrictEqual(commentsOwnedBy(report,["review/feature/comments"]).map(d=>d.path),["/private/local.md","/private/shared.md"]);
        assert.deepStrictEqual(commentsOwnedBy(report,["review/other"]),[]);
        assert.strictEqual(report.rows.find(r=>r.tag==="comment-path")?.fields[2],"old%2525name");
    });
});
