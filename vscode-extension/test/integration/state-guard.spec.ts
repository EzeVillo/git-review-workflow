import * as assert from "node:assert";
import {invokeGitReview} from "../../src/cli/invoke";
import {parseStateGuard} from "../../src/review/staleGuard";
import {STALE} from "../../src/review/userCopy";
import {addWalkthrough, cleanupRepo, createBranchWithChanges, createTempRepo, git, gitReviewOrThrow, startReview} from "./helpers/fixture";

describe("CLI review context validation", function () {
    this.timeout(120000);

    function fixture() {
        const repo = createTempRepo();
        createBranchWithChanges(repo, "guarded", {"a.txt": "a\n", "b.txt": "b\n"});
        addWalkthrough(repo, "guarded", [{path: "a.txt", why: "first"}, {path: "b.txt", why: "second"}]);
        startReview(repo, "guarded");
        return repo;
    }

    it("passes a current guard through the configured dispatcher", async () => {
        const repo = fixture();
        try {
            const guard = parseStateGuard(gitReviewOrThrow(["status", "--porcelain"], repo.dir).stdout);
            assert.ok(guard);
            const before = git(["diff", "--binary", "HEAD"], repo.dir);
            const result = await invokeGitReview("next", [], {cwd: repo.dir, gitReviewPath: repo.gitReviewPath, expectedState: guard});
            assert.strictEqual(result.exitCode, 0, result.stderr);
            assert.strictEqual(git(["config", "branch.review/guarded.reviewwalkstep"], repo.dir).trim(), "2");
            assert.strictEqual(git(["diff", "--binary", "HEAD"], repo.dir), before);
        } finally { cleanupRepo(repo); }
    });

    it("reloads once after an external cursor change and never advances the stale action", async () => {
        const repo = fixture();
        try {
            const guard = parseStateGuard(gitReviewOrThrow(["status", "--porcelain"], repo.dir).stdout);
            assert.ok(guard);
            gitReviewOrThrow(["next"], repo.dir);
            let refreshed = 0;
            const result = await invokeGitReview("next", [], {
                cwd: repo.dir, gitReviewPath: repo.gitReviewPath, expectedState: guard,
                onStateMismatch: async () => {
                    refreshed++;
                    assert.notStrictEqual(parseStateGuard(gitReviewOrThrow(["status", "--porcelain"], repo.dir).stdout), guard);
                },
            });
            assert.strictEqual(result.exitCode, 4);
            assert.strictEqual(result.stderr, STALE);
            assert.strictEqual(refreshed, 1);
            assert.strictEqual(git(["config", "branch.review/guarded.reviewwalkstep"], repo.dir).trim(), "2");
        } finally { cleanupRepo(repo); }
    });
});
