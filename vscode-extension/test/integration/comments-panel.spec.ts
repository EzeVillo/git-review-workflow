import * as assert from "node:assert";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vscode from "vscode";
import {parseComments} from "../../src/cli/commentsPorcelain";
import {sameDraftFile} from "../../src/review/draftFlow";
import {getTestApi} from "./helpers/extensionApi";
import {snapshotTabs, waitForNewTab} from "./helpers/editors";
import {abortReview, createBranchWithChanges, git, gitReviewOrThrow, sharedFixtureRepo, startReview} from "./helpers/fixture";

describe("comments client integration", function () {
    this.timeout(120000);
    const repo=sharedFixtureRepo();
    let branch = "";
    let sequence = 0;
    beforeEach(async()=>{
        abortReview(repo);
        branch = "feature/comments-client-" + ++sequence;
        createBranchWithChanges(repo,branch,{"README.md":"# fixture\none\ntwo\nthree\nfour\nfive\n"});
        startReview(repo,branch,["--no-walk"]);
        const api=await getTestApi();assert.strictEqual((await api.refresh()).situation,"review");
    });
    afterEach(async()=>{
        const api=await getTestApi();await api.sendCommentMessage({type:"cancel"});
        for(const doc of vscode.workspace.textDocuments.filter(d=>d.isDirty)) {
            await vscode.window.showTextDocument(doc);await vscode.commands.executeCommand("workbench.action.revertAndCloseActiveEditor");
        }
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");abortReview(repo);await api.refresh();
    });
    it("copies only the Local document path without saving its editor or changing Git", async () => {
        const api = await getTestApi();
        for (const kind of ["local", "shared"]) {
            await api.sendPanelMessage("addComment");
            await api.sendCommentMessage({type: "save", kind, text: "Keep this " + kind + " observation"});
            assert.strictEqual(api.commentComposerState(), undefined);
        }
        const report = (await api.refresh()).comments!;
        const index = report.documents.findIndex(doc => doc.kind === "local");
        const local = report.documents[index];
        const document = await vscode.workspace.openTextDocument(vscode.Uri.file(local.path));
        const editor = await vscode.window.showTextDocument(document);
        const before = fs.readFileSync(local.path, "utf8");
        const status = git(["status", "--porcelain"], repo.dir);
        assert.ok(await editor.edit(edit => edit.insert(new vscode.Position(0, 0), "Unsaved note\n")));
        await vscode.env.clipboard.writeText("Keep the clipboard");
        for (const invalid of [-1, 0.5, "0", report.documents.length, report.documents.findIndex(doc => doc.kind === "shared")]) {
            await api.sendPanelMessage("copyCommentPath", invalid);
            assert.strictEqual(await vscode.env.clipboard.readText(), "Keep the clipboard");
        }
        // Opening/editing the document can start a watcher refresh, whose first
        // phase temporarily has no comment rows. Resolve it before clicking a
        // current row; keep the unsaved-buffer assertions below unchanged.
        const current = (await api.refresh()).comments!;
        const currentIndex = current.documents.findIndex(doc => doc.kind === "local" && doc.path === local.path);
        assert.ok(currentIndex >= 0);
        await api.sendPanelMessage("copyCommentPath", currentIndex);
        assert.strictEqual(await vscode.env.clipboard.readText(), local.path);
        assert.ok(document.isDirty, "copying a path must not save a comment buffer");
        assert.strictEqual(fs.readFileSync(local.path, "utf8"), before);
        assert.strictEqual(git(["status", "--porcelain"], repo.dir), status);
    });
    it("copies the current Local path after closing a comparison", async () => {
        abortReview(repo);
        gitReviewOrThrow(["compare", "--no-walk", "main", branch], repo.dir);
        const api = await getTestApi();
        await api.refresh();
        await api.sendPanelMessage("addComment");
        await api.sendCommentMessage({type: "save", text: "Comparison note"});
        const active = (await api.refresh()).comments!;
        const local = active.documents.find(doc => doc.kind === "local")!;
        await api.sendPanelMessage("copyCommentPath", active.documents.indexOf(local));
        assert.strictEqual(await vscode.env.clipboard.readText(), local.path);
        gitReviewOrThrow(["abort"], repo.dir);
        const report = (await api.refresh()).comments!;
        const index = report.documents.findIndex(doc => doc.kind === "local" && doc.context === local.context);
        assert.ok(index >= 0);
        assert.notStrictEqual(report.documents[index].path, local.path);
        await api.sendPanelMessage("copyCommentPath", index);
        assert.strictEqual(await vscode.env.clipboard.readText(), report.documents[index].path);
        assert.ok(fs.existsSync(report.documents[index].path));
        assert.strictEqual(git(["status", "--porcelain"], repo.dir).trim(), "");
    });
    it("uses the sole compare destination without choosing and retains notes on close", async () => {
        abortReview(repo);
        gitReviewOrThrow(["compare", "--no-walk", "main", branch], repo.dir);
        const api = await getTestApi();
        await api.refresh();
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
        await vscode.commands.executeCommand("gitReview.addComment");
        assert.strictEqual(api.commentComposerState()?.destination, "local");
        await api.sendCommentMessage({type: "save", kind: "shared", text: "Invalid destination"});
        assert.ok(api.commentComposerState()?.active, "unavailable destinations cannot submit");
        await api.sendCommentMessage({type: "save", text: "Comparison note without a destination picker"});
        assert.strictEqual(api.commentComposerState(), undefined);
        const report = (await api.refresh()).comments!;
        const local = report.documents.find(d => d.kind === "local")!;
        const text = fs.readFileSync(local.path, "utf8");
        gitReviewOrThrow(["abort"], repo.dir);
        const retained = (await api.refresh()).comments!.documents.find(d => d.kind === "local" && d.context === local.context)!;
        assert.strictEqual(fs.readFileSync(retained.path, "utf8"), text);
        assert.strictEqual(git(["status", "--porcelain"], repo.dir).trim(), "");
        assert.ok(!(await vscode.commands.getCommands()).includes("gitReview.saveComments"));
    });
    for (const view of ["file", "diff"]) it("returns to general comments after closing the last " + view, async () => {
        const api = await getTestApi();
        const uri = vscode.Uri.file(path.join(repo.dir, "README.md"));
        const document = await vscode.workspace.openTextDocument(uri);
        if (view === "file") await vscode.window.showTextDocument(document);
        else {
            const previous = snapshotTabs();
            await vscode.commands.executeCommand("vscode.diff", uri, uri, "README.md");
            await waitForNewTab(previous, tab => tab.input instanceof vscode.TabInputTextDiff);
        }
        assert.strictEqual((await api.getPanelModel()).commentTarget, "File · README.md (New version)");
        await vscode.commands.executeCommand("workbench.action.closeAllEditors");
        assert.strictEqual(vscode.window.visibleTextEditors.length, 0);
        assert.strictEqual((await api.getPanelModel()).commentTarget, "General comment");
        await vscode.commands.executeCommand("gitReview.addComment");
        assert.strictEqual(api.commentComposerState()?.scope, "general");
        await api.sendCommentMessage({type: "save", kind: "local", text: "About the review as a whole"});
        assert.strictEqual(api.commentComposerState(), undefined);
        const report = (await api.refresh()).comments!;
        const local = report.documents.find(doc => doc.kind === "local")!;
        assert.strictEqual(local.count, 1);
        const stored = fs.readFileSync(local.path, "utf8");
        assert.ok(stored.includes("About the review as a whole"));
        const entries = parseComments(gitReviewOrThrow(["comments", "entries", "--document", "local", "--porcelain"], repo.dir).stdout);
        assert.deepStrictEqual(entries.rows.filter(row => row.tag === "comment-scope").map(row => row.fields), [["1", "general", ""]]);
        assert.deepStrictEqual(entries.locations, []);
        assert.ok(!entries.rows.some(row => row.tag === "comment-path"), "a closed tab cannot supply a file location");
    });
    it("retains the visible selection when focus moves into the review panel", async () => {
        const api = await getTestApi();
        const editor = await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(path.join(repo.dir, "README.md")));
        editor.selection = new vscode.Selection(1, 0, 2, 3);
        const target = "Selected code · README.md:2:1–3:4 (New version)";
        assert.strictEqual((await api.getPanelModel()).commentTarget, target);
        await vscode.commands.executeCommand("gitReview.walkthrough.focus");
        assert.ok(vscode.window.visibleTextEditors.includes(editor));
        assert.strictEqual((await api.getPanelModel()).commentTarget, target);
        await api.sendPanelMessage("addComment");
        assert.strictEqual(api.commentComposerState()?.scope, "selection");
        await api.sendCommentMessage({type: "save", kind: "local", text: "This exact selection"});
        const report = (await api.refresh()).comments!;
        const stored = fs.readFileSync(report.documents.find(doc => doc.kind === "local")!.path, "utf8");
        assert.ok(stored.includes("This exact selection"));
        const entries = parseComments(gitReviewOrThrow(["comments", "entries", "--document", "local", "--porcelain"], repo.dir).stdout);
        assert.deepStrictEqual(entries.rows.filter(row => row.tag === "comment-scope").map(row => row.fields), [["1", "selection", "head"]]);
        assert.deepStrictEqual(entries.locations, [{ordinal: 1, side: "head", start: 2, end: 3, startColumn: 1, endColumn: 4}]);
        assert.ok(entries.rows.some(row => row.tag === "comment-path" && row.fields[1] === "head" && row.fields[2] === "README.md"));
    });
    for (const view of ["diff", "multi-diff"]) for (const side of ["base", "head"] as const) it("captures the selected " + side + " side of a " + view + " after focusing the panel", async () => {
        const api = await getTestApi();
        const state = await api.refresh();
        const previous = snapshotTabs();
        if (view === "diff") {
            const entry = state.entries.find(entry => typeof entry.id !== "string" && entry.id.display === "README.md");
            assert.ok(entry);
            await vscode.commands.executeCommand("gitReview.openChange", entry);
        } else await vscode.commands.executeCommand("gitReview.openAllChanges");
        assert.ok(await waitForNewTab(previous), "the review changes opened");
        const editor = vscode.window.visibleTextEditors.find(editor => path.basename(editor.document.uri.fsPath) === "README.md" && editor.document.uri.scheme === (side === "base" ? "git" : "file"));
        assert.ok(editor, "the selected side is visible");
        const selection = side === "base" ? new vscode.Selection(0, 2, 0, 5) : new vscode.Selection(1, 0, 2, 3);
        const changed = new Promise<void>(resolve => {
            const listener = vscode.window.onDidChangeTextEditorSelection(event => {
                if (event.textEditor === editor && event.selections[0]?.isEqual(selection)) {listener.dispose(); resolve();}
            });
        });
        editor.selection = selection;
        await changed;
        await vscode.commands.executeCommand("gitReview.walkthrough.focus");
        const target = side === "base" ? "Selected code · README.md:1:3–1:6 (Previous version)" : "Selected code · README.md:2:1–3:4 (New version)";
        assert.strictEqual((await api.getPanelModel()).commentTarget, target);
        await api.sendPanelMessage("addComment");
        assert.strictEqual(api.commentComposerState()?.scope, "selection");
        await api.sendCommentMessage({type: "save", kind: "local", text: "Selected in the " + view});
        assert.strictEqual(api.commentComposerState(), undefined);
        const entries = parseComments(gitReviewOrThrow(["comments", "entries", "--document", "local", "--porcelain"], repo.dir).stdout);
        assert.deepStrictEqual(entries.locations, [{ordinal: 1, side, start: selection.start.line + 1, end: selection.end.line + 1, startColumn: selection.start.character + 1, endColumn: selection.end.character + 1}]);
        assert.ok(entries.rows.some(row => row.tag === "comment-path" && row.fields[1] === side && row.fields[2] === "README.md"));
    });
    for (const [side, action] of [["base", "openChange"], ["head", "openChange"], ["base", "openEntry"]] as const) it("captures selected code from a " + (side === "base" ? "deleted" : "new") + " file opened by " + action, async () => {
        abortReview(repo);
        git(["checkout", branch], repo.dir);
        const file = side === "base" ? "README.md" : "new-file.ts";
        if (side === "base") git(["rm", file], repo.dir);
        else {
            fs.writeFileSync(path.join(repo.dir, file), "first line\nsecond line\n");
            git(["add", file], repo.dir);
        }
        git(["commit", "-m", "one-sided changes"], repo.dir);
        git(["checkout", "main"], repo.dir);
        startReview(repo, branch, ["--no-walk"]);
        const api = await getTestApi();
        const state = await api.refresh();
        const entry = state.entries.find(entry => typeof entry.id !== "string" && entry.id.display === file);
        assert.ok(entry);
        await vscode.commands.executeCommand("gitReview." + action, entry);
        const editor = vscode.window.activeTextEditor;
        assert.ok(editor);
        assert.strictEqual(editor.document.uri.scheme, "git");
        editor.selection = new vscode.Selection(0, 2, 0, 5);
        assert.strictEqual((await api.getPanelModel()).commentTarget, "Selected code · " + file + ":1:3–1:6 (" + (side === "base" ? "Previous version" : "New version") + ")");
        await vscode.commands.executeCommand("gitReview.addComment");
        assert.strictEqual(api.commentComposerState()?.scope, "selection");
        await api.sendCommentMessage({type: "save", kind: "local", text: "One-sided selection"});
        assert.strictEqual(api.commentComposerState(), undefined);
        const entries = parseComments(gitReviewOrThrow(["comments", "entries", "--document", "local", "--porcelain"], repo.dir).stdout);
        assert.deepStrictEqual(entries.locations, [{ordinal: 1, side, start: 1, end: 1, startColumn: 3, endColumn: 6}]);
        assert.ok(entries.rows.some(row => row.tag === "comment-path" && row.fields[1] === side && row.fields[2] === file));
    });
    it("captures reversed selection and Local Shared Local without saving code",async()=>{
        const api=await getTestApi();const file=path.join(repo.dir,"README.md");
        const editor=await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(file));
        editor.selection=new vscode.Selection(new vscode.Position(4,0),new vscode.Position(1,1));
        await editor.edit(edit=>edit.insert(new vscode.Position(0,0),"unsaved code\n"));
        const index=git(["ls-files","--stage"],repo.dir),disk=fs.readFileSync(file,"utf8");
        for(const [kind,text] of [["local","Private first"],["shared","Shared second"],["local","Private third"]]) {
            await vscode.window.showTextDocument(editor.document);
            await vscode.commands.executeCommand("gitReview.addComment");
            assert.strictEqual(api.commentComposerState()?.destination,undefined);
            await api.sendCommentMessage({type:"save",kind,text});
            assert.strictEqual(api.commentComposerState(),undefined);
        }
        const report=(await api.refresh()).comments!;
        assert.strictEqual(report.documents.find(d=>d.kind==="local")?.count,2);
        assert.strictEqual(report.documents.find(d=>d.kind==="shared")?.count,1);
        assert.strictEqual(editor.document.isDirty,true);assert.strictEqual(fs.readFileSync(file,"utf8"),disk);assert.strictEqual(git(["ls-files","--stage"],repo.dir),index);
        const local=fs.readFileSync(report.documents.find(d=>d.kind==="local")!.path,"utf8");
        const shared=fs.readFileSync(report.documents.find(d=>d.kind==="shared")!.path,"utf8");
        assert.ok(local.includes("Private first")&&local.includes("Private third")&&!local.includes("Shared second"));
        assert.ok(shared.includes("Shared second")&&!shared.includes("Private first"));assert.ok(local.includes("unversioned 1"));
    });
    it("cancel and whitespace do not create documents",async()=>{
        const api=await getTestApi();await vscode.commands.executeCommand("gitReview.addComment");
        await api.sendCommentMessage({type:"save",kind:"local",text:" \n\t"});
        assert.ok(api.commentComposerState()?.active);assert.strictEqual((await api.refresh()).comments?.documents.length,0);
        await api.sendCommentMessage({type:"cancel"});assert.strictEqual(api.commentComposerState(),undefined);
    });
    for(const mode of ["false","throw","dirty"])it("failed selective save retains the form: "+mode,async()=>{
        const api=await getTestApi();gitReviewOrThrow(["comments","add","--document","local","--text","Initial"],repo.dir);
        const report=(await api.refresh()).comments!;const local=report.documents.find(d=>d.kind==="local")!;
        const editor=await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(local.path));
        await editor.edit(edit=>edit.insert(new vscode.Position(0,0),"unsaved prose\n"));
        let saved=0;
        api.setCommentSaver(async document=>{assert.ok(sameDraftFile(document.uri.fsPath,local.path));saved++;if(mode==="throw")throw Error("save failure");return mode!=="false";});
        try {
            await vscode.commands.executeCommand("gitReview.addComment");await api.sendCommentMessage({type:"save",kind:"local",text:"Keep this text"});
            assert.strictEqual(saved,1);assert.strictEqual(api.commentComposerState()?.text,"Keep this text");assert.ok(api.commentComposerState()?.error);
            assert.strictEqual(editor.document.isDirty,true);assert.ok(!fs.readFileSync(local.path,"utf8").includes("Keep this text"));
        } finally {api.setCommentSaver();}
    });
    it("a changed session rejects the capture and retains its text",async()=>{
        const api=await getTestApi();await vscode.commands.executeCommand("gitReview.addComment");
        gitReviewOrThrow(["save"],repo.dir);
        await api.sendCommentMessage({type:"save",kind:"shared",text:"Keep on stale"});
        assert.strictEqual(api.commentComposerState()?.text,"Keep on stale");assert.ok(api.commentComposerState()?.error?.includes("repository changed"));
        gitReviewOrThrow(["continue",branch],repo.dir);
    });
    for (const side of ["head", "base"]) it("opens and selects immutable historical lines on " + side,async()=>{
        const api=await getTestApi();
        gitReviewOrThrow(["comments","add","--document","local","--text","Historical observation","--path","README.md","--side",side,"--start-line",side === "head" ? "2" : "1","--end-line",side === "head" ? "3" : "1"],repo.dir);
        const report=(await api.refresh()).comments!;
        fs.unlinkSync(path.join(repo.dir,"README.md"));
        const previous=snapshotTabs();
        {
            await api.sendPanelMessage("openCommentDiff",report.documents.findIndex(d=>d.kind==="local"));
            const browser=api.commentBrowserState();
            assert.strictEqual(browser?.entries[0].body,"Historical observation");
            assert.strictEqual(browser?.entries[0].location,side === "head" ? "README.md:2–3 · New version" : "README.md:1–1 · Previous version");
            await api.sendCommentBrowserMessage({type:"open",ordinal:browser!.entries[0].ordinal});
            assert.strictEqual(api.commentBrowserState(),undefined,"the browser closes after opening the diff");
            const tab=await waitForNewTab(previous,t=>t.input instanceof vscode.TabInputTextDiff);
            assert.ok(tab?.input instanceof vscode.TabInputTextDiff);
            const input=tab.input;
            assert.strictEqual(input.original.scheme,"git-review-comment");assert.strictEqual(input.modified.scheme,"git-review-comment");
            assert.strictEqual((await vscode.workspace.openTextDocument(input.original)).getText(),"# fixture\n");
            assert.strictEqual((await vscode.workspace.openTextDocument(input.modified)).getText(),"# fixture\none\ntwo\nthree\nfour\nfive\n");
            const uri = side === "head" ? input.modified : input.original;
            const marked = vscode.window.visibleTextEditors.find(editor => editor.document.uri.toString() === uri.toString());
            assert.ok(marked, "the original side is visible");
            assert.strictEqual(marked.selection.start.line, side === "head" ? 1 : 0);
            assert.strictEqual(marked.selection.end.line, side === "head" ? 2 : 0);
            assert.strictEqual(git(["branch","--show-current"],repo.dir).trim(),"review/"+branch);
        }
    });
    for (const side of ["head", "base"]) it("restores the exact partial selection on " + side,async()=>{
        const api=await getTestApi();
        const file=path.join(repo.dir,"README.md");
        const editor=await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(file));
        editor.selection=new vscode.Selection(0,5,0,2);
        await vscode.commands.executeCommand("gitReview.addComment");
        await api.sendCommentMessage({type:"save",kind:"local",text:"Only fix"});
        let report=(await api.refresh()).comments!;
        const local=report.documents.find(d=>d.kind==="local")!;
        const stored=fs.readFileSync(local.path,"utf8");
        assert.ok(stored.includes("start-column 3\nend-column 6"));
        // Reuse the captured endpoints on the previous side as well.
        if(side==="base")fs.writeFileSync(local.path,stored.replace("side head", "side base"));
        report=(await api.refresh()).comments!;
        const previous=snapshotTabs();
        await api.sendPanelMessage("openCommentDiff",report.documents.findIndex(d=>d.kind==="local"));
        await api.sendCommentBrowserMessage({type:"open",ordinal:1});
        assert.strictEqual(api.commentBrowserState(),undefined,"the browser closes after opening the diff");
        await waitForNewTab(previous,t=>t.input instanceof vscode.TabInputTextDiff);
        const selected=vscode.window.visibleTextEditors.find(e=>e.document.uri.scheme==="git-review-comment" && e.document.getText(e.selection)==="fix");
        assert.ok(selected,"the exact fragment is selected in the historical viewer");
        assert.strictEqual(selected.selection.start.character,2);
        assert.strictEqual(selected.selection.end.character,5);
    });
    it("general comments ignore diff requests and delete individually without renumbering",async()=>{
        const api=await getTestApi();
        for (const text of ["First", "Remove", "Last"]) gitReviewOrThrow(["comments","add","--document","local","--text",text],repo.dir);
        const report=(await api.refresh()).comments!;const local=report.documents.find(d=>d.kind==="local")!;
        await api.sendPanelMessage("openCommentDiff",report.documents.findIndex(d=>d.kind==="local"));
        const before=fs.readFileSync(local.path,"utf8");
        assert.strictEqual(api.commentBrowserState()?.entries[0].canOpenDiff,false);
        await api.sendCommentBrowserMessage({type:"open",ordinal:1});
        assert.strictEqual(api.commentBrowserState()?.error,undefined);
        assert.ok(!snapshotTabs().some(tab=>tab.input instanceof vscode.TabInputTextDiff));
        const original=vscode.window.showWarningMessage;
        try {
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage=async()=>undefined;
            await api.sendCommentBrowserMessage({type:"delete",ordinal:2});
            assert.strictEqual(fs.readFileSync(local.path,"utf8"),before);
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage=async()=>"Delete";
            await api.sendCommentBrowserMessage({type:"delete",ordinal:2});
            assert.deepStrictEqual(api.commentBrowserState()?.entries.map(e=>e.label.split(".")[0]),["1","3"]);
            assert.deepStrictEqual(api.commentBrowserState()?.entries.map(e=>e.body),["First","Last"]);
            assert.strictEqual(api.commentBrowserState()?.error,undefined);
            assert.ok(!fs.readFileSync(local.path,"utf8").includes("Remove"));
            await api.sendCommentBrowserMessage({type:"delete",ordinal:2});
            await api.sendCommentBrowserMessage({type:"delete",ordinal:1});
            assert.deepStrictEqual(api.commentBrowserState()?.entries,[]);
            assert.ok(fs.existsSync(local.path));
        } finally {(vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage=original;}
    });
    it("stale individual deletion preserves the selected document",async()=>{
        const api=await getTestApi();gitReviewOrThrow(["comments","add","--document","local","--text","Keep"],repo.dir);
        const report=(await api.refresh()).comments!;const local=report.documents.find(d=>d.kind==="local")!;
        await api.sendPanelMessage("openCommentDiff",report.documents.findIndex(d=>d.kind==="local"));
        fs.appendFileSync(local.path,"\nExternal edit\n");const before=fs.readFileSync(local.path,"utf8");
        const original=vscode.window.showWarningMessage;
        try {
            (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage=async()=>"Delete";
            await api.sendCommentBrowserMessage({type:"delete",ordinal:1});
            assert.strictEqual(fs.readFileSync(local.path,"utf8"),before);
            assert.ok(api.commentBrowserState()?.error?.includes("repository changed"));
            assert.strictEqual(api.commentBrowserState()?.entries[0].body,"Keep");
        } finally {(vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage=original;}
    });
    it("keeps full prose and rejects a browser whose document revision changed",async()=>{
        const api=await getTestApi();gitReviewOrThrow(["comments","add","--document","local","--text","Original\n\nSecond paragraph","--path","README.md","--side","head"],repo.dir);
        const report=(await api.refresh()).comments!;const local=report.documents.find(d=>d.kind==="local")!;
        await api.sendPanelMessage("openCommentDiff",report.documents.findIndex(d=>d.kind==="local"));
        assert.strictEqual(api.commentBrowserState()?.entries[0].body,"Original\n\nSecond paragraph");
        fs.appendFileSync(local.path,"\nExternal edit\n");
        await api.sendCommentBrowserMessage({type:"open",ordinal:1});
        assert.ok(api.commentBrowserState()?.error?.includes("repository changed"));
        assert.ok(!snapshotTabs().some(tab => tab.input instanceof vscode.TabInputTextDiff));
    });
});
