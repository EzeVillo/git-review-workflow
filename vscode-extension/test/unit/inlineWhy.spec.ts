import * as assert from "node:assert";
import {parseInlineWhy} from "../../src/review/navigationReply";

describe("inline navigation prose", () => {
    it("decodes bytes once and preserves empty lines and Unicode", () => {
        const output = "why\tpresent\t3\nwhy-line\t1\tcafé \\t \\\\n\nwhy-line\t2\t\nwhy-line\t3\tA\\rB  \n";
        assert.strictEqual(parseInlineWhy(output),"café \t \\n\n\nA\rB  \n");
        assert.strictEqual(parseInlineWhy("why\tabsent\t0\n"),"");
    });
    it("keeps absent capabilities and malformed or truncated prose unknown", () => {
        for (const output of ["", "why\tabsent\t1", "why\tpresent\t0", "why\tpresent\t2\nwhy-line\t1\tone",
            "why\tpresent\t1\nwhy-line\t2\tone", "why\tpresent\t1\nwhy-line\t1\tbad\\x",
            "why\tpresent\t1\nwhy-line\t1\tbad\\", "why\tabsent\t0\nwhy\tabsent\t0"])
            assert.strictEqual(parseInlineWhy(output),undefined,output);
    });
});
