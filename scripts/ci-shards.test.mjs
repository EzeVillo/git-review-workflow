import assert from "node:assert/strict";
import {chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import {execFileSync} from "node:child_process";
import {tmpdir} from "node:os";
import path from "node:path";
import {test} from "node:test";
import sharding from "./ci-shards.cjs";

const {planShards, selectShard, readShardSettings, listSuiteFiles, readProfile, validateWorkflow,
    unitsFor, batsNames, parseBatsNames, batsManifest, escapeRegex, platformName} = sharding;
const config = {shards: 3, fixedMilliseconds: 10, defaultMilliseconds: 40,
    files: {a: 100, b: 90, c: 80, d: 30, e: 20, f: 10}, splitFiles: [], cases: {}};
const profile = {suites: {bats: {windows: config}}};
const plan = (files, count, p = profile) => planShards("bats", files, count, p, "windows");

test("balances measured durations instead of positions in the file list", () => {
    const shards = plan(["a", "b", "c", "d", "e", "f"], 3);
    assert.deepEqual(shards.map(shard => shard.estimatedMilliseconds), [120, 120, 120]);
    assert.deepEqual(shards.map(shard => shard.files), [["a", "f"], ["b", "e"], ["c", "d"]]);
});

test("whole files belong to exactly one nonempty shard and new files stay covered", () => {
    const files = ["a", "b", "c", "d", "e", "f", "new-file"];
    for (let count = 1; count <= files.length; count++) {
        const shards = plan(files, count);
        assert.ok(shards.every(shard => shard.units.length > 0));
        assert.deepEqual(shards.flatMap(shard => shard.files).sort(), files.toSorted());
    }
    assert.equal(plan(["new-file"], 1)[0].estimatedMilliseconds, 50);
});

test("audited files split by independent case and retain new cases exactly once", () => {
    const measured = {fixedMilliseconds: 0, defaultMilliseconds: 20, files: {a: 90, b: 10},
        splitFiles: ["a"], cases: {a: {slow: 60, quick: 30}}};
    const inventory = {a: ["quick", "new", "slow"]};
    const shards = planShards("bats", ["a", "b"], 3, {suites: {bats: {windows: measured}}}, "windows", inventory);
    assert.deepEqual(shards.flatMap(s => s.units.map(u => [u.file, u.name ?? null])).sort(),
        [["a", "new"], ["a", "quick"], ["a", "slow"], ["b", null]].sort());
    assert.deepEqual(shards.map(s => s.estimatedMilliseconds), [60, 45, 40]);
    assert.deepEqual(unitsFor("vscode", ["a"], measured).map(u => u.name).sort(), ["quick", "slow"]);
    assert.throws(() => unitsFor("vscode", ["a"], measured, {a: ["same", "same"]}));
    assert.throws(() => unitsFor("vscode", ["a"], {...measured, cases: {}}));
});

test("zero-cost skips produce nonempty partitions and enumeration order is irrelevant", () => {
    const zero = {suites: {bats: {windows: {...config, fixedMilliseconds: 0, defaultMilliseconds: 0, files: {}}}}};
    assert.deepEqual(plan(["a", "b", "c"], 3, zero).map(s => s.files), [["a"], ["b"], ["c"]]);
    assert.deepEqual(plan(["a", "b", "c", "d"], 3), plan(["d", "c", "b", "a"], 3));
    assert.deepEqual(plan(["c", "a", "b"], 1)[0].files, ["a", "b", "c"]);
});

test("partial-file preprocessing is charged once and affects case placement", () => {
    const config = {fixedMilliseconds: 0, partialFileMilliseconds: 20, defaultMilliseconds: 10,
        files: {a: 60, b: 35}, splitFiles: ["a"], cases: {a: {slow: 30, medium: 20, quick: 10}}};
    const shards = planShards("vscode", ["a", "b"], 2, {suites: {vscode: {windows: config}}}, "windows");
    assert.deepEqual(shards.map(shard => shard.estimatedMilliseconds), [65, 70]);
    assert.equal(shards[1].units.filter(unit => unit.file === "a").length, 2);
    assert.throws(() => planShards("vscode", ["a"], 1,
        {suites: {vscode: {windows: {...config, partialFileMilliseconds: -1}}}}, "windows"));
});

test("Bats filters match literal complete titles and keep files with duplicate titles separate", () => {
    const title = 'a [path].* (x)? $name + "quoted" | end';
    const manifest = batsManifest({files: ["one.bats", "two.bats"], units: [{file: "one.bats", name: title}, {file: "two.bats"}]});
    const rows = manifest.split("\n").map(row => row.split("\t"));
    assert.equal(new RegExp(rows[0][1]).test(title), true);
    assert.equal(new RegExp(rows[0][1]).test(title + " extra"), false);
    assert.equal(rows[0][2], "1");
    assert.deepEqual(rows[1], ["two.bats", ".*", "-"]);
    assert.throws(() => batsManifest({files: ["a\tb"], units: [{file: "a\tb"}]}));
    assert.equal(new RegExp(`^${escapeRegex("a\\b[0]")}$`).test("a\\b[0]"), true);
    assert.ok(batsNames("tests/save.bats").includes('review list shows a saved review under "saved"'));
    assert.deepEqual(parseBatsNames('  @test "new indented case" { :; }\n', "fixture"), ["new indented case"]);
    const quoted = '@test "a \\"quoted\\" title" { :; }\n';
    assert.deepEqual(parseBatsNames(quoted, "fixture"), ['a "quoted" title']);
    const raw = parseBatsNames(quoted, "fixture", true)[0];
    const quoteFilter = batsManifest({files: ["quoted.bats"], units: [{file: "quoted.bats", name: 'a "quoted" title', filterName: raw}]}).split("\t")[1];
    assert.equal(new RegExp(quoteFilter).test(raw), true);
    assert.equal(new RegExp(quoteFilter).test('a "quoted" title'), false);
    assert.throws(() => parseBatsNames('@test "covered" { :; }\n  @test single-quoted { :; }\n', "fixture"));
});

test("rejects invalid settings, platforms, costs, and empty or duplicate inputs", () => {
    assert.deepEqual(readShardSettings(undefined, undefined), {index: 1, count: 1});
    assert.deepEqual(readShardSettings("2", "3"), {index: 2, count: 3});
    for (const args of [["2", undefined], [undefined, "3"], ["0", "3"], ["4", "3"], ["1.5", "3"], ["1", "bad"]]) assert.throws(() => readShardSettings(...args));
    assert.throws(() => selectShard("bats", ["a"], 2, 1, profile, "windows"));
    assert.throws(() => plan(["a"], 2));
    assert.throws(() => plan([], 1));
    assert.throws(() => plan(["a", "a"], 1));
    assert.throws(() => planShards("missing", ["a"], 1, profile, "windows"));
    assert.throws(() => plan(["a"], 1, {suites: {bats: {windows: {...config, files: {a: -1}}}}}));
    assert.throws(() => platformName("unknown"));
    assert.equal(platformName("darwin"), "macos");
    assert.equal(platformName("Windows"), "windows");
});

test("all six actual partitions cover each case once within the eight-minute plan", () => {
    const actual = readProfile();
    const yaml = readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8");
    assert.deepEqual(validateWorkflow(yaml, actual), []);
    assert.equal(actual.maximumMilliseconds, 600000);
    assert.equal(actual.targetMilliseconds, 480000);
    for (const suite of ["bats", "vscode"]) for (const platform of ["linux", "macos", "windows"]) {
        const files = listSuiteFiles(suite), config = actual.suites[suite][platform];
        const shards = planShards(suite, files, config.shards, actual, platform);
        const key = u => `${u.file}\0${u.name ?? ""}`;
        assert.deepEqual(shards.flatMap(s => s.units).map(key).sort(), unitsFor(suite, files, config).map(key).sort());
        assert.ok(shards.every(s => s.units.length > 0 && s.estimatedMilliseconds <= actual.targetMilliseconds));
    }
});

test("workflow drift cannot drop or duplicate shards on any platform or omit a dependency", () => {
    const actual = readProfile();
    const yaml = readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8");
    for (const os of ["ubuntu-latest", "macos-latest", "windows-latest"]) {
        const row = yaml.match(new RegExp(`^.*- \\{ os: ${os}, shard: 2, shards: \\d+ \\}.*$`, "m"))?.[0];
        assert.ok(row);
        assert.ok(validateWorkflow(yaml.replace(row, ""), actual).length > 0);
        assert.ok(validateWorkflow(yaml.replace(row, row.replace("shard: 2", "shard: 1")), actual).length > 0);
    }
    assert.ok(validateWorkflow(yaml.replace("needs: [lint, test,", "needs: [test,"), actual).length > 0);
    assert.ok(validateWorkflow(yaml.replace("run: sh scripts/ci-bats.sh", "run: bats tests/"), actual).length > 0);
    assert.ok(validateWorkflow(yaml.replace("name: CI duration budget", "name: Other report"), actual).length > 0);
});

test("the Bats runner isolates stdin and preserves failures while checking every file", {skip: process.platform === "win32"}, () => {
    const temporary = mkdtempSync(path.join(tmpdir(), "ci-bats-runner-"));
    try {
        const stub = path.join(temporary, "bats"), calls = path.join(temporary, "calls");
        const actual = readProfile(), config = actual.suites.bats.windows;
        const shards = planShards("bats", listSuiteFiles("bats"), config.shards, actual, "windows");
        const index = shards.findIndex(shard => shard.files.length > 1);
        assert.ok(index >= 0);
        const selected = shards[index];
        for (const wrongCount of [false, true]) {
            const cases = selected.files.map(file => {
                assert.match(file, /^[a-zA-Z0-9/.\-]+$/);
                return `'${file}') printf '1..%s\\r\\n' ${selected.units.filter(unit => unit.file === file).length + Number(wrongCount)};;`;
            }).join("\n");
            writeFileSync(calls, "");
            writeFileSync(stub, `#!/bin/sh\nset -eu\nfor value; do :; done\ncat >/dev/null\ncase "$value" in\n${cases}\nesac\nprintf "%s\\n" "$value" >>"$CI_BATS_CALLS"\nexit ${wrongCount ? 0 : 1}\n`);
            chmodSync(stub, 0o755);
            assert.throws(() => execFileSync("sh", ["scripts/ci-bats.sh"], {
                cwd: new URL("..", import.meta.url), encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: {...process.env,
                    PATH: `${temporary}${path.delimiter}${process.env.PATH}`, CI_BATS_CALLS: calls,
                    TEST_SHARD: String(index + 1), TEST_SHARDS: String(config.shards), RUNNER_OS: "Windows"}
            }), error => error.status === 1 && /selected \d+ cases; expected \d+/.test(error.stderr) === wrongCount);
            assert.deepEqual(readFileSync(calls, "utf8").trim().split("\n"), selected.files);
        }
    } finally { rmSync(temporary, {recursive: true, force: true}); }
});
