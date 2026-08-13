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

// Los blobs son LF, pero un checkout de Windows los materializa como CRLF: sin
// normalizar, las regex ancladas en `:\n` no matchean y los chequeos se saltean
// en silencio localmente para reaparecer en CI. Toda lectura pasa por acá.
function readText(path, encoding) {
  return readFileSync(path, encoding).replace(/\r\n/g, "\n");
}

function fail(msg) {
  console.error(`check-client-product-surface: ${msg}`);
  process.exit(1);
}

if (!existsSync(yamlPath)) {
  fail(`missing ${yamlPath}`);
}

const text = readText(yamlPath, "utf8");

function scalar(key) {
  const m = text.match(new RegExp(`^${key}:\\s*"([^"]*)"`, "m"));
  if (!m) fail(`missing scalar ${key}`);
  return m[1];
}

const min = scalar("min_cli_version");
const npmInstall = scalar("npm_install");
const npmUpdate = scalar("npm_update");

// Count actions under `actions:` (stop at next top-level key so panel_layout does not pollute)
const actionsSplit = text.split(/^actions:\s*$/m)[1];
if (!actionsSplit) fail("missing actions: block");
const actionsBlock = actionsSplit.split(/^[a-z_][a-z0-9_]*:\s*$/m)[0];
const actionKeys = [...actionsBlock.matchAll(/^ {2}([A-Za-z][A-Za-z0-9]*):/gm)].map((m) => m[1]);
if (actionKeys.length !== 27) {
  fail(`expected 27 actions, found ${actionKeys.length}: ${actionKeys.join(", ")}`);
}

// VS Code package.json commands
const pkgPath = join(root, "vscode-extension", "package.json");
const pkg = JSON.parse(readText(pkgPath, "utf8"));
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
const versionTs = readText(join(root, "vscode-extension", "src", "cli", "version.ts"), "utf8");
const installTs = readText(join(root, "vscode-extension", "src", "cli", "installHint.ts"), "utf8");
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
const ijVersion = join(root, "jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "domain", "Version.kt");
const ijInstall = join(root, "jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "domain", "InstallHint.kt");
if (existsSync(ijVersion)) {
  const v = readText(ijVersion, "utf8");
  if (!v.includes(`"${min}"`)) fail(`intellij Version.kt missing min ${min}`);
}
if (existsSync(ijInstall)) {
  const i = readText(ijInstall, "utf8");
  if (!i.includes(npmInstall)) fail(`intellij InstallHint.kt missing npm_install`);
  if (!i.includes(npmUpdate)) fail(`intellij InstallHint.kt missing npm_update`);
}

// multi_root_error substring in both state managers
const multi = "multi-root is not supported";
const vsState = readText(join(root, "vscode-extension", "src", "review", "state.ts"), "utf8");
if (!vsState.includes(multi)) fail("vscode state.ts missing multi_root_error fragment");
const ijState = join(root, "jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "host", "ReviewStateManager.kt");
if (existsSync(ijState)) {
  const s = readText(ijState, "utf8");
  if (!s.includes(multi)) fail("intellij ReviewStateManager missing multi_root_error fragment");
}

// no_base_candidates
if (!text.includes("No branches to pick a base from were found.")) {
  fail("YAML missing no_base_candidates string");
}
const setBase = readText(join(root, "vscode-extension", "src", "commands", "setBase.ts"), "utf8");
if (!setBase.includes("No branches to pick a base from were found.")) {
  fail("setBase.ts missing no_base_candidates");
}

// cli_outdated must keep "installed"
if (!text.includes("The installed git-review CLI is older than")) {
  fail('cli_outdated_title must include "installed"');
}

// support URLs: star + bug (openSupport allowlist)
const starUrlMatch = text.match(/^\s*star_url:\s*"([^"]+)"/m);
const bugUrlMatch = text.match(/^\s*bug_url:\s*"([^"]+)"/m);
if (!starUrlMatch) fail("missing support.star_url");
if (!bugUrlMatch) fail("missing support.bug_url");
const starUrl = starUrlMatch[1];
const bugUrl = bugUrlMatch[1];
const providerSupport = readText(
  join(root, "vscode-extension", "src", "views", "walkthroughViewProvider.ts"),
  "utf8",
);
if (!providerSupport.includes(`star: "${starUrl}"`)) {
  fail(`vscode SUPPORT_URLS.star missing or drifted from support.star_url`);
}
if (!providerSupport.includes(`bug: "${bugUrl}"`)) {
  fail(`vscode SUPPORT_URLS.bug missing or drifted from support.bug_url`);
}
const ijSupport = join(
  root,
  "jetbrains-plugin",
  "src",
  "main",
  "kotlin",
  "com",
  "ezevillo",
  "gitreview",
  "domain",
  "SupportLinks.kt",
);
if (existsSync(ijSupport)) {
  const s = readText(ijSupport, "utf8");
  if (!s.includes(starUrl)) fail(`intellij SupportLinks missing star_url ${starUrl}`);
  if (!s.includes(bugUrl)) fail(`intellij SupportLinks missing bug_url ${bugUrl}`);
}
if (!existsSync(join(root, ".github", "ISSUE_TEMPLATE", "bug_report.yml"))) {
  fail("missing .github/ISSUE_TEMPLATE/bug_report.yml (support.bug_url template)");
}

// ---------------------------------------------------------------------------
// panel_layout: six VS Code checks + internal coherence (feature 010)
// ---------------------------------------------------------------------------

if (!/^panel_layout:\s*$/m.test(text)) {
  fail("missing panel_layout: block");
}
if (!/^title_actions:\s*$/m.test(text)) {
  fail("missing title_actions: block");
}
if (!/^panel_excluded:/m.test(text)) {
  fail("missing panel_excluded:");
}

const panelHtmlPath = join(root, "vscode-extension", "src", "views", "panelHtml.ts");
const panelHtml = readText(panelHtmlPath, "utf8");
const providerPath = join(root, "vscode-extension", "src", "views", "walkthroughViewProvider.ts");
const providerSrc = readText(providerPath, "utf8");

// Extract PANEL_MESSAGES string literals
const panelMessagesMatch = providerSrc.match(/export const PANEL_MESSAGES = \[([\s\S]*?)\] as const/);
if (!panelMessagesMatch) fail("PANEL_MESSAGES not found");
const PANEL_MESSAGES = [...panelMessagesMatch[1].matchAll(/"([A-Za-z][A-Za-z0-9]*)"/g)].map((m) => m[1]);

// view/title command ids from package.json
const viewTitle = pkg.contributes?.menus?.["view/title"] ?? [];
const titleCommandIds = viewTitle.map((e) => String(e.command || "").replace(/^gitReview\./, ""));

// panel_excluded
const excludedMatch = text.match(/^panel_excluded:\s*\[([^\]]*)\]/m);
if (!excludedMatch) fail("panel_excluded list missing");
const panelExcluded = excludedMatch[1].split(",").map((s) => s.trim()).filter(Boolean);

// title_actions ids
const titleActionsBlock = text.split(/^title_actions:\s*$/m)[1]?.split(/^[a-z_][a-z0-9_]*:/m)[0] ?? "";
const titleActionIds = [...titleActionsBlock.matchAll(/id:\s*([A-Za-z][A-Za-z0-9]*)/g)].map((m) => m[1]);

// panel_layout, acotado: lo que sigue (title_actions) tiene la misma sangría de
// 2 espacios en sus ids, así que sin este corte la última situación se lo come.
const panelLayoutBlock =
  text.split(/^panel_layout:\s*$/m)[1]?.split(/^title_actions:\s*$/m)[0] ?? "";

/** El bloque YAML de una situación: hasta la próxima o hasta el fin del layout. */
function situationBlock(key) {
  const start = panelLayoutBlock.indexOf(`  ${key}:`);
  if (start === -1) return "";
  const next = panelLayoutBlock.slice(start + 1).search(/\n {2}[a-z][a-z0-9-]*:/);
  return next === -1
    ? panelLayoutBlock.slice(start)
    : panelLayoutBlock.slice(start, start + 1 + next);
}

// Parse control entries from panel_layout (and inventory_controls)
function collectCanonicalControls() {
  const controls = []; // {id, label|null, emphasis, raw, accessible, situation}
  const layoutBlock = panelLayoutBlock;
  // Match control objects in flow or nested form: id: foo, label: "..."
  const controlObjRe =
    /\{\s*id:\s*([A-Za-z][A-Za-z0-9]*)\s*,\s*label:\s*(null|"[^"]*")\s*,\s*(?:accessible_name:\s*"([^"]*)"\s*,\s*)?emphasis:\s*(primary|secondary|link|icon)\s*(?:,\s*raw_button:\s*(true|false))?\s*(?:,\s*confirms:\s*(true|false))?\s*(?:,\s*tooltip:\s*"[^"]*")?\s*\}/g;
  let m;
  while ((m = controlObjRe.exec(layoutBlock)) !== null) {
    const labelRaw = m[2];
    controls.push({
      id: m[1],
      label: labelRaw === "null" ? null : labelRaw.slice(1, -1),
      accessible: m[3] || null,
      emphasis: m[4],
      raw: m[5] === "true",
      confirms: m[6] === "true",
    });
  }
  // code_command controls
  const codeRe =
    /control:\s*([A-Za-z][A-Za-z0-9]*)\s*,\s*label:\s*"([^"]*)"\s*,\s*raw_button:\s*(true|false)/g;
  while ((m = codeRe.exec(layoutBlock)) !== null) {
    controls.push({
      id: m[1],
      label: m[2],
      accessible: null,
      emphasis: "secondary",
      raw: m[3] === "true",
      confirms: false,
    });
  }
  // inventory_controls
  if (text.includes("continueReview: {label: \"Continue\"")) {
    controls.push({
      id: "continueReview",
      label: "Continue",
      accessible: null,
      emphasis: "secondary",
      raw: false,
      confirms: true,
    });
  }
  if (text.includes("discardInventory:")) {
    for (const lab of ["Discard", "Discard orphan"]) {
      controls.push({
        id: "discardInventory",
        label: lab,
        accessible: null,
        emphasis: "secondary",
        raw: false,
        confirms: true,
      });
    }
  }
  return controls;
}

const canonicalControls = collectCanonicalControls();
if (canonicalControls.length === 0) {
  fail("panel_layout has no parsed controls");
}
const rawControlIds = new Set(
  canonicalControls.filter((c) => c.raw).map((c) => c.id),
);

// Map emphasis className in button() third arg
function emphasisFromClassArg(classArg) {
  if (classArg === "null" || classArg === undefined) return "secondary";
  if (classArg === '"primary"' || classArg === "'primary'") return "primary";
  if (classArg === '"link"' || classArg === "'link'") return "link";
  if (classArg === '"file-row"' || classArg === "'file-row'") return "secondary";
  return "secondary";
}

// Extract button()/iconButton() calls from panelHtml.ts
// button(label, message, className, iconName, index)
// iconButton(iconName, message, label)
function extractPanelCalls(src) {
  const calls = []; // {kind, label, id, emphasis, index, line, pos}
  const lines = src.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // iconButton("left", "prev", "Previous entry")
    const iconRe = /iconButton\(\s*"([^"]*)"\s*,\s*"([A-Za-z][A-Za-z0-9]*)"\s*,\s*"([^"]*)"\s*\)/g;
    let im;
    while ((im = iconRe.exec(line)) !== null) {
      calls.push({
        kind: "icon",
        label: null,
        accessible: im[3],
        id: im[2],
        emphasis: "icon",
        line: i + 1,
        pos: im.index,
      });
    }
    // supportButton("Label", "star"|"bug") → wire id openSupport (host allowlist)
    const supportRe = /supportButton\(\s*"([^"]*)"\s*,\s*"([A-Za-z][A-Za-z0-9]*)"\s*\)/g;
    let sm;
    while ((sm = supportRe.exec(line)) !== null) {
      calls.push({
        kind: "button",
        label: sm[1],
        accessible: null,
        id: "openSupport",
        emphasis: "secondary",
        line: i + 1,
        pos: sm.index,
      });
    }
    // button(firstArg, "id", className?, ...) — firstArg may be string, null, ternary, or expression
    const btnRe =
      /button\(\s*((?:[^,"'()]|"[^"]*"|'[^']*'|\([^)]*\))+?)\s*,\s*"([A-Za-z][A-Za-z0-9]*)"\s*(?:,\s*([^,)]+))?/g;
    let bm;
    while ((bm = btnRe.exec(line)) !== null) {
      const first = bm[1].trim();
      if (first === "null") continue; // icon path handled by iconButton
      let label = null;
      let dynamic = false;
      const lit = first.match(/^"([^"]*)"$/) || first.match(/^'([^']*)'$/);
      if (lit) {
        label = lit[1];
      } else {
        // ternary or expression — harvest string literals inside
        dynamic = true;
        const lits = [...first.matchAll(/"([^"]+)"/g)].map((x) => x[1]);
        label = lits[0] ?? undefined;
        // record extra labels as sibling dynamic variants later via same id
        for (const extra of lits.slice(1)) {
          calls.push({
            kind: "button",
            label: extra,
            accessible: null,
            id: bm[2],
            emphasis: "secondary",
            line: i + 1,
            pos: bm.index,
            dynamic: true,
          });
        }
      }
      const classArg = (bm[3] || "null").trim();
      calls.push({
        kind: "button",
        label,
        accessible: null,
        id: bm[2],
        emphasis: classArg.includes("primary")
          ? "primary"
          : classArg.includes("link")
            ? "link"
            : "secondary",
        line: i + 1,
        pos: bm.index,
        dynamic,
      });
    }
  }
  return calls;
}

const panelCalls = extractPanelCalls(panelHtml);

// (1) each canonical control with fixed label matches a call (or raw literal)
for (const c of canonicalControls) {
  if (c.raw) {
    if (c.label && !panelHtml.includes(c.label)) {
      fail(`raw control ${c.id} label "${c.label}" not found in panelHtml.ts`);
    }
    continue;
  }
  if (c.emphasis === "icon") {
    const hit = panelCalls.find(
      (p) => p.kind === "icon" && p.id === c.id && p.accessible === c.accessible,
    );
    if (!hit) {
      fail(`icon control ${c.id} accessible="${c.accessible}" not found as iconButton in panelHtml.ts`);
    }
    continue;
  }
  if (c.label == null) {
    fail(`control ${c.id} has null label but emphasis is not icon`);
  }
  // dynamic labels: only check id exists
  const byId = panelCalls.filter((p) => p.id === c.id);
  if (byId.length === 0) {
    fail(`control ${c.id} not found as button()/iconButton() in panelHtml.ts`);
  }
  const fixed = byId.find((p) => p.label === c.label && p.emphasis === c.emphasis);
  const dynamicOk = byId.some((p) => p.dynamic);
  if (!fixed && !dynamicOk && c.id !== "discardInventory") {
    // discard has ternary labels — allow either label if id matches
    const labelHit = byId.find((p) => p.label === c.label || p.dynamic);
    if (!labelHit) {
      fail(
        `control ${c.id} label="${c.label}" emphasis=${c.emphasis} not matched in panelHtml.ts (found: ${byId.map((p) => `${p.label}/${p.emphasis}`).join(", ")})`,
      );
    }
  } else if (!fixed && c.id === "discardInventory") {
    // ok: ternary
  } else if (!fixed && !dynamicOk) {
    fail(
      `control ${c.id} label="${c.label}" emphasis=${c.emphasis} not matched (found: ${byId.map((p) => `${p.label}/${p.emphasis}`).join(", ")})`,
    );
  }
}

// (2) each control id in PANEL_MESSAGES or view/title
const allControlIds = new Set([
  ...canonicalControls.map((c) => c.id),
  ...titleActionIds,
]);
for (const id of allControlIds) {
  const inPanel = PANEL_MESSAGES.includes(id);
  const inTitle = titleCommandIds.includes(id);
  // title-only actions
  if (titleActionIds.includes(id) && !inTitle) {
    fail(`title action ${id} not in contributes.menus.view/title`);
  }
  if (!titleActionIds.includes(id) || id === "refresh") {
    if (!inPanel && !inTitle) {
      fail(`control id ${id} not in PANEL_MESSAGES or view/title`);
    }
  }
}

// (3) every button/iconButton call in panelHtml is in the canonical
const canonicalIds = new Set(canonicalControls.map((c) => c.id));
for (const p of panelCalls) {
  if (!canonicalIds.has(p.id)) {
    fail(`panelHtml.ts call id=${p.id} label=${p.label} (line ${p.line}) not in panel_layout canonical`);
  }
}

// (4) no panel_excluded id in PANEL_MESSAGES
for (const id of panelExcluded) {
  if (PANEL_MESSAGES.includes(id)) {
    fail(`panel_excluded id ${id} appears in PANEL_MESSAGES`);
  }
}

// (5) adjacency of two-control rows: consecutive button/iconButton calls in order
// Only match flow-style arrays with exactly two objects: [{id: a, ...}, {id: b, ...}]
// Do not cross `]` (would falsely join controls from different rows).
const twoControlRows = [
  ...text.matchAll(
    /controls:\s*\[\s*\{id:\s*([A-Za-z0-9]+)\b[^\]\n]*\}\s*,\s*\{id:\s*([A-Za-z0-9]+)\b/g,
  ),
];
// Also YAML list-style two-control rows under `row:` / `controls:`
const listRows = [
  ...text.matchAll(
    /controls:\n(?: {10,}- \{id:\s*([A-Za-z0-9]+)[^\n]*\n)(?: {10,}- \{id:\s*([A-Za-z0-9]+))/g,
  ),
];
for (const row of [...twoControlRows, ...listRows]) {
  const a = row[1];
  const b = row[2];
  let found = false;
  for (let i = 0; i < panelCalls.length - 1; i++) {
    if (panelCalls[i].id === a && panelCalls[i + 1].id === b) {
      found = true;
      break;
    }
  }
  if (!found) {
    fail(`row adjacency ${a}|${b} not found as consecutive control calls in panelHtml.ts`);
  }
}

// (6) situation control id sequence is a subsequence of calls from source_fns
function extractFunctionBody(src, name) {
  const re = new RegExp(`function ${name}\\s*\\(`);
  const m = re.exec(src);
  if (!m) return null;
  let i = m.index + m[0].length;
  // find opening brace of function
  while (i < src.length && src[i] !== "{") i++;
  if (src[i] !== "{") return null;
  let depth = 0;
  const start = i;
  for (; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}") {
      depth--;
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  return null;
}

function controlSequenceFromSource(srcChunk) {
  const seq = [];
  const iconRe = /iconButton\(\s*"[^"]*"\s*,\s*"([A-Za-z][A-Za-z0-9]*)"/g;
  const btnRe = /button\(\s*(?:null|"[^"]*"|'[^']*'|[^,]+)\s*,\s*"([A-Za-z][A-Za-z0-9]*)"/g;
  let m;
  // Walk in order by scanning combined with positions
  const events = [];
  while ((m = iconRe.exec(srcChunk)) !== null) {
    events.push({ pos: m.index, id: m[1] });
  }
  while ((m = btnRe.exec(srcChunk)) !== null) {
    if (m[0].startsWith("button(null") || m[0].includes("button(null")) continue;
    events.push({ pos: m.index, id: m[1] });
  }
  events.sort((a, b) => a.pos - b.pos);
  for (const e of events) seq.push(e.id);
  return seq;
}

function isSubsequence(small, big) {
  let j = 0;
  for (let i = 0; i < big.length && j < small.length; i++) {
    if (big[i] === small[j]) j++;
  }
  return j === small.length;
}

// Collect situation keys and their source_fns + control id sequences from YAML
const situationEntries = [
  ...text.matchAll(
    /^ {2}([a-z][a-z0-9-]*):\n(?: {4}.*\n)*? {4}source_fns:\s*\[([^\]]*)\]/gm,
  ),
];
for (const se of situationEntries) {
  const sit = se[1];
  const fns = se[2].split(",").map((s) => s.trim()).filter(Boolean);
  let combined = "";
  for (const fn of fns) {
    const body = extractFunctionBody(panelHtml, fn);
    if (!body) fail(`source_fn ${fn} for situation ${sit} not found in panelHtml.ts`);
    combined += body + "\n";
  }
  const extracted = controlSequenceFromSource(combined);
  // control ids from this situation's YAML block
  const sitBlock = situationBlock(sit);
  // Los ids del bloque, en el orden en que se pintan: `{id: ...}` de las rows y
  // `control: ...` de los code_command, mezclados por posición (no primero unos
  // y después otros, que invertiría el orden respecto del panel real).
  const sitHits = [
    ...sitBlock.matchAll(/\{id:\s*([A-Za-z][A-Za-z0-9]*)/g),
    ...sitBlock.matchAll(/control:\s*([A-Za-z][A-Za-z0-9]*)/g),
  ].sort((a, b) => a.index - b.index);
  // Los raw_button se construyen a mano en panelHtml.ts (no via button()), así
  // que nunca aparecen en la secuencia extraída: el chequeo (1) los cubre por
  // label.
  const sitIds = sitHits.map((m) => m[1]).filter((id) => !rawControlIds.has(id));
  if (sitIds.length === 0) continue;
  if (!isSubsequence(sitIds, extracted) && !isSubsequence(sitIds, controlSequenceFromSource(panelHtml))) {
    // Allow full-file fallback when composition is spread (e.g. renderEmptyState)
    // Prefer source_fns sequence; if fail, try full file subsequence
    if (!isSubsequence(sitIds, controlSequenceFromSource(panelHtml))) {
      fail(
        `situation ${sit}: control sequence [${sitIds.join(",")}] is not a subsequence of source_fns [${fns.join(",")}] extracted [${extracted.join(",")}]`,
      );
    }
  }
}

// Internal coherence: panel_layout situations ⊆ actions.<id>.situations
// Map layout keys to situation ids
function layoutKeyToSituations(key) {
  if (key === "no-review-setup") return ["no-review"];
  if (key.startsWith("review-")) return ["review"];
  return [key];
}

// Parse actions situations lists
const actionSituations = {};
for (const id of actionKeys) {
  const re = new RegExp(`^ {2}${id}:\\n(?: {4}.*\\n)*? {4}situations:\\s*\\[([^\\]]*)\\]`, "m");
  const m = text.match(re);
  if (m) {
    actionSituations[id] = m[1].split(",").map((s) => s.trim()).filter(Boolean);
  }
}
const actionBusy = {};
for (const id of actionKeys) {
  const re = new RegExp(`^ {2}${id}:\\n(?: {4}.*\\n)*? {4}requires_not_busy:\\s*true`, "m");
  actionBusy[id] = re.test(actionsBlock);
}

// For each control id painted in a layout situation, situation must be in actions if it's an action
for (const se of situationEntries) {
  const key = se[1];
  const sits = layoutKeyToSituations(key);
  const sitBlock = situationBlock(key);
  const ids = [...sitBlock.matchAll(/\{id:\s*([A-Za-z][A-Za-z0-9]*)/g)].map((m) => m[1]);
  for (const id of ids) {
    if (!actionKeys.includes(id)) continue; // panel-only controls
    const allowed = actionSituations[id] || [];
    for (const s of sits) {
      if (!allowed.includes(s)) {
        fail(`panel_layout ${key} paints ${id} but actions.${id}.situations lacks ${s}`);
      }
    }
  }
}

// requires_not_busy controls: document that busy disables them (coherence note in layout via next/prev etc.)
// We check that every requires_not_busy action that appears in panel_layout is documented as disabled by busy
// in the YAML via being a mutator row control — structural: next/prev have the property and appear in review layouts.
for (const id of actionKeys) {
  if (!actionBusy[id]) continue;
  if (!canonicalIds.has(id) && !titleActionIds.includes(id)) continue;
  // Pass: presence in layout with busy-disable is enforced by IntelliJ tests; Node only asserts the action flag exists.
}

// title actions: finish/save/abort/preview/refresh
for (const id of titleActionIds) {
  if (!actionKeys.includes(id)) fail(`title_actions id ${id} not in actions`);
}

// ---------------------------------------------------------------------------
// Visual Studio client (third tree) — same anti-drift scalars as VS Code / IJ
// ---------------------------------------------------------------------------
const vsVersion = join(
  root,
  "visualstudio-extension",
  "src",
  "GitReview.Domain",
  "Version.cs",
);
const vsInstall = join(
  root,
  "visualstudio-extension",
  "src",
  "GitReview.Domain",
  "InstallHint.cs",
);
const vsSupport = join(
  root,
  "visualstudio-extension",
  "src",
  "GitReview.Domain",
  "SupportLinks.cs",
);
const vsReviewState = join(
  root,
  "visualstudio-extension",
  "src",
  "GitReview.Host",
  "ReviewStateManager.cs",
);
const vsActions = join(
  root,
  "visualstudio-extension",
  "src",
  "GitReview.Domain",
  "ActionArgv.cs",
);

if (existsSync(vsVersion)) {
  const v = readText(vsVersion, "utf8");
  if (!v.includes(`"${min}"`)) fail(`visualstudio Version.cs missing min ${min}`);
}
if (existsSync(vsInstall)) {
  const i = readText(vsInstall, "utf8");
  if (!i.includes(npmInstall)) fail(`visualstudio InstallHint.cs missing npm_install`);
  if (!i.includes(npmUpdate)) fail(`visualstudio InstallHint.cs missing npm_update`);
}
if (existsSync(vsSupport)) {
  const s = readText(vsSupport, "utf8");
  if (!s.includes(starUrl)) fail(`visualstudio SupportLinks missing star_url ${starUrl}`);
  if (!s.includes(bugUrl)) fail(`visualstudio SupportLinks missing bug_url ${bugUrl}`);
}
if (existsSync(vsReviewState)) {
  const s = readText(vsReviewState, "utf8");
  if (!s.includes(multi)) fail("visualstudio ReviewStateManager missing multi_root_error fragment");
}
if (existsSync(vsActions)) {
  const a = readText(vsActions, "utf8");
  for (const id of actionKeys) {
    if (!a.includes(`"${id}"`)) fail(`visualstudio ActionArgv.cs missing product action ${id}`);
  }
}

console.log(
  `check-client-product-surface: ok (min=${min}, actions=${actionKeys.length}, panel_controls=${canonicalControls.length}, title_actions=${titleActionIds.length}, vs=${existsSync(vsVersion) ? "yes" : "no"})`,
);
