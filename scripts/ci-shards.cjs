"use strict";

const {appendFileSync, readFileSync, readdirSync} = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");

function readProfile() {
    return JSON.parse(readFileSync(path.join(root, ".github/ci/test-timings.json"), "utf8"));
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

function platformName(value = process.platform) {
    const names = {linux: "linux", Linux: "linux", "ubuntu-latest": "linux", darwin: "macos", macOS: "macos", macos: "macos", "macos-latest": "macos", win32: "windows", Windows: "windows", windows: "windows", "windows-latest": "windows"};
    if (!names[value]) throw new Error(`Unknown runner platform: ${value}`);
    return names[value];
}

function parseBatsNames(source, file, raw = false) {
    const sourceNames = [...source.matchAll(/^[\t ]*@test\s+"((?:[^"\\\r\n]|\\.)*)"\s*\{/gm)].map(match => match[1]);
    const names = sourceNames.map(name => name.replace(/\\(["\\$`])/g, "$1"));
    if (names.length !== (source.match(/^[\t ]*@test\s/gm) ?? []).length || !names.length || new Set(names).size !== names.length) {
        throw new Error(`Cannot enumerate unique literal test names in ${file}`);
    }
    return raw ? sourceNames : names;
}

function batsNames(file) { return parseBatsNames(readFileSync(path.join(root, file), "utf8"), file); }

// Only explicitly audited files split into cases: their fixtures reset before
// each test. Everything else retains its complete file lifecycle. Names come
// from current source/Bats or the loaded Mocha suite, so new cases stay covered.
function unitsFor(suite, files, config, inventory = {}) {
    return files.flatMap(file => {
        const milliseconds = config.files[file] ?? config.defaultMilliseconds;
        if (!Number.isFinite(milliseconds) || milliseconds < 0) throw new Error(`Invalid duration for ${file}`);
        if (!config.splitFiles?.includes(file)) return [{file, milliseconds}];
        const measured = config.cases[file];
        if (!measured || !Object.keys(measured).length) throw new Error(`Missing case timings for ${file}`);
        const names = inventory[file] ?? (suite === "bats" ? batsNames(file) : Object.keys(measured));
        // Bats filters the raw declaration, before its TAP formatter unescapes
        // quotes. Keep that identity separate from the displayed timing name.
        const filterNames = suite === "bats" && inventory[file] === undefined
            ? parseBatsNames(readFileSync(path.join(root, file), "utf8"), file, true) : names;
        if (!names.length || new Set(names).size !== names.length) throw new Error(`Duplicate or missing case names in ${file}`);
        return names.map((name, index) => {
            const weight = measured[name] ?? milliseconds / Object.keys(measured).length;
            if (!Number.isFinite(weight) || weight < 0) throw new Error(`Invalid case duration: ${file}: ${name}`);
            return {file, name, filterName: filterNames[index], milliseconds: weight};
        });
    });
}

function planShards(suite, files, count, profile = readProfile(), platform = platformName(), inventory = {}) {
    const config = profile.suites[suite]?.[platform];
    if (!config) throw new Error(`Unknown test suite/platform: ${suite}/${platform}`);
    if (!Number.isFinite(config.fixedMilliseconds) || config.fixedMilliseconds < 0) throw new Error("Invalid fixed runner duration.");
    if (!files.length || new Set(files).size !== files.length) throw new Error("Test files must be nonempty and unique.");
    const key = unit => `${unit.file}\0${unit.name ?? ""}`;
    const units = unitsFor(suite, files, config, inventory).sort((a, b) => b.milliseconds - a.milliseconds || (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));
    if (!Number.isSafeInteger(count) || count < 1 || count > units.length) throw new Error("Invalid shard count.");
    const shards = Array.from({length: count}, () => ({files: [], units: [], estimatedMilliseconds: config.fixedMilliseconds}));
    for (const item of units) {
        const shard = shards.reduce((best, candidate) => candidate.estimatedMilliseconds < best.estimatedMilliseconds ||
            (candidate.estimatedMilliseconds === best.estimatedMilliseconds && candidate.units.length < best.units.length) ? candidate : best);
        shard.units.push(item);
        shard.estimatedMilliseconds += item.milliseconds;
    }
    for (const shard of shards) shard.files = [...new Set(shard.units.map(unit => unit.file))].sort();
    return shards;
}

function selectShard(suite, files, index, count, profile = readProfile(), platform = platformName(), inventory = {}) {
    if (!Number.isSafeInteger(index) || index < 1 || index > count) throw new Error("Invalid shard index.");
    return planShards(suite, files, count, profile, platform, inventory)[index - 1];
}

function escapeRegex(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

function batsManifest(shard) {
    return shard.files.map(file => {
        const units = shard.units.filter(unit => unit.file === file);
        const whole = units.some(unit => unit.name === undefined);
        const filter = whole ? ".*" : `^(${units.map(unit => escapeRegex(unit.filterName ?? unit.name)).join("|")})$`;
        if (/[\t\r\n]/.test(file + filter)) throw new Error("Unsupported delimiter in Bats selection.");
        return `${file}\t${filter}\t${whole ? "-" : units.length}`;
    }).join("\n");
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
        if (suite === "bats" && !/^\s+run: sh scripts\/ci-bats\.sh\s*$/m.test(block)) {
            errors.push("Bats must execute the case selection, not just the file list.");
        }
        const rows = [...block.matchAll(/^\s*-\s*\{\s*os:\s*([\w-]+),\s*shard:\s*(\d+),\s*shards:\s*(\d+)\s*\}/gm)];
        for (const platform of ["linux", "macos", "windows"]) {
            const selected = rows.filter(row => platformName(row[1]) === platform);
            const count = profile.suites[suite][platform].shards;
            const indices = selected.map(row => Number(row[2])).sort((a, b) => a - b);
            if (JSON.stringify(indices) !== JSON.stringify(Array.from({length: count}, (_, i) => i + 1)) || selected.some(row => Number(row[3]) !== count)) {
                errors.push(`${job}: expected exactly ${platform} shards 1..${count}, each with shards=${count}`);
            }
        }
    }
    const jobs = (yaml.split(/^jobs:\s*$/m)[1] ?? "").match(/^  [\w-]+:\s*$/gm)?.map(line => line.trim().slice(0, -1)) ?? [];
    const report = yaml.split(/^  duration-budget:\s*$/m)[1] ?? "";
    const awaited = report.match(/^    needs:\s*\[([^\]]+)\]/m)?.[1].split(",").map(job => job.trim()).sort();
    if (JSON.stringify(awaited) !== JSON.stringify(jobs.filter(job => job !== "duration-budget").sort())) {
        errors.push("The duration budget must wait for every CI job.");
    }
    if (!/^    name: CI duration budget\s*$/m.test(report)) errors.push("The reporting job name must match its exclusion from timing.");
    return errors;
}

function check() {
    const profile = readProfile();
    const errors = validateWorkflow(readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8"), profile);
    const lines = ["## CI test distribution", "", "| Suite | Runner | Shards | Maximum estimated minutes |", "|---|---|---:|---:|"];
    for (const suite of ["bats", "vscode"]) for (const platform of ["linux", "macos", "windows"]) {
        const files = listSuiteFiles(suite);
        const config = profile.suites[suite][platform];
        const plan = planShards(suite, files, config.shards, profile, platform);
        const key = unit => `${unit.file}\0${unit.name ?? ""}`;
        const expected = unitsFor(suite, files, config).map(key).sort();
        const selected = plan.flatMap(shard => shard.units).map(key).sort();
        if (JSON.stringify(expected) !== JSON.stringify(selected)) errors.push(`${suite}/${platform}: incomplete or duplicate case coverage`);
        const maximum = Math.max(...plan.map(shard => shard.estimatedMilliseconds));
        lines.push(`| ${suite} | ${platform} | ${config.shards} | ${(maximum / 60000).toFixed(2)} |`);
        if (maximum > profile.targetMilliseconds) errors.push(`${suite}/${platform} exceeds the planned eight-minute budget`);
    }
    console.log(lines.join("\n"));
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join("\n") + "\n");
    if (errors.length) throw new Error(errors.join("\n"));
}

module.exports = {readProfile, readShardSettings, platformName, planShards, selectShard, listSuiteFiles, unitsFor, batsNames, parseBatsNames, batsManifest, escapeRegex, validateWorkflow};
if (require.main === module) {
    try {
        const [suite, index, count, platform] = process.argv.slice(2);
        if (suite === "check") check();
        else {
            const settings = readShardSettings(index, count);
            const shard = selectShard(suite, listSuiteFiles(suite), settings.index, settings.count, readProfile(), platformName(platform));
            console.log(suite === "bats" ? batsManifest(shard) : JSON.stringify(shard));
        }
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
