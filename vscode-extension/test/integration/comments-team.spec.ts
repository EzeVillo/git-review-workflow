import * as assert from "node:assert";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {abortReview, createBranchWithChanges, git, gitReviewOrThrow, sharedFixtureRepo} from "./helpers/fixture";

describe("comments across people and merges in the extension host", function () {
    this.timeout(120000);
    const repo = sharedFixtureRepo();

    for (const strategy of ["ff", "merge", "squash"]) it("keeps history and isolates new branches after " + strategy, async () => {
        abortReview(repo);
        const api = await getTestApi();
        const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "comments-team-"));
        const remote = path.join(temporary, "remote.git");
        const author = path.join(temporary, "author");
        const source = "feature/team-" + strategy;
        const base = "team-base-" + strategy;
        const before = "team-before-" + strategy;
        const after = "team-after-" + strategy;
        const originalPick = vscode.window.showQuickPick;
        const originalError = vscode.window.showErrorMessage;
        const errors: string[] = [];
        const previousBase = git(["config", "reviewworkflow.base"], repo.dir).trim();
        // Only the location picker is scripted. The command, selective save,
        // process invocation, refresh and comment browser are production code.
        (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = async (items: {label: string}[]) => items.find(i => i.label === "A separate branch");
        (vscode.window as unknown as {showErrorMessage: unknown}).showErrorMessage = async (message: string) => { errors.push(message); return undefined; };
        try {
            git(["branch", base, "main"], repo.dir);
            git(["branch", before, base], repo.dir);
            git(["switch", before], repo.dir);
            fs.writeFileSync(path.join(repo.dir, "before.txt"), "Before merge\n");
            git(["add", "before.txt"], repo.dir);
            git(["commit", "-m", "Branch before merge"], repo.dir);
            git(["switch", "main"], repo.dir);
            createBranchWithChanges(repo, source, {"README.md": "# fixture\nChanged by author\n"});
            git(["clone", "--bare", repo.dir, remote], temporary);
            git(["remote", "add", "team", remote], repo.dir);
            git(["config", "reviewworkflow.base", base], repo.dir);
            git(["config", "reviewworkflow.remote", "team"], repo.dir);
            gitReviewOrThrow(["start", "--no-walk", source], repo.dir);
            assert.strictEqual((await api.refresh()).situation, "review");
            const editor = await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(path.join(repo.dir, "README.md")));
            editor.selection = new vscode.Selection(1, 0, 1, 7);
            for (const [kind, text] of [["local", "Private Alice"], ["shared", "Alice asks"]]) {
                await vscode.window.showTextDocument(editor.document);
                await vscode.commands.executeCommand("gitReview.addComment");
                await api.sendCommentMessage({type: "save", kind, text});
                assert.strictEqual(api.commentComposerState(), undefined);
            }
            let report = (await api.refresh()).comments!;
            const context = report.documents.find(d => d.kind === "shared")!.context;
            await vscode.commands.executeCommand("gitReview.finishReview");
            assert.deepStrictEqual(errors, []);
            assert.strictEqual(git(["branch", "--show-current"], repo.dir).trim(), "review-fixes/" + source);
            assert.strictEqual(git(["ls-files", "--", ".review/comments.md"], repo.dir).trim(), ".review/comments.md");
            assert.strictEqual(git(["show", ":.review/comments.md"], repo.dir), fs.readFileSync(path.join(repo.dir, ".review/comments.md"), "utf8"));
            git(["commit", "-m", "Alice feedback"], repo.dir);
            git(["push", "team", "HEAD:refs/heads/alice-feedback"], repo.dir);
            git(["clone", "--branch", source, remote, author], temporary);
            git(["config", "user.name", "Author"], author);
            git(["config", "user.email", "author@example.invalid"], author);
            git(["merge", "--ff-only", "origin/alice-feedback"], author);
            const sharedPath = path.join(author, ".review/comments.md");
            fs.writeFileSync(sharedPath, fs.readFileSync(sharedPath, "utf8").replace("Alice asks", "Author replies"));
            git(["add", ".review/comments.md"], author);
            git(["commit", "-m", "Author replies"], author);
            git(["push", "origin", source], author);
            // Resume from the independent author's commits using the client.
            git(["switch", "main"], repo.dir);
            gitReviewOrThrow(["clean", source], repo.dir);
            gitReviewOrThrow(["start", "--no-walk", source], repo.dir);
            report = (await api.refresh()).comments!;
            assert.strictEqual(report.documents.find(d => d.kind === "shared")!.context, context);
            // Shared comes from the branch, including the author's reply.
            assert.ok(!report.diagnostics.some(d => d.code === "source-conflict"));
            assert.ok(fs.readFileSync(report.documents.find(d => d.kind === "shared")!.path, "utf8").includes("Author replies"));
            assert.ok(fs.readFileSync(path.join(repo.dir, ".review/comments.md"), "utf8").includes("Author replies"));
            fs.copyFileSync(path.join(repo.dir, ".review/comments.md"), report.documents.find(d => d.kind === "shared")!.path);
            report = (await api.refresh()).comments!;
            assert.ok(fs.readFileSync(report.documents.find(d => d.kind === "shared")!.path, "utf8").includes("Author replies"));
            await api.sendPanelMessage("openCommentDiff", report.documents.findIndex(d => d.kind === "shared"));
            assert.strictEqual(api.commentBrowserState()?.entries[0].body, "Author replies");
            await api.sendCommentBrowserMessage({type: "open", ordinal: 1});
            assert.strictEqual(api.commentBrowserState(), undefined);
            const historical = vscode.workspace.textDocuments.filter(d => d.uri.scheme === "git-review-comment");
            assert.ok(historical.some(d => d.getText() === "# fixture\nChanged by author\n"));
            await vscode.commands.executeCommand("gitReview.finishReview");
            assert.deepStrictEqual(errors, []);
            assert.ok(!(await api.refresh()).comments!.diagnostics.some(d => d.code === "source-conflict"));
            git(["switch", "main"], repo.dir);
            git(["switch", base], author);
            if (strategy === "ff") git(["merge", "--ff-only", source], author);
            else if (strategy === "merge") git(["merge", "--no-ff", source, "-m", "Merge feature"], author);
            else { git(["merge", "--squash", source], author); git(["commit", "-m", "Squash feature"], author); }
            git(["push", "origin", base], author);
            git(["switch", "-c", after], author);
            fs.writeFileSync(path.join(author, "after.txt"), "After merge\n");
            git(["add", "after.txt"], author);
            git(["commit", "-m", "Branch after merge"], author);
            git(["push", "origin", after], author);
            for (const branch of [before, after]) {
                gitReviewOrThrow(["start", "--no-walk", branch], repo.dir);
                await api.refresh();
                await vscode.commands.executeCommand("gitReview.addComment");
                await api.sendCommentMessage({type: "save", kind: "shared", text: "New independent review"});
                assert.strictEqual(api.commentComposerState(), undefined);
                report = (await api.refresh()).comments!;
                const active = report.documents.find(d => d.kind === "shared" && d.context !== context)!;
                assert.ok(active);
                const contents = fs.readFileSync(active.path, "utf8");
                assert.ok(contents.includes("New independent review"));
                assert.ok(!contents.includes("Alice asks") && !contents.includes("Author replies") && !contents.includes("Private Alice"));
                gitReviewOrThrow(["abort"], repo.dir);
            }
            assert.strictEqual(git(["log", "--all", "--format=", "-p", "-G", "Private Alice"], author), "");
            assert.deepStrictEqual(errors, []);
        } finally {
            (vscode.window as unknown as {showQuickPick: unknown}).showQuickPick = originalPick;
            (vscode.window as unknown as {showErrorMessage: unknown}).showErrorMessage = originalError;
            await api.sendCommentMessage({type: "cancel"});
            await vscode.commands.executeCommand("workbench.action.closeAllEditors");
            abortReview(repo);
            gitReviewOrThrow(["clean", source], repo.dir);
            git(["config", "reviewworkflow.base", previousBase], repo.dir);
            git(["config", "--unset-all", "reviewworkflow.remote"], repo.dir);
            git(["remote", "remove", "team"], repo.dir);
            fs.rmSync(temporary, {recursive: true, force: true});
            await api.refresh();
        }
    });
});
