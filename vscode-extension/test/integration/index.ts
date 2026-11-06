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
        platformName: (value?: string) => string;
        readProfile: () => unknown;
        escapeRegex: (value: string) => string;
        selectShard: (suite: string, files: string[], index: number, count: number, profile: unknown, platform: string,
            inventory: Record<string, string[]>) => {files: string[]; units: {file: string; name?: string}[]};
    };
    const shard = sharding.readShardSettings(process.env.VSCODE_TEST_SHARD, process.env.VSCODE_TEST_SHARDS);
    // Discover real tests before selecting: new cases participate immediately.
    // grep preserves Mocha's hooks and original order; it does not run tests in
    // parallel inside the editor or remove their beforeEach/afterEach fixtures.
    files.forEach(file => mocha.addFile(path.resolve(testsRoot, file)));
    await mocha.loadFilesAsync();
    const tests: Mocha.Test[] = [];
    mocha.suite.eachTest(test => tests.push(test));
    if (shard.count > 1 && new Set(tests.map(test => test.fullTitle())).size !== tests.length) {
        throw new Error("Integration sharding requires unique complete test titles.");
    }
    const inventory: Record<string, string[]> = {};
    const fileOf = (test: Mocha.Test): string => path.relative(testsRoot, test.file!).replace(/\\/g, "/");
    for (const test of tests) (inventory[fileOf(test)] ??= []).push(test.title);
    const selected = sharding.selectShard("vscode", files, shard.index, shard.count, sharding.readProfile(),
        sharding.platformName(process.env.RUNNER_OS), inventory);
    const diagnostic = process.env.MOCHA_GREP ? new RegExp(process.env.MOCHA_GREP) : undefined;
    const titles = tests.filter(test => selected.units.some(unit => unit.file === fileOf(test) &&
        (unit.name === undefined || unit.name === test.title)) && (!diagnostic || diagnostic.test(test.fullTitle())))
        .map(test => test.fullTitle());
    if (!titles.length) throw new Error("Integration shard selected no tests.");
    mocha.grep(new RegExp(`^(${titles.map(sharding.escapeRegex).join("|")})$`));
    console.log(`Integration shard ${shard.index}/${shard.count}: ${titles.length}/${tests.length} tests (${selected.files.join(", ")})`);
    console.log(`Integration cases: ${JSON.stringify(titles)}`);

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
