import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {createHash} from "node:crypto";
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {basename, delimiter, join} from "node:path";
import test from "node:test";

const workflow = readFileSync(new URL("../.github/workflows/release-vscode.yml", import.meta.url), "utf8");
const steps = workflow.replace(/\r\n/g, "\n").split(/^      - name: /m).slice(1);
const version = "1.2.3";
const tag = "vscode-v" + version;
const filename = "git-review-workflow-" + version + ".vsix";
const built = "vscode-extension/" + filename;
const repository = "example/git-review-workflow";

function runStep(name, cwd, env) {
    const step = steps.find(block => block.startsWith(name + "\n"));
    assert.ok(step, "missing workflow step " + name);
    const script = step.split(/^        run: \|\n/m)[1];
    assert.ok(script, "missing run block in " + name);
    const result = spawnSync("bash", ["-e", "-c", script.replace(/^ {10}/gm, "")], {cwd, env, encoding: "utf8"});
    assert.ifError(result.error);
    assert.equal(result.signal, null);
    return result;
}

const mock = `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const tool = path.basename(process.argv[1]);
const args = process.argv.slice(2);
const asset = tool === "npx" && args[1] === "publish" ? fs.readFileSync(args[3], "utf8") : undefined;
fs.appendFileSync(process.env.AUDIT_LOG, JSON.stringify({tool, args, asset}) + "\\n");
if (tool === "gh") {
    switch (args[1]) {
    case "view": process.exit(process.env.AUDIT_RECOVER === "yes" ? 0 : 1);
    case "download":
        fs.writeFileSync(path.join(args[8], args[6]), "original tagged bytes");
        break;
    case "create":
        if (fs.readFileSync(args[3], "utf8") !== "new build bytes") process.exit(92);
        break;
    case "edit": break;
    default: process.exit(93);
    }
} else if (args[1] === "show") {
    if (process.env.AUDIT_METADATA === "unavailable") process.exit(1);
    console.log(process.env.AUDIT_METADATA);
} else if (args[1] === "publish") {
    process.exit(Number(process.env.AUDIT_PUBLISH_EXIT));
} else {
    process.exit(94);
}
`;

const listing = bytes => JSON.stringify({versions: [{version, properties: [{
    key: "Microsoft.VisualStudio.Services.VsixSha256",
    value: createHash("sha256").update(bytes).digest("hex"),
}]}]});

for (const scenario of [
    {name: "first release uploads the artifact it just attached", metadata: "unavailable", publishes: true, status: 0},
    {name: "retry uploads the recovered archive when its version is absent", recover: true, metadata: "undefined", publishes: true, status: 0},
    {name: "retry skips an upload only if the recovered archive matches", recover: true, metadata: listing("original tagged bytes"), status: 0},
    {name: "different Marketplace bytes block finalization", recover: true, metadata: listing("other bytes"), status: 2},
    {name: "upload failure blocks finalization and preserves its exit code", recover: true, metadata: "undefined", publishes: true, status: 19},
]) {
    test(scenario.name, t => {
        const cwd = mkdtempSync(join(tmpdir(), "release-vscode-test-"));
        t.after(() => rmSync(cwd, {recursive: true, force: true}));
        const tools = join(cwd, "tools");
        const output = join(cwd, "output");
        const trace = join(cwd, "trace");
        mkdirSync(tools);
        mkdirSync(join(cwd, "vscode-extension", "scripts"), {recursive: true});
        writeFileSync(join(cwd, built), "new build bytes");
        writeFileSync(join(cwd, "vscode-extension", "CHANGELOG.md"), "## [1.2.3]\n\nRelease notes.\n");
        copyFileSync(new URL("../vscode-extension/scripts/marketplace-vsix-status.mjs", import.meta.url),
            join(cwd, "vscode-extension", "scripts", "marketplace-vsix-status.mjs"));
        for (const tool of ["npx", "gh"]) writeFileSync(join(tools, tool), mock, {mode: 0o755});
        const env = {
            ...process.env, PATH: tools + delimiter + process.env.PATH, TMPDIR: cwd,
            GITHUB_OUTPUT: output, GITHUB_REF_NAME: tag, GITHUB_REPOSITORY: repository,
            VERSION: version, PUBLISH_TOKEN: "fake-test-token",
            AUDIT_LOG: trace, AUDIT_RECOVER: scenario.recover ? "yes" : "no",
            AUDIT_METADATA: scenario.metadata, AUDIT_PUBLISH_EXIT: scenario.status === 19 ? "19" : "0",
        };

        const recovered = runStep("Create or recover the GitHub release artifact", cwd, env);
        assert.equal(recovered.status, 0, recovered.stderr);
        const asset = readFileSync(output, "utf8").match(/^vsix=(.+)\n$/)?.[1];
        assert.ok(asset, "no VSIX output");
        assert.equal(basename(asset), filename);
        const published = runStep("Publish the release VSIX to the VS Code Marketplace", cwd, {...env, VSIX: asset});
        assert.equal(published.status, scenario.status, published.stderr);
        if (published.status === 0) {
            const finalized = runStep("Publish the GitHub release", cwd, env);
            assert.equal(finalized.status, 0, finalized.stderr);
        }

        const calls = readFileSync(trace, "utf8").trimEnd().split("\n").map(line => JSON.parse(line));
        assert.deepEqual(calls.map(({tool, args}) => [tool, ...args.slice(0, 2)]), [
            ["gh", "release", "view"],
            ["gh", "release", scenario.recover ? "download" : "create"],
            ["npx", "vsce", "show"],
            ...(scenario.publishes ? [["npx", "vsce", "publish"]] : []),
            ...(scenario.status === 0 ? [["gh", "release", "edit"]] : []),
        ]);
        assert.deepEqual(calls[2].args, ["vsce", "show", "EzeVillo.git-review-workflow", "--json"]);
        if (scenario.recover) {
            assert.deepEqual(calls[1].args.slice(0, 8),
                ["release", "download", tag, "--repo", repository, "--pattern", filename, "--dir"]);
            assert.equal(asset, join(calls[1].args[8], filename));
        } else {
            assert.equal(asset, built);
            assert.deepEqual(calls[1].args.slice(0, 6), ["release", "create", tag, asset, "--repo", repository]);
            assert.ok(calls[1].args.includes("--draft"));
        }
        if (scenario.publishes) {
            assert.deepEqual(calls[3], {
                tool: "npx", args: ["vsce", "publish", "--packagePath", asset, "--pat", "fake-test-token"],
                asset: scenario.recover ? "original tagged bytes" : "new build bytes",
            });
        }
        if (scenario.status === 0) assert.ok(calls.at(-1).args.includes("--draft=false"));
    });
}
