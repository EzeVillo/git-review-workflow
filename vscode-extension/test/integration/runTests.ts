import * as path from "path";
import {runTests} from "@vscode/test-electron";
import {cleanupRepo, createTempRepo, putBinOnPath} from "./helpers/fixture";
import {createUserDataDir, launchArgsFor, removeUserDataDir} from "./helpers/userDataDir";

async function main() {
    // Antes de lanzar nada: el host hereda este PATH, y con él la extensión
    // resuelve la CLI del checkout en vez de la que esté instalada en el
    // sistema (ver putBinOnPath). Sin esto la suite necesita `./install.sh`.
    putBinOnPath();

    const extensionDevelopmentPath = path.resolve(__dirname, "../../..");
    const extensionTestsPath = path.resolve(__dirname, "./index");

    // No el default de test-electron (`<extensionRoot>/.vscode-test/user-data`):
    // en un runner de GitHub ese path deja el socket IPC del proceso main por
    // encima del límite de `sun_path` y el editor muere con EINVAL antes de
    // correr un test. Ver helpers/userDataDir.ts. Primero que el repo fixture,
    // así un tmpdir imposible aborta sin dejar el repo huérfano en %TEMP%.
    const userDataDir = createUserDataDir();

    const repo = createTempRepo();
    process.env.GIT_REVIEW_FIXTURE_DIR = repo.dir;

    try {
        await runTests({
            extensionDevelopmentPath,
            extensionTestsPath,
            launchArgs: launchArgsFor(repo.dir, userDataDir),
        });
    } catch (err) {
        console.error("Failed to run integration tests", err);
        process.exitCode = 1;
    } finally {
        cleanupRepo(repo);
        removeUserDataDir(userDataDir);
    }
}

main();
