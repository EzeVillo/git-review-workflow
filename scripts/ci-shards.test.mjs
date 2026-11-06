import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {test} from "node:test";
import sharding from "./ci-shards.cjs";

const {planShards, selectShard, readShardSettings, listSuiteFiles, readProfile, validateWorkflow} = sharding;
const profile = {suites: {bats: {shards: 3, fixedMilliseconds: 10, defaultMilliseconds: 40,
    files: {a: 100, b: 90, c: 80, d: 30, e: 20, f: 10}}}};

test("balances measured durations instead of positions in the file list", () => {
    const plan = planShards("bats", ["a", "b", "c", "d", "e", "f"], 3, profile);
    assert.deepEqual(plan.map(shard => shard.estimatedMilliseconds), [120, 120, 120]);
    assert.deepEqual(plan.map(shard => shard.files), [["a", "f"], ["b", "e"], ["c", "d"]]);
});

test("each file belongs to exactly one nonempty shard", () => {
    const files = ["a", "b", "c", "d", "e", "f", "new-file"];
    for (let count = 1; count <= files.length; count++) {
        const shards = Array.from({length: count}, (_, i) => selectShard("bats", files, i + 1, count, profile));
        assert.ok(shards.every(shard => shard.length > 0));
        assert.deepEqual(shards.flat().sort(), files.toSorted());
        assert.equal(new Set(shards.flat()).size, files.length);
    }
});

test("new files get a fallback duration and remain covered", () => {
    const plan = planShards("bats", ["a", "new-file"], 2, profile);
    assert.deepEqual(plan.map(shard => shard.estimatedMilliseconds), [110, 50]);
    assert.deepEqual(plan.flatMap(shard => shard.files).sort(), ["a", "new-file"]);
});

test("zero-cost platform skips still belong to nonempty partitions", () => {
    const zero = {suites: {bats: {shards: 3, fixedMilliseconds: 0, defaultMilliseconds: 0, files: {}}}};
    const plan = planShards("bats", ["a", "b", "c"], 3, zero);
    assert.deepEqual(plan.map(shard => shard.files), [["a"], ["b"], ["c"]]);
});

test("planning is deterministic regardless of enumeration order", () => {
    const files = ["a", "b", "c", "d", "e", "f"];
    assert.deepEqual(planShards("bats", files, 3, profile), planShards("bats", files.toReversed(), 3, profile));
});

test("unsharded runs retain the complete suite", () => {
    assert.deepEqual(selectShard("bats", ["c", "a", "b"], 1, 1, profile), ["a", "b", "c"]);
});

test("rejects invalid or incomplete shard settings", () => {
    assert.deepEqual(readShardSettings(undefined, undefined), {index: 1, count: 1});
    assert.deepEqual(readShardSettings("2", "3"), {index: 2, count: 3});
    for (const args of [["2", undefined], [undefined, "3"], ["0", "3"], ["4", "3"], ["1.5", "3"], ["1", "bad"]]) {
        assert.throws(() => readShardSettings(...args));
    }
    assert.throws(() => selectShard("bats", ["a"], 2, 1, profile));
    assert.throws(() => planShards("bats", ["a"], 2, profile));
    assert.throws(() => planShards("bats", [], 1, profile));
    assert.throws(() => planShards("bats", ["a", "a"], 1, profile));
    assert.throws(() => planShards("missing", ["a"], 1, profile));
});

test("the actual Windows matrices cover both complete suites within the measured budget", () => {
    const actual = readProfile();
    const yaml = readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8");
    assert.deepEqual(validateWorkflow(yaml, actual), []);
    for (const suite of ["bats", "vscode"]) {
        const files = listSuiteFiles(suite);
        const plan = planShards(suite, files, actual.suites[suite].shards, actual);
        assert.deepEqual(plan.flatMap(shard => shard.files).sort(), files.toSorted());
        assert.ok(plan.every(shard => shard.estimatedMilliseconds <= actual.targetMilliseconds));
        assert.ok(actual.targetMilliseconds < actual.reference.milliseconds);
    }
});

test("workflow drift cannot drop or duplicate a Windows shard", () => {
    const actual = readProfile();
    const yaml = readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8");
    const row = "          - { os: windows-latest, shard: 2, shards: 12 }";
    assert.ok(yaml.includes(row));
    assert.ok(validateWorkflow(yaml.replace(row, ""), actual).length > 0);
    assert.ok(validateWorkflow(yaml.replace(row, row.replace("shard: 2", "shard: 1")), actual).length > 0);
    assert.ok(validateWorkflow(yaml.replace(row, row.replace("shards: 12", "shards: 13")), actual).length > 0);
    assert.ok(validateWorkflow(yaml.replace("needs: [lint, test,", "needs: [test,"), actual).length > 0);
});
