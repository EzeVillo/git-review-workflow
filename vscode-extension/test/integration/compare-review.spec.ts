import * as assert from "node:assert";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {abortReview, createBranchWithChanges, git, sharedFixtureRepo} from "./helpers/fixture";

describe("Compare revisions", function () {
    this.timeout(60000);
    const repo = sharedFixtureRepo();

    afterEach(() => abortReview(repo));

    it("lists a new branch and compares it against a typed tag", async () => {
        const api = await getTestApi();
        const branch = "compare-pruebas";
        const tag = "compare-base";
        const before = await api.refresh();
        assert.strictEqual(before.situation, "no-review");
        assert.ok(before.candidates?.some(candidate => candidate.name === "main"));
        assert.ok(!before.candidates?.some(candidate => candidate.name === branch));
        createBranchWithChanges(repo, branch, {"compare.txt": "added\n"});
        git(["tag", tag, "main"], repo.dir);

        type Item = vscode.QuickPickItem & {value?: string; layout?: string};
        const edit = vscode.window as unknown as Record<string, unknown>;
        const {createQuickPick, showQuickPick, showWarningMessage} = edit;
        const questions: string[] = [];
        edit.createQuickPick = () => {
            let changeValue: (value: string) => void;
            let accept: () => void;
            let hide: () => void;
            const picker = {
                title: "",
                placeholder: "",
                value: "",
                items: [] as Item[],
                selectedItems: [] as Item[],
                onDidChangeValue(callback: typeof changeValue) { changeValue = callback; },
                onDidAccept(callback: typeof accept) { accept = callback; },
                onDidHide(callback: typeof hide) { hide = callback; },
                hide() { hide(); },
                dispose() {},
                show() {
                    questions.push(this.title);
                    if (questions.length === 1) {
                        const candidate = this.items.find(item => item.label === branch);
                        assert.ok(candidate, "the new local branch should be suggested");
                        this.selectedItems = [candidate];
                    } else {
                        assert.ok(this.placeholder.includes(`Reviewing ${branch}.`));
                        this.value = tag;
                        changeValue(tag);
                        assert.strictEqual(this.items[0].label, tag);
                        this.selectedItems = [this.items[0]];
                    }
                    accept();
                },
            };
            return picker;
        };
        edit.showQuickPick = async (items: Item[], options: vscode.QuickPickOptions) => {
            if (options.title === `Which version of ${branch}?`) {
                assert.deepStrictEqual(items.map(item => item.label), ["Local branch"]);
                return items[0];
            }
            assert.strictEqual(options.title, `Review ${branch} against ${tag}`);
            return items.find(item => item.layout === "whole");
        };
        edit.showWarningMessage = async () => "Compare";
        try {
            await vscode.commands.executeCommand("gitReview.compareReview");
        } finally {
            Object.assign(edit, {createQuickPick, showQuickPick, showWarningMessage});
        }

        assert.deepStrictEqual(questions, ["What do you want to review?", "Compare against what?"]);
        const state = await api.refresh();
        assert.strictEqual(state.comparison?.baseOid, git(["rev-parse", tag], repo.dir).trim());
        assert.strictEqual(state.comparison?.targetOid, git(["rev-parse", branch], repo.dir).trim());
        assert.strictEqual(git(["diff", "--cached", "--name-status"], repo.dir).trim(), "A\tcompare.txt");
        assert.strictEqual(git(["for-each-ref", "--format=%(refname)", "refs/worktree/review-compare/pending/"], repo.dir).trim(), "");
    });
});
