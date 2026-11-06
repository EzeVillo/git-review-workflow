"use strict";

const {appendFileSync, readFileSync, readdirSync} = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");

function readProfile() {
    return JSON.parse(readFileSync(path.join(root, ".github/ci/windows-timings.json"), "utf8"));
}

function readShardSettings(index, count) {
    if (index === undefined && count === undefined) return {index: 1, count: 1};
    if (!/^[1-9][0-9]*$/.test(index ?? "") || !/^[1-9][0-9]*$/.test(count ?? "")) {
        throw new Error("Shard index and count must both be positive integers.");
    }
    const parsed = {index: Number(index), count: Number(count)};
    if (!Number.isSafeInteger(parsed.index) || !Number.isSafeInteger(parsed.count) || parsed.index > parsed.count) {
        throw new Error("Shard index must be within the configured count.");
    }
    return parsed;
}

// Keep entire files together: their before/after and setup_file lifecycles must
// stay intact. Longest-processing-time assignment balances real Windows costs.
function planShards(suite, files, count, profile = readProfile()) {
    const config = profile.suites[suite];
    if (!config) throw new Error(`Unknown test suite: ${suite}`);
    if (!Number.isFinite(config.fixedMilliseconds) || config.fixedMilliseconds < 0) throw new Error("Invalid fixed runner duration.");
    if (!files.length || new Set(files).size !== files.length) throw new Error("Test files must be nonempty and unique.");
    if (!Number.isSafeInteger(count) || count < 1 || count > files.length) throw new Error("Invalid shard count.");
    const durations = files.map(file => {
        const milliseconds = config.files[file] ?? config.defaultMilliseconds;
        if (!Number.isFinite(milliseconds) || milliseconds < 0) throw new Error(`Invalid duration for ${file}`);
        return {file, milliseconds};
    }).sort((a, b) => b.milliseconds - a.milliseconds || (a.file < b.file ? -1 : a.file > b.file ? 1 : 0));
    const shards = Array.from({length: count}, () => ({files: [], estimatedMilliseconds: config.fixedMilliseconds}));
    for (const item of durations) {
        const shard = shards.reduce((best, candidate) => candidate.estimatedMilliseconds < best.estimatedMilliseconds ||
            (candidate.estimatedMilliseconds === best.estimatedMilliseconds && candidate.files.length < best.files.length) ? candidate : best);
        shard.files.push(item.file);
        shard.estimatedMilliseconds += item.milliseconds;
    }
    for (const shard of shards) shard.files.sort();
    return shards;
}

function selectShard(suite, files, index, count, profile = readProfile()) {
    if (!Number.isSafeInteger(index) || index < 1 || index > count) throw new Error("Invalid shard index.");
    return planShards(suite, files, count, profile)[index - 1].files;
}

function listSuiteFiles(suite) {
    if (suite === "bats") return readdirSync(path.join(root, "tests")).filter(name => name.endsWith(".bats")).map(name => `tests/${name}`).sort();
    if (suite === "vscode") {
        const directory = path.join(root, "vscode-extension/test/integration");
        const visit = relative => readdirSync(path.join(directory, relative), {withFileTypes: true}).flatMap(entry => {
            const name = relative ? `${relative}/${entry.name}` : entry.name;
            if (entry.isDirectory()) return visit(name);
            return entry.isFile() && name.endsWith(".spec.ts") ? [name.replace(/\.ts$/, ".js")] : [];
        });
        return visit("").sort();
    }
    throw new Error(`Unknown test suite: ${suite}`);
}

function validateWorkflow(yaml, profile = readProfile()) {
    const errors = [];
    for (const [suite, job] of [["bats", "test"], ["vscode", "vscode-extension"]]) {
        const block = yaml.split(new RegExp(`^  ${job}:\\s*$`, "m"))[1]?.split(/^  [\w-]+:/m)[0] ?? "";
        const rows = [...block.matchAll(/^\s*-\s*\{\s*os:\s*windows-latest,\s*shard:\s*(\d+),\s*shards:\s*(\d+)\s*\}/gm)];
        const count = profile.suites[suite].shards;
        const indices = rows.map(row => Number(row[1])).sort((a, b) => a - b);
        if (JSON.stringify(indices) !== JSON.stringify(Array.from({length: count}, (_, i) => i + 1)) || rows.some(row => Number(row[2]) !== count)) {
            errors.push(`${job}: expected exactly Windows shards 1..${count}, each with shards=${count}`);
        }
    }
    const jobs = (yaml.split(/^jobs:\s*$/m)[1] ?? "").match(/^  [\w-]+:\s*$/gm)?.map(line => line.trim().slice(0, -1)) ?? [];
    const report = yaml.split(/^  windows-duration-budget:\s*$/m)[1] ?? "";
    const awaited = report.match(/^    needs:\s*\[([^\]]+)\]/m)?.[1].split(",").map(job => job.trim()).sort();
    if (JSON.stringify(awaited) !== JSON.stringify(jobs.filter(job => job !== "windows-duration-budget").sort())) {
        errors.push("The duration budget must wait for every CI job.");
    }
    return errors;
}

function check() {
    const profile = readProfile();
    const errors = validateWorkflow(readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8"), profile);
    const lines = ["## Windows test distribution", "", "| Suite | Shard | Files | Estimated minutes |", "|---|---:|---:|---:|"];
    for (const suite of ["bats", "vscode"]) {
        const files = listSuiteFiles(suite);
        const plan = planShards(suite, files, profile.suites[suite].shards, profile);
        if (new Set(plan.flatMap(shard => shard.files)).size !== files.length) errors.push(`${suite}: incomplete file coverage`);
        for (const [index, shard] of plan.entries()) {
            lines.push(`| ${suite} | ${index + 1} | ${shard.files.length} | ${(shard.estimatedMilliseconds / 60000).toFixed(2)} |`);
            if (shard.estimatedMilliseconds > profile.targetMilliseconds) errors.push(`${suite} shard ${index + 1} exceeds the planned Windows budget`);
        }
    }
    console.log(lines.join("\n"));
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join("\n") + "\n");
    if (errors.length) throw new Error(errors.join("\n"));
}

module.exports = {readProfile, readShardSettings, planShards, selectShard, listSuiteFiles, validateWorkflow};
if (require.main === module) {
    try {
        const [suite, index, count] = process.argv.slice(2);
        if (suite === "check") check();
        else {
            const settings = readShardSettings(index, count);
            console.log(selectShard(suite, listSuiteFiles(suite), settings.index, settings.count).join("\n"));
        }
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
