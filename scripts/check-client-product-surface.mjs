#!/usr/bin/env node
/**
 * Anti-drift check: contracts/client-product-surface.yaml vs both clients.
 * Fails on missing YAML, schema issues, min_cli_version / npm / string drift,
 * and action-count mismatch vs vscode-extension package.json.
 */
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const yamlPath = join(root, "contracts", "client-product-surface.yaml");

function fail(msg) {
  console.error(`check-client-product-surface: ${msg}`);
  process.exit(1);
}

if (!existsSync(yamlPath)) {
  fail(`missing ${yamlPath}`);
}

const text = readFileSync(yamlPath, "utf8");

function scalar(key) {
  const m = text.match(new RegExp(`^${key}:\\s*"([^"]*)"`, "m"));
  if (!m) fail(`missing scalar ${key}`);
  return m[1];
}

const min = scalar("min_cli_version");
const npmInstall = scalar("npm_install");
const npmUpdate = scalar("npm_update");

// Count actions under `actions:`
const actionsBlock = text.split(/^actions:\s*$/m)[1];
if (!actionsBlock) fail("missing actions: block");
const actionKeys = [...actionsBlock.matchAll(/^ {2}([A-Za-z][A-Za-z0-9]*):/gm)].map((m) => m[1]);
if (actionKeys.length !== 27) {
  fail(`expected 27 actions, found ${actionKeys.length}: ${actionKeys.join(", ")}`);
}

// VS Code package.json commands
const pkgPath = join(root, "vscode-extension", "package.json");
const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
const commands = pkg.contributes?.commands ?? [];
if (commands.length !== 27) {
  fail(`vscode package.json has ${commands.length} commands, expected 27`);
}
const cmdIds = commands.map((c) => c.command.replace(/^gitReview\./, ""));
for (const id of cmdIds) {
  if (!actionKeys.includes(id)) fail(`YAML missing action for command ${id}`);
}
for (const id of actionKeys) {
  if (!cmdIds.includes(id)) fail(`YAML action ${id} not in package.json commands`);
}

// VS Code constants
const versionTs = readFileSync(join(root, "vscode-extension", "src", "cli", "version.ts"), "utf8");
const installTs = readFileSync(join(root, "vscode-extension", "src", "cli", "installHint.ts"), "utf8");
if (!versionTs.includes(`"${min}"`)) {
  fail(`vscode version.ts does not contain min_cli_version ${min}`);
}
if (!installTs.includes(npmInstall)) {
  fail(`vscode installHint.ts missing npm_install`);
}
if (!installTs.includes(npmUpdate)) {
  fail(`vscode installHint.ts missing npm_update`);
}

// IntelliJ domain constants (if present)
const ijVersion = join(root, "intellij-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "domain", "Version.kt");
const ijInstall = join(root, "intellij-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "domain", "InstallHint.kt");
if (existsSync(ijVersion)) {
  const v = readFileSync(ijVersion, "utf8");
  if (!v.includes(`"${min}"`)) fail(`intellij Version.kt missing min ${min}`);
}
if (existsSync(ijInstall)) {
  const i = readFileSync(ijInstall, "utf8");
  if (!i.includes(npmInstall)) fail(`intellij InstallHint.kt missing npm_install`);
  if (!i.includes(npmUpdate)) fail(`intellij InstallHint.kt missing npm_update`);
}

// multi_root_error substring in both state managers
const multi = "multi-root is not supported";
const vsState = readFileSync(join(root, "vscode-extension", "src", "review", "state.ts"), "utf8");
if (!vsState.includes(multi)) fail("vscode state.ts missing multi_root_error fragment");
const ijState = join(root, "intellij-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "host", "ReviewStateManager.kt");
if (existsSync(ijState)) {
  const s = readFileSync(ijState, "utf8");
  if (!s.includes(multi)) fail("intellij ReviewStateManager missing multi_root_error fragment");
}

// no_base_candidates
if (!text.includes("No branches to pick a base from were found.")) {
  fail("YAML missing no_base_candidates string");
}
const setBase = readFileSync(join(root, "vscode-extension", "src", "commands", "setBase.ts"), "utf8");
if (!setBase.includes("No branches to pick a base from were found.")) {
  fail("setBase.ts missing no_base_candidates");
}

// cli_outdated must keep "installed"
if (!text.includes("The installed git-review CLI is older than")) {
  fail('cli_outdated_title must include "installed"');
}

console.log(`check-client-product-surface: ok (min=${min}, actions=${actionKeys.length})`);
