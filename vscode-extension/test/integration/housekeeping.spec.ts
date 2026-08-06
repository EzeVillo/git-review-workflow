import * as assert from "node:assert";
import * as vscode from "vscode";
import {getTestApi} from "./helpers/extensionApi";
import {
    abortReview,
    createBranchWithChanges,
    FixtureRepo,
    git,
    gitReview,
    gitReviewOrThrow,
    sharedFixtureRepo,
    startReview,
} from "./helpers/fixture";

async function withScriptedConfirm<T>(answer: string | undefined, fn: () => Thenable<T>): Promise<T> {
    const original = vscode.window.showWarningMessage;
    (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = async () => answer;
    try {
        return await fn();
    } finally {
        (vscode.window as unknown as {showWarningMessage: unknown}).showWarningMessage = original;
    }
}

function listPorcelain(repo: {dir: string}): string {
    return gitReviewOrThrow(["list", "--porcelain"], repo.dir).stdout;
}

function tryDelete(repo: {dir: string}, ref: string): void {
    try {
        git(["branch", "-D", ref], repo.dir);
    } catch {
        // absent
    }
}

function forceCleanup(repo: FixtureRepo, branch: string): void {
    git(["checkout", "-f", "main"], repo.dir);
    gitReview(["forget", "--saved", branch], repo.dir);
    tryDelete(repo, `review/${branch}`);
    tryDelete(repo, `review-saved/${branch}`);
    abortReview(repo);
    tryDelete(repo, branch);
}

const BRANCHES = ["hk-discard-saved", "hk-dismiss-discard"];

describe("US1 (006): housekeeping forget and clean", function () {
    this.timeout(90000);
    const repo = sharedFixtureRepo();

    afterEach(async () => {
        git(["checkout", "-f", "main"], repo.dir);
        for (const b of BRANCHES) {
            forceCleanup(repo, b);
        }
    });

    it("confirm discard saved removes review-saved from list porcelain", async () => {
        const branch = "hk-discard-saved";
        createBranchWithChanges(repo, branch, {"src/hk-a.ts": "a\n"});

        const api = await getTestApi();
        startReview(repo, branch);
        gitReviewOrThrow(["save"], repo.dir);

        assert.ok(
            listPorcelain(repo).includes(`review-saved/${branch}`),
            "precondition: saved review listed"
        );

        let state = await api.refresh();
        assert.strictEqual(state.situation, "no-review");
        assert.ok(state.branches.some((b) => b.name === `review-saved/${branch}`));

        const index = state.branches.findIndex((b) => b.name === `review-saved/${branch}`);
        assert.ok(index >= 0);

        await withScriptedConfirm("Discard", () =>
            vscode.commands.executeCommand("gitReview.discardInventory", index)
        );

        state = await api.refresh();
        assert.ok(
            !listPorcelain(repo).includes(`review-saved/${branch}`),
            "saved review must be gone after discard"
        );
        assert.ok(!state.branches.some((b) => b.name === `review-saved/${branch}`));
    });

    it("dismiss discard confirm leaves saved review", async () => {
        const branch = "hk-dismiss-discard";
        createBranchWithChanges(repo, branch, {"src/hk-b.ts": "b\n"});

        const api = await getTestApi();
        startReview(repo, branch);
        gitReviewOrThrow(["save"], repo.dir);

        const state = await api.refresh();
        const index = state.branches.findIndex((b) => b.name === `review-saved/${branch}`);
        assert.ok(index >= 0);

        await withScriptedConfirm(undefined, () =>
            vscode.commands.executeCommand("gitReview.discardInventory", index)
        );

        assert.ok(
            listPorcelain(repo).includes(`review-saved/${branch}`),
            "dismiss must not call forget"
        );
    });
});
