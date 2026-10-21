import * as assert from "node:assert";
import {commentsArgs, commentDestinations, saveCommentBuffers, selectionLines, selectionCoordinates, commentRangeEndpoints} from "../../src/review/commentsFlow";
import {parseComments} from "../../src/cli/commentsPorcelain";
describe("comments flow", () => {
    it("uses only the CLI capture capabilities regardless of document presence or context kind", () => {
        const report = parseComments("comments-capability\tinit\tshared\ncomments-capability\tadd\tshared\ncomments-capability\tadd\tshared\ncomments-capability\tadd\tunknown\ncomments-capability\tadd\ncomments-context\tc\tcompare\tactive\tg\tCompare\ncomments-document\t/local\tc\tlocal\tpresent\tr");
        assert.deepStrictEqual(commentDestinations(report), ["shared"]);
        assert.deepStrictEqual(commentDestinations(parseComments("comments-guard\tg")), []);
    });
    it("round trips partial and reversed UTF16 selections including next line column zero", () => {
        for (const [anchor, active, expected] of [
            [{line: 0, character: 1}, {line: 0, character: 3}, "😀"],
            [{line: 1, character: 0}, {line: 0, character: 1}, "😀\tZ\n"],
        ] as const) {
            const text = "a😀\tZ\nlast";
            const lines = text.split("\n");
            const capture = selectionCoordinates(anchor, active);
            const wire = `comment-location\t1\thead\t${capture.start}\t${capture.end}\ncomment-columns\t1\thead\t${capture.startColumn}\t${capture.endColumn}`;
            const [start, end] = commentRangeEndpoints(parseComments(wire).locations[0], lines.map(l => l.length));
            const offset = (p: {line: number; character: number}) => lines.slice(0, p.line).reduce((n, line) => n + line.length + 1, 0) + p.character;
            assert.strictEqual(text.slice(offset(start), offset(end)), expected);
        }
        assert.deepStrictEqual(commentRangeEndpoints({start: 1, end: 1}, [5]), [{line: 0, character: 0}, {line: 0, character: 5}]);
        assert.throws(() => commentRangeEndpoints({start: 1, end: 1, startColumn: 2, endColumn: 9}, [5]));
        assert.throws(() => commentRangeEndpoints({start: 1, end: 1, startColumn: 2}, [5]));
    });
    const wire = "comments-guard\tstep1\ncomments-context\tc1\treview\tactive\tstep1\tFeature\ncomments-document\t/l\tc1\tlocal\tpresent\tr1\ncomments-document\t/s\tc1\tshared\tabsent\tabsent";
    it("sends independent byte guards and physical ordinal", () => {
        const report = parseComments(wire);
        assert.deepStrictEqual(commentsArgs(report, "diff", "local", "c1", 3), ["diff", "--document", "local", "--context", "c1", "--expect-context", "step1", "--expect-document", "r1", "--entry", "3"]);
        assert.deepStrictEqual(commentsArgs(report, "save"), ["save", "--expect-context", "step1", "--expect-local", "r1", "--expect-shared", "absent"]);
        assert.throws(() => commentsArgs(parseComments(wire.replace("r1", "unreadable")), "renumber", "local"));
    });
    it("normalizes reversed selection, zero column end, and caret", () => {
        assert.deepStrictEqual(selectionLines({line: 5, character: 0}, {line: 2, character: 4}), [3, 5]);
        assert.deepStrictEqual(selectionLines({line: 2, character: 4}, {line: 2, character: 4}), [3, 3]);
    });
    for (const failure of ["false", "throw", "dirty"]) it("stops selective saving on " + failure, async () => {
        let secondSaved = false;
        const first = {isDirty: true, save: async () => {if (failure === "throw") throw Error("disk"); first.isDirty = failure === "dirty"; return failure !== "false";}};
        assert.strictEqual(await saveCommentBuffers([first, {isDirty: true, save: async () => {secondSaved = true; return true;}}]), false);
        assert.strictEqual(secondSaved, false);
    });
});
