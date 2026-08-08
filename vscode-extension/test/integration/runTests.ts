import * as path from "path";
import {runTests} from "@vscode/test-electron";
import {cleanupRepo, createTempRepo, putBinOnPath} from "./helpers/fixture";

async function main() {
    // Antes de lanzar nada: el host hereda este PATH, y con él la extensión
    // resuelve la CLI del checkout en vez de la que esté instalada en el
    // sistema (ver putBinOnPath). Sin esto la suite necesita `./install.sh`.
    putBinOnPath();

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
