import * as path from "path";
import {runTests} from "@vscode/test-electron";
import {cleanupRepo, createTempRepo} from "./helpers/fixture";

async function main() {
    const extensionDevelopmentPath = path.resolve(__dirname, "../../..");
    const extensionTestsPath = path.resolve(__dirname, "./index");

    const repo = createTempRepo();
    process.env.GIT_REVIEW_FIXTURE_DIR = repo.dir;

    try {
        await runTests({
            extensionDevelopmentPath,
            extensionTestsPath,
            launchArgs: [repo.dir],
        });
    } catch (err) {
        console.error("Failed to run integration tests", err);
        process.exitCode = 1;
    } finally {
        cleanupRepo(repo);
    }
}

main();
