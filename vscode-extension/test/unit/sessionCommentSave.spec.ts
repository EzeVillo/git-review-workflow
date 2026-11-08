import * as assert from "node:assert";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {runInNewContext} from "node:vm";
import * as ts from "typescript";

function scenario(dirty: boolean, save = true, query = true, unknown = false) {
    const calls: string[] = [], saved: string[] = [], notices: string[] = [];
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
            if(name==="../cli/invoke")return {invokeGitReview:async(verb:string)=>{calls.push(verb);return {exitCode:query?0:1,stdout:query?report:"",stderr:"query failed"};}};
            if(name==="../cli/commentsPorcelain"||name==="../review/commentsFlow"||name==="../review/userCopy")return require(resolve("src/commands",name));
            if(name==="../review/draftFlow")return {sameDraftFile:(a:string,b:string)=>a===b};
            return {};
        },
    });
    const manager={state:{state:{source:"x"}},refreshPrimary:async()=>undefined,refresh:async()=>undefined};
    return {run:()=>exported.saveSessionComments(manager,{cwd:"/repo"},undefined,"all"),calls,saved,notices};
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
