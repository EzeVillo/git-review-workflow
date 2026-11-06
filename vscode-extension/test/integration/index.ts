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
    const sharding = require(path.resolve(testsRoot, "../../../../scripts/ci-shards.cjs")) as {
        readShardSettings: (index: string | undefined, count: string | undefined) => {index: number; count: number};
        selectShard: (suite: string, files: string[], index: number, count: number) => string[];
    };
    const shard = sharding.readShardSettings(process.env.VSCODE_TEST_SHARD, process.env.VSCODE_TEST_SHARDS);
    const selected = new Set(sharding.selectShard("vscode", files, shard.index, shard.count));
    console.log(`Integration shard ${shard.index}/${shard.count}: ${selected.size}/${files.length} files (${[...selected].join(", ")})`);
    // Preserve Mocha's existing file order inside each complete-file partition.
    files.filter(file => selected.has(file)).forEach(file => mocha.addFile(path.resolve(testsRoot, file)));

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
