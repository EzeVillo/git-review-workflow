import * as assert from "node:assert";
import {draftWatchDirs,isReportedGuide} from "../../src/review/draftWatch";
describe("comments reported paths",()=>{
    it("watches both document parents and accepts only exact saves",()=>{
        const state={comments:{documents:[{path:"/git/session/local.md"},{path:"/git/result/shared.md"}]}};
        assert.deepStrictEqual(draftWatchDirs(state),["/git/result","/git/session"]);
        assert.strictEqual(isReportedGuide(state,"/git/session/local.md"),true);
        assert.strictEqual(isReportedGuide(state,"/git/session/other.md"),false);
        assert.deepStrictEqual(draftWatchDirs({comments:{documents:[]}}),[]);
    });
});
