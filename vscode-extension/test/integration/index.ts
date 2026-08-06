import * as path from "path";
import Mocha from "mocha";
import {glob} from "glob";

export async function run(): Promise<void> {
    const mocha = new Mocha({
        ui: "bdd",
        timeout: 30000,
        // Opcional: `MOCHA_GREP=US4` para acotar una corrida de diagnóstico.
        grep: process.env.MOCHA_GREP || undefined,
    });
    const testsRoot = path.resolve(__dirname);

    const all = await glob("**/*.spec.js", {cwd: testsRoot});
    // Opcional: `MOCHA_FILE=finish-review` carga sólo specs cuyo path lo
    // contenga (diagnóstico de una suite sin arrastrar open-entry flaky).
    const filter = process.env.MOCHA_FILE;
    const files = filter ? all.filter((f) => f.includes(filter)) : all;
    files.forEach((f) => mocha.addFile(path.resolve(testsRoot, f)));

    return new Promise((resolve, reject) => {
        mocha.run((failures) => {
            if (failures > 0) {
                reject(new Error(`${failures} tests failed.`));
            } else {
                resolve();
            }
        });
    });
}
