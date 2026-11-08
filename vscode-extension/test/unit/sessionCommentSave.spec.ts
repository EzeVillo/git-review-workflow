import * as assert from "node:assert";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {runInNewContext} from "node:vm";
import * as ts from "typescript";

function scenario(dirty: boolean, save = true, query = true, unknown = false, modern = false, pathsReply?: string, closing = true) {
    const calls: string[] = [], saved: string[] = [], notices: string[] = [], requests: string[][] = [];
    const guard="a".repeat(40);
    const paths=pathsReply ?? `comments-paths\t1\t${guard}\t${"b".repeat(40)}\ncomments-path\tlocal\t/private.md\ncomments-path\tshared\t/shared.md\ncomments-paths\tcomplete\n`;
    const document = (file: string) => ({uri:{scheme:"file",fsPath:file},isDirty:dirty,save:async function () {saved.push(file);this.isDirty=!save;return save;}});
    const exported: any = {};
    const report = "comments-context\tc\treview\tactive\tg\tCurrent\ncomments-owner\tc\tx\treview/x\ncomments-document\t/private.md\tc\tlocal\tpresent\tr\n"+
        "comments-context\tother\treview\tactive\tg\tOther\ncomments-owner\tother\tother\treview/other\ncomments-document\t/other.md\tother\tlocal\tpresent\tr";
    const documents=[document("/private.md"),document("/other.md"),document("/code.ts")];
    runInNewContext(ts.transpileModule(readFileSync(resolve("src/commands/comments.ts"),"utf8"),
        {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,{
        exports:exported,
        require:(name:string) => {
            if(name.startsWith("node:"))return require(name);
            if(name==="vscode")return {workspace:{get textDocuments(){if(unknown){unknown=false;throw Error("unknown");}return documents;}},window:{showErrorMessage:(text:string)=>notices.push(text)}};
            if(name==="../cli/invoke")return {invokeGitReview:async(verb:string,args:string[])=>{calls.push(verb);requests.push(Array.from(args));return {exitCode:query?0:1,stdout:query?(args[0]==="paths"?paths:report):"",stderr:"query failed"};}};
            if(name==="../review/commentPaths"||name==="../cli/commentsPorcelain"||name==="../review/commentsFlow"||name==="../review/userCopy")return require(resolve("src/commands",name));
            if(name==="../review/draftFlow")return {sameDraftFile:(a:string,b:string)=>a===b};
            return {};
        },
    });
    const manager={state:{situation:"review",guard,commentsPaths:modern,state:{source:"x"}},refreshPrimary:async()=>undefined,refresh:async()=>undefined};
    return {run:()=>exported.saveSessionComments(manager,{cwd:"/repo"},undefined,"all",closing),calls,saved,notices,requests};
}

describe("pre-mutation comment buffers",()=>{
    it("a clean editor needs no CLI inventory or save",async()=>{
        const test=scenario(false);assert.strictEqual(await test.run(),true);assert.deepStrictEqual(test.calls,[]);assert.deepStrictEqual(test.saved,[]);
    });
    it("dirty buffers save only the CLI-owned comment document",async()=>{
        const test=scenario(true);assert.strictEqual(await test.run(),true);assert.deepStrictEqual(test.calls,["comments"]);assert.deepStrictEqual(test.saved,["/private.md"]);
    });
    it("a failed inventory or selective save blocks the action",async()=>{
        for(const test of [scenario(true,false),scenario(true,true,false)]) {
            assert.strictEqual(await test.run(),false);assert.strictEqual(test.notices.length,1);
        }
    });
    it("an unknown editor state keeps the query and selective save",async()=>{
        const test=scenario(true,true,true,true);assert.strictEqual(await test.run(),true);assert.deepStrictEqual(test.calls,["comments"]);assert.deepStrictEqual(test.saved,["/private.md"]);
    });
});

describe("focused session paths",()=>{
    it("uses custody paths instead of the full inventory on active closures",async()=>{
        const test=scenario(true,true,true,false,true);
        assert.strictEqual(await test.run(),true);
        assert.deepStrictEqual(test.requests,[["paths","--porcelain"]]);
        assert.deepStrictEqual(test.saved,["/private.md"]);
    });
    it("does not narrow a housekeeping inventory",async()=>{
        const test=scenario(true,true,true,false,true,undefined,false);
        assert.strictEqual(await test.run(),true);
        assert.deepStrictEqual(test.requests,[["status","--porcelain","--all"]]);
    });
    it("refuses mismatched truncated or failed path reads before saving a buffer",async()=>{
        const good=`comments-paths\t1\t${"a".repeat(40)}\t${"b".repeat(40)}\ncomments-path\tlocal\t/private.md\ncomments-path\tshared\t/shared.md\ncomments-paths\tcomplete\n`;
        for(const bad of [good.replace("complete","bad"),good.replace("a".repeat(40),"c".repeat(40)),good+"comments-paths\tcomplete\n"]) {
            const test=scenario(true,true,true,false,true,bad);
            assert.strictEqual(await test.run(),false);assert.deepStrictEqual(test.saved,[]);
        }
        const test=scenario(true,true,false,false,true);
        assert.strictEqual(await test.run(),false);assert.deepStrictEqual(test.saved,[]);
    });
    it("falls back only for an explicitly reported legacy session",async()=>{
        const test=scenario(true,true,true,false,true,`comments-paths\t1\t${"a".repeat(40)}\tlegacy\ncomments-paths\tcomplete\n`);
        assert.strictEqual(await test.run(),true);
        assert.deepStrictEqual(test.requests,[["paths","--porcelain"],["status","--porcelain","--all"]]);
        assert.deepStrictEqual(test.saved,["/private.md"]);
    });
    it("decodes literal percent and control characters exactly once",()=>{
        const {parseCommentPaths}=require("../../src/review/commentPaths");
        const guard="a".repeat(40);
        const wire=`comments-paths\t1\t${guard}\t${"b".repeat(40)}\ncomments-path\tlocal\t/Café + %252F%09%0D%0A%3E\ncomments-path\tshared\t/shared.md\ncomments-paths\tcomplete\n`;
        assert.deepStrictEqual(parseCommentPaths(wire,guard).paths,["/Café + %2F\t\r\n>","/shared.md"]);
        assert.strictEqual(parseCommentPaths(wire.replace("%09","%GG"),guard),undefined);
    });
});
