#!/usr/bin/env node
/**
 * Anti-drift check: contracts/client-product-surface.yaml vs los tres clientes.
 * Falla si falta el YAML, si el esquema no cierra, si driftea min_cli_version /
 * npm / los strings criticos, o si el conteo de acciones no da contra el
 * package.json de la extension.
 */
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

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

// --yaml <path>: corre el chequeo entero contra otro archivo en vez del
// canonico del repo. Existe para la fixture de T008 -- un YAML con los cuatro
// min_cli_version maximamente distintos -- que prueba que "ningun gate exige
// que sean iguales" sigue probando algo el dia que los cuatro converjan por
// casualidad en `main`.
const yamlArgIndex = process.argv.indexOf("--yaml");
const yamlOverride = yamlArgIndex === -1 ? null : process.argv[yamlArgIndex + 1];
if (yamlArgIndex !== -1 && !yamlOverride) {
  fail("--yaml requires a path argument");
}
const yamlPath = yamlOverride
  ? resolve(process.cwd(), yamlOverride)
  : join(root, "contracts", "client-product-surface.yaml");

if (!existsSync(yamlPath)) {
  fail(`missing ${yamlPath}`);
}

const text = readText(yamlPath, "utf8");

function scalar(key) {
  const m = text.match(new RegExp(`^${key}:\\s*"([^"]*)"`, "m"));
  if (!m) fail(`missing scalar ${key}`);
  return m[1];
}

// Los cuatro clientes que todo mapa "por cliente" del canonico declara.
// Ninguno hereda de otro -- un cliente ausente es un fail, no un default
// silencioso --, el mismo criterio con el que las guias se emiten exista o no
// el archivo y con el que `not_in:` se verifica en las dos direcciones.
const REQUIRED_CLIENTS = ["vscode", "intellij", "visualstudio", "tui"];

/** El bloque de nivel 0 bajo `key:`, hasta la proxima clave de nivel 0. */
function topBlock(key) {
  const block = text.split(new RegExp(`^${key}:\\s*$`, "m"))[1]?.split(/^[a-z_][a-z0-9_]*:\s*$/m)[0];
  if (!block) fail(`missing ${key}: block`);
  return block;
}

/** Que un mapa por-cliente declare los cuatro, ni uno de mas ni de menos. */
function requireFourClients(block, where) {
  for (const c of REQUIRED_CLIENTS) {
    if (!new RegExp(`^ {2,4}${c}:`, "m").test(block)) {
      fail(`${where} is missing client ${c}`);
    }
  }
}

// Cada cliente parte una cadena compartida en dos literales, y cada lenguaje
// lo escribe distinto. Sacar comillas, backticks y el operador de
// concatenacion compara el texto sin obligarlos a cortarlo en el mismo lugar
// -- eso es formato, no copy.
const squash = (s) => s.replace(/["`+]/g, " ").replace(/\s+/g, " ");

// EL PISO DE CADA CLIENTE, Y NADA MAS. min_cli_version es un mapa y minFor es
// la unica forma de leerlo: no queda ningun `min` global en scope, que es lo
// que hace imposible escribir por accidente una comparacion entre dos
// clientes. Que los cuatro difieran no es drift -- es el estado esperado --, y
// la comparacion de cada cliente es un piso estricto: no hay techo, asi que
// una CLI mas nueva que el minimo nunca se reporta desactualizada (FR-028).
function minFor(client) {
  const block = topBlock("min_cli_version");
  requireFourClients(block, "min_cli_version");
  const m = block.match(new RegExp(`^ {2}${client}:\\s*"([^"]*)"`, "m"));
  if (!m) fail(`min_cli_version missing client ${client}`);
  return m[1];
}

/** El sub-bloque `per_client_strings.<name>`, hasta la proxima clave de nivel 2. */
function perClientStringBlock(name) {
  const parent = topBlock("per_client_strings");
  const parts = parent.split(new RegExp(`^ {2}${name}:\\s*$`, "m"));
  if (parts.length < 2) fail(`missing per_client_strings.${name}`);
  const after = parts[1];
  const cut = after.search(/^ {2}[a-z_][a-z0-9_]*:\s*$/m);
  return cut === -1 ? after : after.slice(0, cut);
}

// Lo que perClientString("no_single_root"|"after_install", client) contesta:
// la misma situacion, con el proximo paso distinto por cliente. Se compara
// plegada y normalizada con squash, la misma tecnica que ya usa
// draft_agent_prompt, porque cada cliente parte la cadena en un literal propio
// de su lenguaje.
function perClientString(name, client) {
  const block = perClientStringBlock(name);
  requireFourClients(block, `per_client_strings.${name}`);
  const m = block.match(new RegExp(`^ {4}${client}: >-\\n((?: {6}.*\\n)+)`, "m"));
  if (!m) fail(`per_client_strings.${name} missing client ${client}`);
  return m[1]
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
    .join(" ");
}

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

/**
 * `not_in:` — las acciones que un cliente deliberadamente no ofrece. Se verifica en
 * las dos direcciones: el cliente listado no la declara en ninguna superficie (si
 * reapareciera, el contrato tendria que decirlo primero) y los demas la siguen
 * teniendo, que es lo que sigue haciendo el resto de este archivo con actionKeys.
 */
function actionsNotIn(client) {
  const excluded = new Set();
  let current = null;
  for (const line of actionsBlock.split(/\r?\n/)) {
    const head = line.match(/^ {2}([A-Za-z][A-Za-z0-9]*):\s*$/);
    if (head) {
      current = head[1];
      continue;
    }
    const notIn = line.match(/^ {4}not_in:\s*\[([^\]]*)\]/);
    if (notIn && current) {
      const clients = notIn[1].split(",").map((x) => x.trim());
      if (clients.includes(client)) excluded.add(current);
    }
  }
  return excluded;
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
if (!versionTs.includes(`"${minFor("vscode")}"`)) {
  fail(`vscode version.ts does not contain min_cli_version ${minFor("vscode")}`);
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
  if (!v.includes(`"${minFor("intellij")}"`)) fail(`intellij Version.kt missing min ${minFor("intellij")}`);
}
if (existsSync(ijInstall)) {
  const i = readText(ijInstall, "utf8");
  if (!i.includes(npmInstall)) fail(`intellij InstallHint.kt missing npm_install`);
  if (!i.includes(npmUpdate)) fail(`intellij InstallHint.kt missing npm_update`);
}

// La cuarta punta (T028): sin existsSync, porque el archivo existe desde
// esta misma tarea -- un andamio aca naceria vencido. minFor("tui") queda
// cableado del mismo modo que los otros tres.
//
// Salteado contra --yaml: la fixture de T008 estampa tui a proposito en
// "999.99.9" para probar la divergencia, y version.go sigue el numero REAL
// (min_cli_version.tui en el canonico de disco) -- comparar contra la
// fixture pondria este chequeo en rojo por la razon equivocada. Los otros
// tres clientes no tienen este problema porque la fixture los deja en su
// valor real.
const tuiVersionGo = readText(join(root, "tui", "internal", "domain", "version.go"), "utf8");
if (!yamlOverride && !tuiVersionGo.includes(`"${minFor("tui")}"`)) {
  fail(`tui version.go missing min_cli_version ${minFor("tui")}`);
}
const tuiInstallHintGo = readText(join(root, "tui", "internal", "domain", "installhint.go"), "utf8");
if (!tuiInstallHintGo.includes(npmInstall)) fail(`tui installhint.go missing npm_install`);
if (!tuiInstallHintGo.includes(npmUpdate)) fail(`tui installhint.go missing npm_update`);

// per_client_strings.no_single_root — antes un fragmento de cinco palabras
// tipeado a mano en JS ("multi-root is not supported"); ahora la oracion
// entera, leida del YAML y comparada plegada con squash. Se llamaba
// multi_root_error.
const vsState = readText(join(root, "vscode-extension", "src", "review", "state.ts"), "utf8");
if (!squash(vsState).includes(squash(perClientString("no_single_root", "vscode")))) {
  fail("vscode state.ts missing the no_single_root string");
}
const ijState = join(root, "jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "host", "ReviewStateManager.kt");
if (existsSync(ijState)) {
  const s = readText(ijState, "utf8");
  if (!squash(s).includes(squash(perClientString("no_single_root", "intellij")))) {
    fail("intellij ReviewStateManager missing the no_single_root string");
  }
}
// La cuarta punta (T025): sin existsSync -- el archivo ya existe para
// cuando esta tarea termina, asi que la guarda seria un andamio que nace
// vencido.
//
// Salteado contra --yaml: la fixture de T008 es una foto de antes de esta
// tarea y todavia trae el placeholder de no_single_root.tui / after_install
// .tui (nunca se edita: no es uno de los dos archivos que esta fase puede
// tocar), asi que comparar usercopy.go contra ESE texto fallaria por un
// motivo ajeno a la propiedad que la fixture existe para probar.
const tuiUserCopyPath = join(root, "tui", "internal", "domain", "usercopy.go");
const tuiUserCopy = readText(tuiUserCopyPath, "utf8");
if (!yamlOverride) {
  if (!squash(tuiUserCopy).includes(squash(perClientString("no_single_root", "tui")))) {
    fail("tui usercopy.go missing the no_single_root string");
  }
  if (!squash(tuiUserCopy).includes(squash(perClientString("after_install", "tui")))) {
    fail("tui usercopy.go missing the after_install string");
  }
}

// waiting_text — la frase de la espera previa a la primera situacion resuelta.
// Vive en los tres paneles y en ninguna otra parte: no es un estado vacio, asi
// que no tiene fila en panel_layout ni control que la dibuje, y sin este check
// nada la ata. El drift que evita es el de siempre —tres frases distintas para
// el mismo momento— con el agravante de que el momento es el arranque, que es
// justo cuando el panel no puede decir nada mas.
const waiting = "Reading the review state…";
if (!text.includes(`waiting_text: "${waiting}"`)) {
  fail("YAML missing waiting_text string");
}
const waitingSurfaces = [
  ["vscode", join(root, "vscode-extension", "src", "views", "panelHtml.ts")],
  ["intellij", join(root, "jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "ui", "ReviewPanel.kt")],
  ["visualstudio", join(root, "visualstudio-extension", "src", "GitReview.VS", "ToolWindows", "PanelView.cs")],
  ["tui", tuiUserCopyPath],
];
for (const [label, file] of waitingSurfaces) {
  if (!existsSync(file)) continue;
  if (!readText(file, "utf8").includes(waiting)) {
    fail(`${label} panel missing waiting_text`);
  }
}

// no_base_candidates
if (!text.includes("No branches to pick a base from were found.")) {
  fail("YAML missing no_base_candidates string");
}
const setBase = readText(join(root, "vscode-extension", "src", "commands", "setBase.ts"), "utf8");
if (!setBase.includes("No branches to pick a base from were found.")) {
  fail("setBase.ts missing no_base_candidates");
}
if (!tuiUserCopy.includes("No branches to pick a base from were found.")) {
  fail("tui usercopy.go missing no_base_candidates");
}

// draft_agent_prompt — lo que copyDraftPrompt pone en el portapapeles, byte por
// byte igual en los tres clientes. Vive en una constante por cliente para que
// este check compare contra una constante y no contra codigo. El escalar es un
// bloque plegado (>-): se pliega aca y se compara con los espacios normalizados,
// unica forma de que "byte por byte igual" signifique lo mismo de los dos lados.
const draftPromptBlock = text.match(/^ {2}draft_agent_prompt: >-\n((?: {4}.*\n)+)/m);
if (!draftPromptBlock) fail("YAML missing draft_agent_prompt string");
const draftPrompt = (draftPromptBlock?.[1] ?? "")
  .split(/\r?\n/)
  .map((l) => l.trim())
  .filter(Boolean)
  .join(" ");
if (!draftPrompt.startsWith("Fill in the reading order at {path}.")) {
  fail(`draft_agent_prompt must name the row's path: ${draftPrompt}`);
}
// La cuarta punta (T025): usercopy.go lleva TODA la copy del cliente, asi
// que es tambien donde viven draft_agent_prompt y la eleccion de
// walkthroughInit -- las mismas dos cosas que userCopy.ts/UserCopy.kt/
// UserCopy.cs cargan del lado de los otros tres.
const userCopyFiles = [
  ["vscode", ["vscode-extension", "src", "review", "userCopy.ts"]],
  ["intellij", ["jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "domain", "UserCopy.kt"]],
  ["visualstudio", ["visualstudio-extension", "src", "GitReview.Domain", "UserCopy.cs"]],
  ["tui", ["tui", "internal", "domain", "usercopy.go"]],
];

/** Una cadena que los cuatro UserCopy tienen que traer, entrecomillada. */
function requireUserCopy(what, copy) {
  for (const [label, rel] of userCopyFiles) {
    const p = join(root, ...rel);
    if (!existsSync(p)) {
      fail(`${label} UserCopy module missing at ${rel.join("/")}`);
      continue;
    }
    if (!readText(p, "utf8").includes(`"${copy}"`)) fail(`${label} is missing the ${what}`);
  }
}

for (const [label, rel] of userCopyFiles) {
  const p = join(root, ...rel);
  if (!existsSync(p)) {
    fail(`${label} UserCopy module missing at ${rel.join("/")}`);
    continue;
  }
  const s = readText(p, "utf8");
  // {path} es el placeholder del canonico; cada cliente lo interpola a su
  // manera, asi que se compara lo que lo rodea, que es donde vive la copy.
  const [before, after] = draftPrompt.split("{path}");
  if (!squash(s).includes(squash(before)) || !squash(s).includes(squash(after))) {
    fail(`${label} UserCopy missing draft_agent_prompt text`);
  }
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
if (!tuiUserCopy.includes(starUrl)) fail(`tui usercopy.go missing star_url ${starUrl}`);
if (!tuiUserCopy.includes(bugUrl)) fail(`tui usercopy.go missing bug_url ${bugUrl}`);
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
    /\{\s*id:\s*([A-Za-z][A-Za-z0-9]*)\s*,\s*label:\s*(null|"[^"]*")\s*,\s*(?:accessible_name:\s*"([^"]*)"\s*,\s*)?emphasis:\s*(primary|secondary|link|icon)\s*(?:,\s*icon:\s*[a-z]+)?\s*(?:,\s*raw_button:\s*(true|false))?\s*(?:,\s*confirms:\s*(true|false))?\s*(?:,\s*tooltip:\s*"[^"]*")?\s*\}/g;
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
  // draft_controls — los cuatro controles de una fila del bloque de borradores,
  // leidos del mapa propio igual que inventory_controls: son por fila, asi que
  // no pueden declararse como un {block: row} del layout. NO son acciones: el
  // conteo fijo de 27 de arriba no los cuenta y no se toca.
  const draftBlock = text.split(/^draft_controls:\s*$/m)[1]?.split(/^[a-z_][a-z0-9_]*:/m)[0] ?? "";
  const draftRe =
    /^ {2}([A-Za-z][A-Za-z0-9]*):\s*\{label:\s*(null|"[^"]*")\s*,\s*(?:accessible_name:\s*"([^"]*)"\s*,\s*)?emphasis:\s*(primary|secondary|link|icon)\s*(?:,\s*emphasis_unfilled:\s*(primary|secondary))?(?:\s*,\s*icon:\s*[a-z]+)?\s*,\s*confirms:\s*(true|false)(?:\s*,\s*tooltip:\s*"[^"]*")?(?:\s*,\s*tooltip_disabled:\s*"([^"]*)")?(?:\s*,\s*tooltip_unfilled:\s*"([^"]*)")?\}/gm;
  let dm;
  while ((dm = draftRe.exec(draftBlock)) !== null) {
    // Un control con emphasis_unfilled tiene DOS enfasis validos —el cliente
    // elige con el progreso del borrador—, asi que lo que se compara despues
    // es el conjunto y no el escalar.
    const emphases = dm[5] ? [dm[4], dm[5]] : [dm[4]];
    controls.push({
      id: dm[1],
      label: dm[2] === "null" ? null : dm[2].slice(1, -1),
      accessible: dm[3] || null,
      emphasis: dm[4],
      emphases,
      raw: false,
      confirms: dm[6] === "true",
      tooltipDisabled: dm[7] || null,
      tooltipUnfilled: dm[8] || null,
    });
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

// Los tres archivos donde vive la copy de un control del bloque de borradores:
// no es UserCopy, porque la escribe el builder del layout de cada cliente.
const layoutFiles = [
  ["vscode", ["vscode-extension", "src", "views", "panelHtml.ts"]],
  ["intellij", ["jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "domain", "PanelLayout.kt"]],
  ["visualstudio", ["visualstudio-extension", "src", "GitReview.Domain", "PanelLayout.cs"]],
];

/**
 * Una cadena que los tres clientes escriben a mano y tiene que decir lo mismo.
 * `exact` la busca entrecomillada y sin normalizar: un nombre accesible que es
 * prefijo del tooltip de al lado --"Open the reading order" contra "Open the
 * reading order for editing"-- se da por presente con la comparacion laxa
 * aunque el cliente lo haya perdido.
 */
function requireSharedCopy(what, copy, exact, excluded = []) {
  for (const [label, rel] of layoutFiles) {
    // Una divergencia declarada en el canonico (`not_in:`) no es drift: el
    // cliente listado no tiene el control, asi que tampoco tiene su copy.
    if (excluded.includes(label)) continue;
    const p = join(root, ...rel);
    if (!existsSync(p)) {
      fail(`${label} panel layout missing at ${rel.join("/")}`);
      continue;
    }
    const src = readText(p, "utf8");
    const hit = exact
      ? src.includes(`"${copy}"`)
      : squash(src).includes(squash(copy));
    if (!hit) fail(`${label} is missing the ${what}`);
  }
}

// Los tres archivos donde vive la PROYECCION: kind y state de la CLI entran, y
// salen la etiqueta de la fila y el texto del badge. Es copy compartida igual
// que la del layout, solo que la escribe otro archivo de cada cliente.
const modelFiles = [
  ["vscode", ["vscode-extension", "src", "views", "panelModel.ts"]],
  ["intellij", ["jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "domain", "PanelModel.kt"]],
  ["visualstudio", ["visualstudio-extension", "src", "GitReview.Domain", "PanelModel.cs"]],
];

function requireModelCopy(what, copy) {
  for (const [label, rel] of modelFiles) {
    const p = join(root, ...rel);
    if (!existsSync(p)) {
      fail(`${label} panel model missing at ${rel.join("/")}`);
      continue;
    }
    if (!readText(p, "utf8").includes(`"${copy}"`)) fail(`${label} is missing the ${what}`);
  }
}

for (const c of canonicalControls) {
  // Lo que dice un control apagado. Es copy compartida como draft_agent_prompt,
  // y el motivo de verificarla es el mismo: tres clientes escribiendo a mano el
  // mismo texto derivan sin que nadie mire.
  if (c.tooltipDisabled) {
    requireSharedCopy(`disabled tooltip of ${c.id}`, c.tooltipDisabled, false);
  }
  // El otro motivo por el que el mismo control puede estar apagado. Se verifica
  // aparte y no como variante del anterior porque son dos frases distintas: si
  // un cliente pierde una y deja la otra, el control sigue diciendo algo, y lo
  // que dice es el motivo equivocado.
  if (c.tooltipUnfilled) {
    requireSharedCopy(`unfilled tooltip of ${c.id}`, c.tooltipUnfilled, false);
  }
  // El nombre accesible de un control CON etiqueta: es copy propia, no la
  // etiqueta, y sin verificarla el aria-label se cae de un cliente sin que
  // nadie lo note (uno de icono ya se verifica por su iconButton).
  if (c.accessible && c.label != null) {
    requireSharedCopy(`accessible name of ${c.id}`, c.accessible, true);
  }
}

// TODO TOOLTIP DECLARADO EN EL CANONICO TIENE QUE ESTAR EN LOS TRES PANELES.
//
// Barrido por texto y no por control parseado: los tooltips se declaran en
// cuatro lugares con cuatro formas (inline en panel_layout, draft_controls,
// guide_rows.controls, fixes_rows.controls) y un parser por forma se olvida de
// la quinta. Con solo uno parseado, el tooltip de openAllChanges vivia en el
// contrato sin que nadie lo verificara -- y un tooltip que falta no rompe ningun
// layout, asi que se pierde sin que se note. Entra cualquier clave que empiece
// con `tooltip` y lleve un literal entre comillas.
//
// `not_in:` en la MISMA linea excluye a ese cliente: es como se declara la unica
// divergencia deliberada (openAllChanges no existe en Visual Studio).
const tooltipKeyRe = /\btooltip(?:_[a-z]+)?:\s*"((?:[^"\\]|\\.)+)"/g;
let tooltipsChecked = 0;
for (const line of text.split("\n")) {
  const trimmed = line.trim();
  if (trimmed.startsWith("#") || !/\btooltip/.test(trimmed)) continue;
  const notIn = /not_in:\s*\[([^\]]*)\]/.exec(line);
  const excluded = notIn
    ? notIn[1].split(",").map((s) => s.trim()).filter(Boolean)
    : [];
  let tm;
  tooltipKeyRe.lastIndex = 0;
  while ((tm = tooltipKeyRe.exec(line)) !== null) {
    requireSharedCopy(`tooltip "${tm[1].slice(0, 40)}…"`, tm[1], false, excluded);
    tooltipsChecked += 1;
  }
}
if (tooltipsChecked === 0) {
  fail("no tooltips were parsed from the canonical (the sweep regex broke)");
}


// Map emphasis className in button() third arg. Un ternario entre null y
// "primary" no es un enfasis fijo sino uno condicional: devuelve los DOS
// valores, que es lo mismo que el canonico declara con emphasis_unfilled.
function emphasisFromClassArg(classArg) {
  if (classArg === "null" || classArg === undefined) return "secondary";
  if (classArg === '"primary"' || classArg === "'primary'") return "primary";
  const cond = /^[A-Za-z_$][\w$]*\s*\?\s*(null|"primary")\s*:\s*(null|"primary")$/.exec(classArg);
  if (cond) {
    return [cond[1], cond[2]].map((v) => (v === "null" ? "secondary" : "primary")).join("|");
  }
  if (classArg.includes("link")) return "link";
  if (classArg.includes("primary")) return "primary";
  return "secondary";
}

/**
 * El enfasis de una llamada contra el del canonico. Con emphasis_unfilled hay
 * dos valores validos y el orden en que se escriben no significa nada, asi que
 * se comparan como conjuntos: lo que no puede pasar es que el cliente ofrezca
 * un enfasis que el canonico no declara, ni al reves.
 */
function emphasisMatches(canonical, actual) {
  if (!Array.isArray(canonical.emphases) || canonical.emphases.length < 2) {
    return actual === canonical.emphasis;
  }
  const want = [...canonical.emphases].sort().join("|");
  const got = String(actual).split("|").sort().join("|");
  return want === got;
}

// Extract button()/iconButton() calls from panelHtml.ts
// button(label, message, className, iconName, index)
// iconButton(iconName, message, label, index?)
function extractPanelCalls(src) {
  const calls = []; // {kind, label, id, emphasis, index, line, pos}
  const lines = src.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // iconButton("left", "prev", "Previous entry")
    // El cuarto argumento es el indice de la fila, y solo lo llevan los
    // controles de icono que actuan sobre UNA fila del cuerpo.
    const iconRe =
      /iconButton\(\s*"([^"]*)"\s*,\s*"([A-Za-z][A-Za-z0-9]*)"\s*,\s*"([^"]*)"\s*(?:,\s*[A-Za-z_$][\w$]*\s*)?\)/g;
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
        emphasis: emphasisFromClassArg(classArg),
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
  const fixed = byId.find((p) => p.label === c.label && emphasisMatches(c, p.emphasis));
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
// Los mapas de controles cuyo sujeto es una FILA. No son acciones del producto
// -- sin la fila que los dibuja no tienen sujeto --, asi que no cuentan contra
// las 27 y no viven dentro de panel_layout; pero si tienen que estar cableados
// en cada cliente, que es lo que se verifica abajo.
function rowBlock(name) {
  return text.split(new RegExp(`^${name}:\s*$`, "m"))[1]?.split(/^[a-z_][a-z0-9_]*:\s*$/m)[0] ?? "";
}
function rowControlIds(name) {
  return [...rowBlock(name).matchAll(/^ {4}([A-Za-z][A-Za-z0-9]*):\s*\{/gm)].map((m) => m[1]);
}
const guideIdsForMessages = rowControlIds("guide_rows");
const walkthroughRowIds = rowControlIds("walkthrough_row");
const fixesRowIds = rowControlIds("fixes_rows");
const allControlIds = new Set([
  ...canonicalControls.map((c) => c.id),
  ...guideIdsForMessages,
  ...walkthroughRowIds,
  ...fixesRowIds,
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

// (3) every button/iconButton call in panelHtml is in the canonical.
// Los del bloque de guias entran por su propio mapa, igual que los de
// draft_controls entran por el suyo: su sujeto es la fila, no la situacion, asi
// que no pueden declararse dentro de panel_layout.
const guideRowsBlock = rowBlock("guide_rows");
const guideControlIds = guideIdsForMessages;
const canonicalIds = new Set([
  ...canonicalControls.map((c) => c.id),
  ...guideControlIds,
  ...walkthroughRowIds,
  ...fixesRowIds,
]);
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
  if (!v.includes(`"${minFor("visualstudio")}"`)) fail(`visualstudio Version.cs missing min ${minFor("visualstudio")}`);
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
  if (!squash(s).includes(squash(perClientString("no_single_root", "visualstudio")))) {
    fail("visualstudio ReviewStateManager missing the no_single_root string");
  }
}
// Lo que este cliente ofrece: todas las acciones menos las que el contrato marca
// not_in: [visualstudio]. La lista completa sigue siendo la de VS Code.
const vsNotIn = actionsNotIn("visualstudio");
const vsActionKeys = actionKeys.filter((id) => !vsNotIn.has(id));

if (existsSync(vsActions)) {
  const a = readText(vsActions, "utf8");
  for (const id of vsActionKeys) {
    if (!a.includes(`"${id}"`)) fail(`visualstudio ActionArgv.cs missing product action ${id}`);
  }
  for (const id of vsNotIn) {
    if (a.includes(`"${id}"`)) {
      fail(
        `visualstudio ActionArgv.cs declares ${id}, which the contract marks ` +
          `not_in: [visualstudio] — reponerla es editar el contrato primero`,
      );
    }
  }
}

// The five title_actions are a tool-window toolbar in Visual Studio, and that takes
// three files agreeing: the .vsct declares the buttons, GitReviewPackage maps each
// command id to the ControlId it answers for, and the tool window names the toolbar.
// Two of the ways they drift are silent in a build — a button that lost its <Icon>
// draws as an empty slot, and a command id that no longer matches its IDSymbol is a
// button that does nothing — so they are checked here rather than left to a reviewer.
const vsVsct = join(
  root,
  "visualstudio-extension",
  "src",
  "GitReview.VS",
  "Vsix",
  "GitReviewPackage.vsct",
);
const vsPackage = join(
  root,
  "visualstudio-extension",
  "src",
  "GitReview.VS",
  "Vsix",
  "GitReviewPackage.cs",
);
if (existsSync(vsVsct) && existsSync(vsPackage)) {
  const vsct = readText(vsVsct, "utf8");
  const pkg = readText(vsPackage, "utf8");

  const mapBlock = pkg.split(/TitleBarCommands\s*=\s*\{/)[1]?.split("};")[0] ?? "";
  const mapped = [...mapBlock.matchAll(/\((0x[0-9A-Fa-f]+),\s*ControlId\.([A-Za-z]+)\)/g)]
    .map((m) => ({ id: m[1].toLowerCase(), control: m[2] }));
  if (mapped.length !== titleActionIds.length) {
    fail(
      `visualstudio GitReviewPackage.TitleBarCommands has ${mapped.length} entries, ` +
        `title_actions has ${titleActionIds.length}`,
    );
  }

  const symbols = new Map(
    [...vsct.matchAll(/<IDSymbol name="([A-Za-z0-9_]+)" value="(0x[0-9A-Fa-f]+)"/g)]
      .map((m) => [m[2].toLowerCase(), m[1]]),
  );
  const buttons = new Map(
    [...vsct.matchAll(/<Button [^>]*id="([A-Za-z0-9_]+)"[\s\S]*?<\/Button>/g)]
      .map((m) => [m[1], m[0]]),
  );

  titleActionIds.forEach((wire, i) => {
    const entry = mapped[i];
    if (!entry) return;
    const expected = wire[0].toUpperCase() + wire.slice(1);
    if (entry.control !== expected) {
      fail(
        `visualstudio TitleBarCommands[${i}] is ControlId.${entry.control}, ` +
          `title_actions[${i}] is ${wire}`,
      );
    }
    const symbol = symbols.get(entry.id);
    if (!symbol) {
      fail(`visualstudio .vsct has no IDSymbol for title action ${wire} (${entry.id})`);
      return;
    }
    const button = buttons.get(symbol);
    if (!button) {
      fail(`visualstudio .vsct has no <Button id="${symbol}"> for title action ${wire}`);
      return;
    }
    if (!/<Icon guid="ImageCatalogGuid" id="[A-Za-z0-9_]+"/.test(button)) {
      fail(`visualstudio .vsct button ${symbol} has no image-catalog <Icon>`);
    }
    if (!button.includes("<CommandFlag>IconIsMoniker</CommandFlag>")) {
      fail(`visualstudio .vsct button ${symbol} misses IconIsMoniker (icon would not draw)`);
    }
  });

  // Tools > git review is the Visual Studio counterpart of the VS Code command
  // palette (27 commands in package.json, checked above) and of the JetBrains Tools
  // menu. It is checked the same way and for the same reason: four of the actions are
  // panel_excluded, so the menu is their only surface, and an entry that lost its
  // IDSymbol or its parent group is an action that silently cannot be run — neither
  // breaks the build.
  const menuBlock = pkg.split(/MenuCommands\s*=\s*\{/)[1]?.split("};")[0] ?? "";
  const menuMapped = [...menuBlock.matchAll(/\((0x[0-9A-Fa-f]+),\s*"([A-Za-z]+)"\)/g)]
    .map((m) => ({ id: m[1].toLowerCase(), wire: m[2] }));
  if (menuMapped.length !== vsActionKeys.length) {
    fail(
      `visualstudio GitReviewPackage.MenuCommands has ${menuMapped.length} entries, ` +
        `actions has ${vsActionKeys.length}`,
    );
  }
  for (const { wire } of menuMapped) {
    if (vsNotIn.has(wire)) {
      fail(
        `visualstudio Tools menu offers ${wire}, which the contract marks ` +
          `not_in: [visualstudio]`,
      );
      continue;
    }
    if (!actionKeys.includes(wire)) fail(`visualstudio menu command ${wire} is not a YAML action`);
  }
  for (const id of vsActionKeys) {
    if (!menuMapped.some((m) => m.wire === id)) {
      fail(`visualstudio Tools menu has no command for action ${id}`);
    }
  }
  for (const { id, wire } of menuMapped) {
    const symbol = symbols.get(id);
    if (!symbol) {
      fail(`visualstudio .vsct has no IDSymbol for menu command ${wire} (${id})`);
      continue;
    }
    const button = buttons.get(symbol);
    if (!button) {
      fail(`visualstudio .vsct has no <Button id="${symbol}"> for menu command ${wire}`);
      continue;
    }
    if (!/<Parent guid="guidGitReviewCmdSet" id="ToolsMenuGroup[A-Za-z]+"/.test(button)) {
      fail(`visualstudio .vsct button ${symbol} is not in a Tools > git review group`);
    }
  }
  if (!/<Menu [^>]*id="ToolsMenu" priority="[^"]*" type="Menu"/.test(vsct)) {
    fail("visualstudio .vsct has no Tools > git review submenu (ToolsMenu)");
  }
  if (!/<Menu [^>]*id="ToolsMenu"[\s\S]*?<Parent guid="guidSHLMainMenu" id="IDG_VS_TOOLS_EXT_TOOLS"/.test(vsct)) {
    fail("visualstudio .vsct ToolsMenu is not parented to the Tools menu");
  }

  const toolbarId = pkg.match(/ToolbarId\s*=\s*(0x[0-9A-Fa-f]+)/)?.[1]?.toLowerCase();
  const toolbarSymbol = toolbarId ? symbols.get(toolbarId) : undefined;
  if (!toolbarSymbol) {
    fail(`visualstudio GitReviewPackage.ToolbarId ${toolbarId} has no IDSymbol in the .vsct`);
  } else if (!new RegExp(`<Menu [^>]*id="${toolbarSymbol}" type="ToolWindowToolbar"`).test(vsct)) {
    fail(`visualstudio .vsct ${toolbarSymbol} is not a ToolWindowToolbar menu`);
  }
}

// ---------------------------------------------------------------------------
// listing: storefront copy that must read the same in all three marketplaces.
// The listing *body* differs per marketplace by design (packaged README /
// plugin.xml description / pasted overview.md) — only the tagline and the
// search keywords are shared, so only those are checked.
// ---------------------------------------------------------------------------
function nestedScalar(parent, key) {
  const block = text.split(new RegExp(`^${parent}:\\s*$`, "m"))[1];
  if (!block) fail(`missing ${parent}: block`);
  const m = block.split(/^[a-z_][a-z0-9_]*:/m)[0].match(new RegExp(`^ +${key}:\\s*"([^"]*)"`, "m"));
  if (!m) fail(`missing ${parent}.${key}`);
  return m[1];
}

function nestedList(parent, key) {
  const block = text.split(new RegExp(`^${parent}:\\s*$`, "m"))[1];
  if (!block) fail(`missing ${parent}: block`);
  const m = block.split(/^[a-z_][a-z0-9_]*:/m)[0].match(new RegExp(`^ +${key}:\\s*\\[([^\\]]*)\\]`, "m"));
  if (!m) fail(`missing ${parent}.${key}`);
  return [...m[1].matchAll(/"([^"]*)"/g)].map((x) => x[1]);
}

/**
 * Como nestedList, pero para un array de identificadores sin comillas --
 * `applies_to: [vscode, intellij, visualstudio]`, no `keywords: ["git", ...]`.
 */
function nestedIdentList(parent, key) {
  const block = text.split(new RegExp(`^${parent}:\\s*$`, "m"))[1];
  if (!block) fail(`missing ${parent}: block`);
  const m = block.split(/^[a-z_][a-z0-9_]*:/m)[0].match(new RegExp(`^ +${key}:\\s*\\[([^\\]]*)\\]`, "m"));
  if (!m) fail(`missing ${parent}.${key}`);
  return m[1].split(",").map((s) => s.trim()).filter(Boolean);
}

// Same word, different house style per marketplace: "pull-request" (VS Code
// package.json) and "pull request" (vsixmanifest Tags) are the same keyword.
function normKeyword(k) {
  return k.toLowerCase().replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim();
}

function sameKeywordSet(a, b) {
  const x = [...new Set(a.map(normKeyword))].sort();
  const y = [...new Set(b.map(normKeyword))].sort();
  return x.length === y.length && x.every((v, i) => v === y[i]);
}

// Contents of `header { ... }`, brace-balanced. Needed because "description" is
// an ordinary Gradle task property elsewhere in build.gradle.kts — a file-wide
// grep would flag `tasks.register(...) { description = ... }`.
function braceBlock(src, header) {
  const start = src.indexOf(header);
  if (start === -1) return null;
  let depth = 0;
  for (let i = src.indexOf("{", start); i < src.length; i += 1) {
    if (src[i] === "{") depth += 1;
    else if (src[i] === "}") {
      depth -= 1;
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  return null;
}

const tagline = nestedScalar("listing", "tagline");
const keywords = nestedList("listing", "keywords");

// listing.applies_to: los clientes que tienen ficha de tienda. El verificador
// itera esta lista en vez de tener los tres escritos a mano, asi que agregar
// un cuarto cliente sin darle un chequeo de storefront es un fail inmediato --
// es lo que hace que `applies_to` sin `tui` sea la declaracion explicita que
// FR-029 pide, y no un hueco.
const STOREFRONT_CHECKS = {
  // VS Code: the tagline *is* the description field (short by design).
  vscode() {
    if (pkg.description !== tagline) {
      fail(`vscode package.json description is not the canonical tagline\n  want: ${tagline}\n  got:  ${pkg.description}`);
    }
    if (!sameKeywordSet(pkg.keywords ?? [], keywords)) {
      fail(`vscode package.json keywords drift from listing.keywords: ${(pkg.keywords ?? []).join(", ")}`);
    }
  },
  // JetBrains: plugin.xml owns the listing body, and build.gradle.kts must not
  // set `description` — that would silently overwrite it at package time with
  // a copy no test asserts on.
  intellij() {
    const ijXml = join(root, "jetbrains-plugin", "src", "main", "resources", "META-INF", "plugin.xml");
    if (existsSync(ijXml)) {
      const x = readText(ijXml, "utf8");
      if (!x.includes(tagline)) fail(`intellij plugin.xml <description> missing the tagline: ${tagline}`);
    }
    const ijGradle = join(root, "jetbrains-plugin", "build.gradle.kts");
    if (existsSync(ijGradle)) {
      const g = readText(ijGradle, "utf8");
      const cfg = braceBlock(g, "pluginConfiguration");
      if (!cfg) fail("intellij build.gradle.kts has no pluginConfiguration block");
      if (/^\s*description\s*(=|\.set\()/m.test(cfg)) {
        fail("intellij build.gradle.kts sets pluginConfiguration.description — it overwrites plugin.xml; keep one copy, in plugin.xml");
      }
      // Without this the Marketplace "What's New" tab and the IDE update
      // dialog ship empty, which is how 0.1.0 through 0.1.3 were published.
      if (!/^\s*changeNotes\s*(=|\.set\()/m.test(cfg)) {
        fail("intellij build.gradle.kts does not set pluginConfiguration.changeNotes — the listing would have no release notes");
      }
    }
  },
  // Visual Studio: the tagline opens both the packaged manifest description
  // and the overview pasted into the portal.
  visualstudio() {
    const vsManifest = join(root, "visualstudio-extension", "src", "GitReview.VS", "source.extension.vsixmanifest");
    if (existsSync(vsManifest)) {
      const m = readText(vsManifest, "utf8");
      if (!m.includes(tagline)) fail(`visualstudio vsixmanifest <Description> missing the tagline: ${tagline}`);
      const tags = m.match(/<Tags>([^<]*)<\/Tags>/)?.[1] ?? "";
      if (!sameKeywordSet(tags.split(";").filter((t) => t.trim()), keywords)) {
        fail(`visualstudio vsixmanifest Tags drift from listing.keywords: ${tags}`);
      }
    }
    const vsOverview = join(root, "visualstudio-extension", "marketplace", "overview.md");
    if (existsSync(vsOverview)) {
      const o = readText(vsOverview, "utf8");
      if (!o.includes(tagline)) fail(`visualstudio marketplace/overview.md missing the tagline: ${tagline}`);
    }
  },
};

const listingAppliesTo = nestedIdentList("listing", "applies_to");
if (listingAppliesTo.length === 0) fail("listing.applies_to is empty");
for (const client of listingAppliesTo) {
  const check = STOREFRONT_CHECKS[client];
  if (!check) {
    fail(`listing.applies_to declares ${client}, which has no storefront artifact check (no listing lives under ${client}/)`);
    continue;
  }
  check();
}

// ── Authoring guides ─────────────────────────────────────────────────────────
//
// Grupo propio y no colado en canonicalControls: sus controles cuelgan de
// guide_rows.controls con claves (disabled_when, only_in_row) que el parser de
// draft_controls no conoce, y forzarlos en ese molde haria que un cambio de
// forma pasara en silencio. Se verifica lo de siempre: la copy que los tres
// escriben a mano dice lo mismo, y un id que un cliente perdio es un boton que
// no existe.
const guideBlock = guideRowsBlock;
if (guideBlock.length === 0) {
  fail("guide_rows block missing from the canonical contract");
} else {
  const guideIds = [...guideBlock.matchAll(/^ {4}([A-Za-z][A-Za-z0-9]*):\s*\{/gm)].map((m) => m[1]);
  const wantIds = ["openGuide", "createGuide", "discardGuide"];
  for (const id of wantIds) {
    if (!guideIds.includes(id)) fail(`guide_rows does not declare ${id}`);
  }
  // Los controles del bloque NO son acciones del producto: el conteo fijo de
  // actions: y contributes.commands no se mueve, y la paleta no los ofrece.
  for (const id of wantIds) {
    if (actionKeys.includes(id)) {
      fail(`${id} is a row control, not a product action: it must not appear in actions:`);
    }
    if (cmdIds.includes(id)) {
      fail(`${id} is a row control: it must not appear in contributes.commands`);
    }
  }
  // Cada id, y cada cadena que el usuario ve, en los tres archivos de layout.
  for (const id of wantIds) {
    requireSharedCopy(`guide control ${id}`, id, false);
  }
  // El nombre de cada fila y su badge son PROYECCION, no layout: los deriva el
  // modelo de cada cliente a partir del kind y del state que reporto la CLI, asi
  // que se buscan en PanelModel y no en el archivo del layout.
  const rowsSection = guideBlock.split(/^ {2}rows:\s*$/m)[1]?.split(/^ {2}[a-z_]+:/m)[0] ?? "";
  const rowLabels = [...rowsSection.matchAll(/label:\s*"([^"]+)"/g)].map((m) => m[1]);
  if (rowLabels.length === 0) fail("guide_rows declares no rows");
  for (const label of rowLabels) {
    requireModelCopy(`guide row label "${label}"`, label);
  }
  // La etiqueta de un control si es del layout: la escribe el builder, no el
  // modelo. Hoy es una sola -- los otros dos son iconos y no llevan texto.
  const controlsSection = guideBlock.split(/^ {2}controls:\s*$/m)[1] ?? "";
  for (const label of [...controlsSection.matchAll(/label:\s*"([^"]+)"/g)].map((m) => m[1])) {
    requireSharedCopy(`guide control label "${label}"`, label, true);
  }
  const accessible = [...controlsSection.matchAll(/accessible_name:\s*"([^"]+)"/g)].map((m) => m[1]);
  for (const name of accessible) {
    requireSharedCopy(`accessible name of a guide control`, name, true);
  }
  const statesMatch = guideBlock.match(/^ {2}states:\s*\[([^\]]*)\]/m);
  if (!statesMatch) {
    fail("guide_rows declares no states");
  } else {
    for (const raw of statesMatch[1].split(",")) {
      const state = raw.trim().replace(/^"|"$/g, "");
      if (state.length > 0) requireModelCopy(`guide badge "${state}"`, state);
    }
  }
  // La seccion que los aloja. Se creo cuando las guias entraron y se llevo init
  // y build: si un cliente los deja a los cuatro en el cajon del que salieron
  // -- la seccion que hoy es Compare --, el panel deja de decir lo que dice la
  // CLI.
  if (!/title:\s*"Walkthrough"/.test(panelLayoutBlock)) {
    fail("panel_layout has no Walkthrough tools section for the guide rows");
  }
  requireSharedCopy("Walkthrough tools section", "Walkthrough", true);
}

// ── The footer of the empty state, in order ────────────────────────────
//
// Walkthrough y los ordenes de lectura terminados son de la review que estas
// por hacer; Compare monta dos revisiones cualesquiera. Se llamaba "Other
// actions" y era la primera: un titulo que no nombraba su contenido, encima de
// las dos que si lo nombran. El orden es del canonico y los tres clientes lo
// dibujan igual, asi que se verifica aca y no en cada cliente.
{
  const sit = situationBlock("no-review");
  const order = [...sit.matchAll(/title:\s*"([^"]+)"/g)].map((m) => m[1]);
  const want = ["Walkthrough", "Reading orders you finished with", "Edits you extracted", "Compare", "Settings", "Support"];
  if (order.join("|") !== want.join("|")) {
    fail(`no-review footer sections are [${order.join(", ")}], expected [${want.join(", ")}]`);
  }
  requireSharedCopy("Compare tools section", "Compare", true);
  // Solo lo que el layout DIBUJA: los tres archivos cuentan en un comentario de
  // donde salio la seccion, y esa prosa es justamente lo que hay que conservar.
  for (const [label, rel] of layoutFiles) {
    const drawn = readText(join(root, ...rel), "utf8")
      .split("\n")
      .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l));
    if (drawn.some((l) => l.includes('"Other actions"'))) {
      fail(`${label} still draws the "Other actions" section: it is called Compare and goes last`);
    }
  }
}

// ── The author's own walkthrough row ─────────────────────────────────────────
//
// Mismo grupo propio que las guias, y por el mismo motivo: sus controles cuelgan
// de walkthrough_row.controls, no de panel_layout, porque sin la fila que los
// dibuja no tienen sujeto.
const walkthroughBlock = rowBlock("walkthrough_row");
if (walkthroughBlock.length === 0) {
  fail("walkthrough_row block missing from the canonical contract");
} else {
  const wantIds = ["openWalkthrough", "copyWalkthroughPrompt"];
  for (const id of wantIds) {
    if (!walkthroughRowIds.includes(id)) fail(`walkthrough_row does not declare ${id}`);
    // Control de fila, no accion del producto: el conteo fijo de 27 no se mueve
    // y la paleta no lo ofrece.
    if (actionKeys.includes(id)) {
      fail(`${id} is a row control, not a product action: it must not appear in actions:`);
    }
    if (cmdIds.includes(id)) {
      fail(`${id} is a row control: it must not appear in contributes.commands`);
    }
    requireSharedCopy(`walkthrough control ${id}`, id, false);
  }
  const wControls = walkthroughBlock.split(/^ {2}controls:\s*$/m)[1] ?? "";
  for (const label of [...wControls.matchAll(/label:\s*"([^"]+)"/g)].map((m) => m[1])) {
    requireSharedCopy(`walkthrough control label "${label}"`, label, true);
  }
  for (const name of [...wControls.matchAll(/accessible_name:\s*"([^"]+)"/g)].map((m) => m[1])) {
    requireSharedCopy("accessible name of a walkthrough control", name, true);
  }
  // El badge de cada estado es PROYECCION: lo deriva el modelo de cada cliente
  // desde el state que reporto la CLI, asi que va contra PanelModel.
  const badges = walkthroughBlock.split(/^ {2}badges:\s*$/m)[1]?.split(/^ {2}[a-z_]+:/m)[0] ?? "";
  // Solo las lineas "clave: valor" del mapa. Un match de comillas sobre el bloque
  // entero se come tambien las de los comentarios, que citan copy a proposito.
  const mapValues = (block) =>
    [...block.matchAll(/^ {4}[a-z-]+:\s*"([^"]+)"/gm)].map((m) => m[1]);
  const badgeTexts = mapValues(badges);
  if (badgeTexts.length === 0) fail("walkthrough_row declares no badges");
  for (const badge of badgeTexts) {
    requireModelCopy(`walkthrough badge "${badge}"`, badge);
  }
  // Las DOS etiquetas del boton que crea y actualiza. Es la unica accion del
  // producto cuya etiqueta depende del estado, asi que el layout de cada cliente
  // tiene que traer las dos -- con una sola, un cliente se quedaria diciendo
  // "Init" sobre un archivo que ese verbo ya no crea desde cero.
  const labels = walkthroughBlock.split(/^ {2}action_labels:\s*$/m)[1]?.split(/^ {2}[a-z_]+:/m)[0] ?? "";
  const labelTexts = mapValues(labels);
  // Tres: crear, actualizar y empezar de cero. Un cliente que se quede con dos
  // dice "Update" sobre un walkthrough que la CLI va a reemplazar entero.
  if (labelTexts.length !== 3) fail("walkthrough_row must declare all three action labels");
  for (const label of labelTexts) {
    requireSharedCopy(`walkthrough action label "${label}"`, label, true);
  }
  // La eleccion entre reconciliar y empezar de cero. Es copy que los tres
  // clientes escriben a mano y que ademas es la unica puerta a --force desde un
  // panel, asi que un cliente que la pierda pierde el flag entero.
  const choice = walkthroughBlock.split(/^ {2}init_choice:\s*$/m)[1]?.split(/^ {2}[a-z_]+:/m)[0] ?? "";
  const choiceTexts = mapValues(choice);
  if (choiceTexts.length === 0) fail("walkthrough_row declares no init_choice copy");
  // Contra UserCopy y no contra el layout: es copy de un dialogo, como
  // draft_agent_prompt, y vive en el modulo que los tres clientes comparten.
  for (const text of choiceTexts) {
    requireUserCopy(`walkthrough init choice "${text}"`, text);
  }
}

// ---------------------------------------------------------------------------
// TUI (T025): la copy de guias, walkthrough y tooltips va TODA a
// usercopy.go. No se suma tui a `layoutFiles`: ese barrido reusa el
// `not_in:` escrito en la MISMA linea del layout, y hoy esa anotacion solo
// nombra a visualstudio para el tooltip de openAllChanges (T006 declaro la
// exclusion de la TUI a nivel de ACCION, no a nivel de fila). Los chequeos
// de abajo son el equivalente de ese barrido con la exclusion resuelta
// contra `actionsNotIn("tui")` en vez de contra el texto de la fila.
// ---------------------------------------------------------------------------
const tuiLayoutGo = readText(join(root, "tui", "internal", "domain", "layout.go"), "utf8");

// La copy (labels, tooltips, nombres accesibles) vive en usercopy.go; los
// ids de control DESNUDOS (sin comillas de por medio en el chequeo `exact`)
// viven como claves de mapa en layout.go (GuideRowControls,
// WalkthroughRowControls). Por eso este helper mira los DOS archivos: basta
// con que el id o la copy aparezca en cualquiera de los dos.
function requireTuiCopy(what, copy, exact) {
  const hitIn = (src) => (exact ? src.includes(`"${copy}"`) : squash(src).includes(squash(copy)));
  if (!hitIn(tuiUserCopy) && !hitIn(tuiLayoutGo)) {
    fail(`tui usercopy.go/layout.go is missing the ${what}`);
  }
}

{
  // guide_rows: los tres ids (control-id token, no copy: se compara igual
  // que "guide control ${id}" arriba, sin comillas), la etiqueta y los dos
  // nombres accesibles. Ninguno esta en not_in para la TUI.
  const guideIds = [...guideRowsBlock.matchAll(/^ {4}([A-Za-z][A-Za-z0-9]*):\s*\{/gm)].map((m) => m[1]);
  for (const id of guideIds) requireTuiCopy(`guide control ${id}`, id, false);
  const guideControlsSection = guideRowsBlock.split(/^ {2}controls:\s*$/m)[1] ?? "";
  for (const label of [...guideControlsSection.matchAll(/label:\s*"([^"]+)"/g)].map((m) => m[1])) {
    requireTuiCopy(`guide control label "${label}"`, label, true);
  }
  for (const name of [...guideControlsSection.matchAll(/accessible_name:\s*"([^"]+)"/g)].map((m) => m[1])) {
    requireTuiCopy(`accessible name of a guide control ("${name}")`, name, true);
  }
}
requireTuiCopy("Walkthrough tools section", "Walkthrough", true);
requireTuiCopy("Compare tools section", "Compare", true);
{
  // walkthrough_row: los dos ids de fila, la etiqueta, el nombre accesible
  // y las tres etiquetas de accion (Init/Update/Start over).
  for (const id of ["openWalkthrough", "copyWalkthroughPrompt"]) {
    requireTuiCopy(`walkthrough control ${id}`, id, false);
  }
  const wControlsSection = walkthroughBlock.split(/^ {2}controls:\s*$/m)[1] ?? "";
  for (const label of [...wControlsSection.matchAll(/label:\s*"([^"]+)"/g)].map((m) => m[1])) {
    requireTuiCopy(`walkthrough control label "${label}"`, label, true);
  }
  for (const name of [...wControlsSection.matchAll(/accessible_name:\s*"([^"]+)"/g)].map((m) => m[1])) {
    requireTuiCopy(`accessible name of a walkthrough control ("${name}")`, name, true);
  }
  const actionLabelsSection = walkthroughBlock.split(/^ {2}action_labels:\s*$/m)[1]?.split(/^ {2}[a-z_]+:/m)[0] ?? "";
  for (const m of actionLabelsSection.matchAll(/^ {4}[a-z-]+:\s*"([^"]+)"/gm)) {
    requireTuiCopy(`walkthrough action label "${m[1]}"`, m[1], true);
  }
}

// El barrido de tooltip*: de las tres GUI (arriba), reapuntado a usercopy.go
// y con la exclusion resuelta contra actions: — openAllChanges no existe
// para la TUI en ninguna superficie, asi que su tooltip no tiene por que
// vivir en usercopy.go.
{
  const tuiNotIn = actionsNotIn("tui");
  let tuiTooltipsChecked = 0;
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.startsWith("#") || !/\btooltip/.test(trimmed)) continue;
    const idOnLine = /\{id:\s*([A-Za-z][A-Za-z0-9]*)/.exec(line)?.[1] ?? null;
    if (idOnLine && tuiNotIn.has(idOnLine)) continue;
    const tuiTooltipRe = /\btooltip(?:_[a-z]+)?:\s*"((?:[^"\\]|\\.)+)"/g;
    let tm;
    while ((tm = tuiTooltipRe.exec(line)) !== null) {
      requireTuiCopy(`tooltip "${tm[1].slice(0, 40)}…"`, tm[1], false);
      tuiTooltipsChecked += 1;
    }
  }
  if (tuiTooltipsChecked === 0) fail("tui tooltip sweep matched nothing (the regex broke)");
}

// ---------------------------------------------------------------------------
// EL ALFABETO DE ICONOS: cada par (control, icono) del canonico, contra los tres
// clientes.
//
// El icono era lo unico de un control que ningun lado declaraba, y los dos
// clientes que lo DERIVAN del id se olvidaron del mismo control dos veces
// seguidas: primero los tres pares de las guias, despues el tacho de las ramas
// de ediciones. Los dos olvidos dibujan algo -- el nombre accesible entero en
// JetBrains, la flecha de `next` en Visual Studio --, asi que no hay excepcion
// ni pantalla en blanco que los delate: hay que ir a mirarlos.
//
// Cada cliente responde desde UN mapa (ICON_OF / IconOf / la llamada literal en
// panelHtml), asi que la pregunta se hace una sola vez por par y no hay que
// entender el render para contestarla. La direccion es canonico -> clientes: un
// cliente puede mapear un id que el canonico no declara (COPY_CLI_INSTALL en
// JetBrains), lo que no puede es dejar sin mapear uno que si esta.
// ---------------------------------------------------------------------------
const iconVocabMatch = text.match(/^icon_vocabulary:\s*\[([^\]]*)\]/m);
if (!iconVocabMatch) fail("missing icon_vocabulary");
const iconVocabulary = new Set(
  iconVocabMatch[1].split(",").map((x) => x.trim()).filter(Boolean),
);
if (iconVocabulary.size === 0) fail("icon_vocabulary is empty");

/** Los pares (id, icono) del canonico, de las dos formas en que se declara un control. */
const canonicalIcons = new Map();
function declareIcon(id, icon, where) {
  if (!iconVocabulary.has(icon)) {
    fail(`${where}: icon "${icon}" is not in icon_vocabulary`);
  }
  const seen = canonicalIcons.get(id);
  if (seen && seen !== icon) {
    fail(`${where}: control ${id} declares two icons (${seen} and ${icon})`);
  }
  canonicalIcons.set(id, icon);
}
// a. inline en panel_layout: {id: openChange, ..., icon: diff, ...}
for (const m of text.matchAll(/\{id:\s*([A-Za-z][A-Za-z0-9]*)[^}]*?\bicon:\s*([a-z]+)/g)) {
  declareIcon(m[1], m[2], "panel_layout");
}
// b. en un mapa de fila: openGuide: {..., icon: file, ...}
for (const m of text.matchAll(/^ {2,4}([A-Za-z][A-Za-z0-9]*):\s*\{[^}]*?\bicon:\s*([a-z]+)/gm)) {
  declareIcon(m[1], m[2], "row controls");
}
if (canonicalIcons.size < 8) {
  fail(`expected the canonical to declare at least 8 control icons, found ${canonicalIcons.size}`);
}
// Y al reves: un control DIBUJADO como icono sin `icon:` es el hueco de origen,
// porque su icono vuelve a ser cosa de cada cliente y nadie puede verificarlo.
for (const m of text.matchAll(/\{id:\s*([A-Za-z][A-Za-z0-9]*)[^}]*?emphasis:\s*icon\b[^}]*?\}/g)) {
  if (!canonicalIcons.has(m[1])) fail(`control ${m[1]}: emphasis icon without icon:`);
}
for (const m of text.matchAll(/^ {2,4}([A-Za-z][A-Za-z0-9]*):\s*\{[^}]*?emphasis:\s*icon\b[^}]*?\}/gm)) {
  if (!canonicalIcons.has(m[1])) fail(`control ${m[1]}: emphasis icon without icon:`);
}

/**
 * VS Code pasa el icono en cada llamada, asi que lo que se lee son las llamadas:
 * `iconButton("<icon>", "<id>", ...)` y `button(<label>, "<id>", <class>,
 * "<icon>", ...)`. TODAS las de un id tienen que traer el mismo -- "Diff"
 * aparece tres veces y una sin icono es un boton pelado entre dos que lo tienen.
 */
function vscodeIconsOf(id) {
  const found = [];
  for (const m of panelHtml.matchAll(/\b(iconButton|button)\(([^()]*)\)/g)) {
    const args = m[2].split(",").map((x) => x.trim());
    const isIconButton = m[1] === "iconButton";
    const calledId = isIconButton ? args[1] : args[1];
    if (calledId !== `"${id}"`) continue;
    const icon = isIconButton ? args[0] : args[3];
    found.push(icon && /^"[a-z]+"$/.test(icon) ? icon.slice(1, -1) : null);
  }
  return found;
}

const screaming = (id) => id.replace(/([A-Z])/g, "_$1").toUpperCase();
const pascal = (id) => id[0].toUpperCase() + id.slice(1);

const rendererKt = join(root, "jetbrains-plugin", "src", "main", "kotlin", "com", "ezevillo", "gitreview", "ui", "PanelRenderer.kt");
const panelViewCs = join(root, "visualstudio-extension", "src", "GitReview.VS", "ToolWindows", "PanelView.cs");
const ijIcons = new Map();
if (existsSync(rendererKt)) {
  for (const m of readText(rendererKt, "utf8").matchAll(/ControlId\.([A-Z_]+)\s+to\s+"([a-z]+)"/g)) {
    ijIcons.set(m[1], m[2]);
  }
  if (ijIcons.size === 0) fail("PanelRenderer.kt declares no ICON_OF entries");
}
const vsIcons = new Map();
if (existsSync(panelViewCs)) {
  for (const m of readText(panelViewCs, "utf8").matchAll(/\[ControlId\.([A-Za-z]+)\]\s*=\s*"([a-z]+)"/g)) {
    vsIcons.set(m[1], m[2]);
  }
  if (vsIcons.size === 0) fail("PanelView.cs declares no IconOf entries");
}

const notInVs = actionsNotIn("visualstudio");
const notInIj = actionsNotIn("intellij");
for (const [id, icon] of canonicalIcons) {
  const drawn = vscodeIconsOf(id);
  if (drawn.length === 0) {
    fail(`vscode: control ${id} carries icon "${icon}" in the canonical and is drawn by no button`);
  }
  const wrong = drawn.filter((x) => x !== icon);
  if (wrong.length > 0) {
    fail(`vscode: ${id} should draw "${icon}", ${wrong.length} of ${drawn.length} call(s) draw ${wrong.map((x) => x ?? "no icon").join(", ")}`);
  }
  if (ijIcons.size > 0 && !notInIj.has(id)) {
    const got = ijIcons.get(screaming(id));
    if (got !== icon) {
      fail(`intellij: ICON_OF is missing ${screaming(id)} -> "${icon}"${got ? ` (found "${got}")` : ""}`);
    }
  }
  if (vsIcons.size > 0 && !notInVs.has(id)) {
    const got = vsIcons.get(pascal(id));
    if (got !== icon) {
      fail(`visualstudio: IconOf is missing ${pascal(id)} = "${icon}"${got ? ` (found "${got}")` : ""}`);
    }
  }
}

// ---------------------------------------------------------------------------
// QUE `confirms:` GOBIERNE, no solo que este declarado.
//
// Este campo se venia parseando y descartando: `collectCanonicalControls` lo
// leia y ningun chequeo lo usaba, asi que del lado de VS Code el `confirms:`
// del canonico no gobernaba nada -- la extension tenia dieciseis
// `showWarningMessage` sueltos y ningun gate. Asi el canonico llego a declarar
// `confirms: true` para un control que hacia rato no confirmaba, con las cinco
// suites en verde.
//
// Los tres chequeos de abajo cierran el circulo: la tabla del cliente coincide
// con el canonico, todo id declarado tiene un llamador que pasa por la puerta, y
// no hay ninguna otra puerta.
// ---------------------------------------------------------------------------

// walkthroughInit es la EXCEPCION declarada: no confirma con un si/no sino con
// un picker de dos cursos ("Update" / "Start over"), que confirmMutation no
// puede expresar porque su "no" es un cancel. Sigue siendo `confirms: true`
// porque hay un modal entre el clic y la mutacion, que es lo que la clave dice.
const CONFIRM_BY_PICKER = new Set(["walkthroughInit"]);

// Barrido de TODO el canonico y no de una lista de bloques: `confirms:` se
// declara en cinco lugares distintos --panel_layout, title_actions y los tres
// mapas de controles por fila-- y una lista de bloques es lo que ya dejo afuera
// a discardGuide. Hay TRES formas, y las tres aparecen en el archivo:
//   {id: foo, ..., confirms: true}      entrada inline de una lista
//   foo: {..., confirms: true}          clave de mapa en una linea
//   foo:                                clave de mapa en bloque
//     confirms: true
// La primera es una regex; las otras dos piden recordar la ultima clave abierta,
// que es lo que una regex no puede hacer.
function collectConfirmingIds(yaml) {
  const found = new Set();
  for (const m of yaml.matchAll(/\{\s*id:\s*([A-Za-z][A-Za-z0-9]*)[^}]*confirms:\s*true/g)) {
    found.add(m[1]);
  }
  let key = null;
  let keyIndent = -1;
  for (const line of yaml.split("\n")) {
    // Las entradas inline ya las tomo la regex de arriba, y dejarlas pasar por
    // aca le atribuiria su confirms a la clave del bloque que las contiene.
    if (line.includes("{id:")) continue;
    // Sólo una clave que ABRE un mapa, en bloque o con llaves. Sin esto,
    // `labels: [...]` y la propia línea `confirms: true` cuentan como claves y
    // el id que se atribuye es el de una propiedad.
    const opened = line.match(/^(\s*)([A-Za-z][A-Za-z0-9]*):\s*(?:\{.*)?$/);
    if (opened) {
      key = opened[2];
      keyIndent = opened[1].length;
    }
    if (!/confirms:\s*true/.test(line) || key === null) continue;
    const indent = line.match(/^\s*/)[0].length;
    if (opened || indent > keyIndent) found.add(key);
  }
  return found;
}

const canonicalConfirming = collectConfirmingIds(text);
if (canonicalConfirming.size === 0) {
  fail("canonical: no control declares confirms: true");
}

const confirmTs = readText(join(root, "vscode-extension", "src", "review", "confirm.ts"), "utf8");
const confirmBlock = confirmTs.match(/export const CONFIRMING_IDS = \[([\s\S]*?)\] as const;/);
if (!confirmBlock) {
  fail("vscode: confirm.ts has no CONFIRMING_IDS array");
}
const clientConfirming = new Set(
  [...(confirmBlock?.[1] ?? "").matchAll(/"([A-Za-z][A-Za-z0-9]*)"/g)].map((m) => m[1]),
);
for (const id of canonicalConfirming) {
  if (!clientConfirming.has(id)) {
    fail(`vscode: ${id} is confirms: true in the canonical and missing from CONFIRMING_IDS`);
  }
}
for (const id of clientConfirming) {
  if (!canonicalConfirming.has(id)) {
    fail(`vscode: CONFIRMING_IDS carries ${id}, which the canonical does not mark confirms: true`);
  }
}

// Los .ts de src/, para los dos chequeos de fuente.
function tsSources(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...tsSources(full));
    else if (name.endsWith(".ts")) out.push([full, readText(full, "utf8")]);
  }
  return out;
}
const srcFiles = tsSources(join(root, "vscode-extension", "src"));
if (srcFiles.length === 0) {
  fail("vscode: no sources found under src/");
}
// Los ids REALMENTE pasados por la puerta, extraidos del primer argumento y no
// buscados sueltos en el archivo: "saveReview" aparece en saveReview.ts como
// nombre de funcion, de comando y de import, asi que un `includes` da verde con
// el call site cambiado -- probado, daba verde.
//
// Dos entradas y no una: runHousekeeping recibe el id y delega en la puerta,
// porque un solo dialogo sirve a varios controles. Si aparece una tercera
// delegacion, el gate la reclama sola: su id no va a estar en esta lista.
const passedToGate = new Set();
for (const [, body] of srcFiles) {
  for (const m of body.matchAll(
    /(?:confirmMutation|runHousekeeping)\(\s*"([A-Za-z][A-Za-z0-9]*)"/g,
  )) {
    passedToGate.add(m[1]);
  }
}
for (const id of canonicalConfirming) {
  if (CONFIRM_BY_PICKER.has(id)) continue;
  if (!passedToGate.has(id)) {
    fail(`vscode: ${id} is confirms: true but is never passed to confirmMutation`);
  }
}
for (const id of passedToGate) {
  if (!canonicalConfirming.has(id)) {
    fail(`vscode: confirmMutation is called with ${id}, which the canonical does not mark confirms: true`);
  }
}

for (const [file, body] of srcFiles) {
  if (file.endsWith("confirm.ts")) continue;
  // La excepcion del picker se anota en el codigo, junto al modal.
  if (body.includes("EXCEPCION DECLARADA a la puerta unica")) continue;
  if (body.includes("modal: true")) {
    fail(`vscode: ${file} opens a modal itself; it must go through confirmMutation`);
  }
}

// ---------------------------------------------------------------------------
// TUI, gate 1 de `confirms:` (T026): la tabla ConfirmingIDs de confirms.go
// contra el canonico, en las dos direcciones. Los gates 2 (el call site de
// ConfirmMutation lee el primer argumento) y 3 (ningun otro modal) llegan en
// T067/T068, cuando existen los call sites y el overlay — hoy no hay nada
// bajo tui/internal/ui/ que barrer.
// ---------------------------------------------------------------------------
const tuiConfirmsGo = readText(join(root, "tui", "internal", "domain", "confirms.go"), "utf8");
const tuiConfirmingBlock = tuiConfirmsGo.match(/ConfirmingIDs = map\[string\]bool\{([\s\S]*?)\n\}/);
if (!tuiConfirmingBlock) {
  fail("tui confirms.go has no ConfirmingIDs map");
}
const tuiConfirming = new Set(
  [...(tuiConfirmingBlock?.[1] ?? "").matchAll(/"([A-Za-z][A-Za-z0-9]*)"/g)].map((m) => m[1]),
);
for (const id of canonicalConfirming) {
  if (!tuiConfirming.has(id)) {
    fail(`tui: ${id} is confirms: true in the canonical and missing from confirms.go's ConfirmingIDs`);
  }
}
for (const id of tuiConfirming) {
  if (!canonicalConfirming.has(id)) {
    fail(`tui: confirms.go's ConfirmingIDs carries ${id}, which the canonical does not mark confirms: true`);
  }
}

// ---------------------------------------------------------------------------
// TUI, `actions:` en las dos direcciones (T030), el mismo par de bucles que
// ya tiene Visual Studio (arriba): las 26 que ofrece estan en actions.go, y
// openAllChanges -- not_in: [tui] -- no esta en ninguna parte del arbol.
// ---------------------------------------------------------------------------
const tuiNotInActions = actionsNotIn("tui");
const tuiActionKeys = actionKeys.filter((id) => !tuiNotInActions.has(id));
const tuiActionsGo = readText(join(root, "tui", "internal", "domain", "actions.go"), "utf8");
for (const id of tuiActionKeys) {
  if (!tuiActionsGo.includes(`"${id}"`)) fail(`tui actions.go missing product action ${id}`);
}
for (const id of tuiNotInActions) {
  if (tuiActionsGo.includes(`"${id}"`)) {
    fail(
      `tui actions.go declares ${id}, which the contract marks not_in: [tui] — ` +
        `reponerla es editar el contrato primero`,
    );
  }
}
// La clasificacion 22 nativas / 4 delegadas / 1 not_in cubre las 27 sin
// huecos ni sobrantes (SC-006): 26 ofrecidas + 1 excluida == 27.
if (tuiActionKeys.length + tuiNotInActions.size !== actionKeys.length) {
  fail(
    `tui: ${tuiActionKeys.length} offered + ${tuiNotInActions.size} not_in should cover all ${actionKeys.length} canonical actions`,
  );
}

// ---------------------------------------------------------------------------
// EL MAPA DE TECLAS DE LA TUI (FR-041). `only_in: [tui]`: los otros tres
// clientes reciben sus atajos del IDE y no declaran keymap propio. La barra de
// teclas del cliente se dibuja de este mismo mapa, asi que una tecla que existe
// y no se muestra es imposible por construccion -- los gates de abajo son
// sobre el YAML mismo y corren en verde antes de que exista una linea de Go.
// ---------------------------------------------------------------------------

const keymapBlock = topBlock("keymap");
const keymapOnlyIn =
  keymapBlock
    .match(/^ {2}only_in:\s*\[([^\]]*)\]/m)?.[1]
    ?.split(",")
    .map((s) => s.trim())
    .filter(Boolean) ?? [];
if (keymapOnlyIn.length !== 1 || keymapOnlyIn[0] !== "tui") {
  fail(`keymap.only_in must be exactly [tui], found [${keymapOnlyIn.join(", ")}]`);
}

/** El sub-bloque `keymap.<name>` (una lista `- {...}`), hasta la proxima clave de nivel 2. */
function keymapSectionBlock(name) {
  const re = new RegExp(`^ {2}${name}:\\s*$`, "m");
  const idx = keymapBlock.search(re);
  if (idx === -1) return "";
  const nlIdx = keymapBlock.indexOf("\n", idx);
  const after = nlIdx === -1 ? "" : keymapBlock.slice(nlIdx + 1);
  const cut = after.search(/^ {2}[a-z_][a-z0-9_]*:/m);
  return cut === -1 ? after : after.slice(0, cut);
}

/** Los `- {...}` de una seccion del keymap, ya parseados. */
function parseKeymapEntries(block) {
  return [...block.matchAll(/-\s*\{([^}]*)\}/g)].map((m) => {
    const body = m[1];
    const keysRaw = body.match(/keys:\s*\[([^\]]*)\]/)?.[1] ?? "";
    const keys = keysRaw
      .split(",")
      .map((k) => k.trim().replace(/^"|"$/g, ""))
      .filter(Boolean);
    return {
      keys,
      does: body.match(/does:\s*([A-Za-z_][A-Za-z0-9_]*)/)?.[1],
      action: body.match(/action:\s*([A-Za-z_][A-Za-z0-9_]*)/)?.[1],
      opens: body.match(/opens:\s*([A-Za-z_][A-Za-z0-9_]*)/)?.[1],
      toggles: body.match(/toggles:\s*([A-Za-z_][A-Za-z0-9_]*)/)?.[1],
    };
  });
}

const KEYMAP_SECTIONS = ["movement", "cursor", "actions", "overlays", "toggles"];
const keymapEntries = Object.fromEntries(
  KEYMAP_SECTIONS.map((name) => [name, parseKeymapEntries(keymapSectionBlock(name))]),
);
for (const name of KEYMAP_SECTIONS) {
  if (keymapEntries[name].length === 0) fail(`keymap.${name} is empty or missing`);
}

// (a) todo id de keymap.actions existe en actions:
for (const e of keymapEntries.actions) {
  if (e.action && !actionKeys.includes(e.action)) {
    fail(`keymap.actions references ${e.action}, which is not a declared action`);
  }
}

// (b) ninguna tecla se declara dos veces en el mismo contexto
for (const name of KEYMAP_SECTIONS) {
  const seen = new Set();
  for (const e of keymapEntries[name]) {
    for (const k of e.keys) {
      if (seen.has(k)) fail(`keymap.${name} declares key "${k}" twice`);
      seen.add(k);
    }
  }
}

// (c) n/p reservadas para el cursor de la review, y para nada mas
for (const name of KEYMAP_SECTIONS) {
  if (name === "cursor") continue;
  for (const e of keymapEntries[name]) {
    for (const k of e.keys) {
      if (k === "n" || k === "p") {
        fail(`keymap.${name} uses "${k}", reserved for cursor: (next/prev)`);
      }
    }
  }
}

// (e) todo panel_excluded es alcanzable desde el overlay action_list y no
// tiene una tecla propia bajo keymap.actions -- goToEntry, por ejemplo, se
// abre con un overlay dedicado (entry_picker), nunca con una tecla que la
// invoque directamente bajo actions:.
if (!keymapEntries.overlays.some((e) => e.opens === "action_list")) {
  fail("keymap.overlays has no entry that opens action_list");
}
for (const id of panelExcluded) {
  if (keymapEntries.actions.some((e) => e.action === id)) {
    fail(`keymap.actions binds ${id} directly; panel_excluded actions must go through an overlay`);
  }
}

// (d) el mapa del cliente declara exactamente estos pares. Andamio borrado
// en T029: el archivo ya existe, asi que el chequeo corre siempre.
const tuiKeymapGo = readText(join(root, "tui", "internal", "domain", "keymap.go"), "utf8");
for (const name of KEYMAP_SECTIONS) {
  for (const e of keymapEntries[name]) {
    for (const k of e.keys) {
      if (!tuiKeymapGo.includes(`"${k}"`)) {
        fail(`tui keymap.go missing key "${k}" declared in keymap.${name}`);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// QUE `reveals:` GOBIERNE, con la leccion que dejo `confirms:`: una tabla que
// nadie consulta no es un contrato, es un comentario. Los mismos tres chequeos.
// ---------------------------------------------------------------------------

/** Los ids de reveals.<client>, como lista (posiblemente vacia). */
function revealsForClient(client) {
  const block = topBlock("reveals");
  const m = block.match(new RegExp(`^ {2}${client}:\\s*\\[([^\\]]*)\\]`, "m"));
  if (!m) fail(`reveals missing client ${client}`);
  return m[1].split(",").map((s) => s.trim()).filter(Boolean);
}

requireFourClients(topBlock("reveals"), "reveals");

// tui: [] es la respuesta, no un hueco -- un pane que abriste vos ya esta a la
// vista, y robarle el foco a alguien en un multiplexor es agresion. Que la
// clave falte, o que deje de estar vacia, es un fail igual que un cliente
// ausente de min_cli_version (FR-025).
const revealsTui = revealsForClient("tui");
if (revealsTui.length !== 0) {
  fail(`reveals.tui must be empty (a terminal pane never steals focus), found: ${revealsTui.join(", ")}`);
}

const canonicalRevealing = new Set(revealsForClient("vscode"));
if (canonicalRevealing.size === 0) {
  fail("canonical: reveals.vscode is empty or missing");
}

const revealTs = readText(join(root, "vscode-extension", "src", "views", "reveal.ts"), "utf8");
const revealBlock = revealTs.match(/export const REVEALING_IDS = \[([\s\S]*?)\] as const;/);
if (!revealBlock) {
  fail("vscode: reveal.ts has no REVEALING_IDS array");
}
const clientRevealing = new Set(
  [...(revealBlock?.[1] ?? "").matchAll(/"([A-Za-z][A-Za-z0-9]*)"/g)].map((m) => m[1]),
);
for (const id of canonicalRevealing) {
  if (!clientRevealing.has(id)) {
    fail(`vscode: ${id} is in reveals: and missing from REVEALING_IDS`);
  }
}
for (const id of clientRevealing) {
  if (!canonicalRevealing.has(id)) {
    fail(`vscode: REVEALING_IDS carries ${id}, which the canonical does not list under reveals:`);
  }
}

const revealed = new Set();
for (const [, body] of srcFiles) {
  for (const m of body.matchAll(/revealPanel\(\s*"([A-Za-z][A-Za-z0-9]*)"/g)) {
    revealed.add(m[1]);
  }
}
for (const id of canonicalRevealing) {
  if (!revealed.has(id)) {
    fail(`vscode: ${id} is in reveals: but is never passed to revealPanel`);
  }
}
for (const id of revealed) {
  if (!canonicalRevealing.has(id)) {
    fail(`vscode: revealPanel is called with ${id}, which the canonical does not list under reveals:`);
  }
}

// Ninguna otra forma de traer el panel al frente: el vehiculo es
// WalkthroughViewProvider.reveal(), y el unico que lo referencia es el host que
// arma el closure. Cualquier otro llamador se saltearia la tabla.
for (const [file, body] of srcFiles) {
  if (file.endsWith("walkthroughViewProvider.ts") || file.endsWith("extension.ts")) continue;
  if (/\.reveal\(\)/.test(body)) {
    fail(`vscode: ${file} reveals the panel itself; it must go through revealPanel`);
  }
}

// La fixture de T008: un YAML con los cuatro min_cli_version maximamente
// distintos. La primera capa del gate "ningun gate exige que sean iguales" es
// gratis -- los cuatro ya difieren en `main` --, pero deja de probar algo el
// dia que converjan por casualidad; por eso esta misma corrida, ademas de
// chequear el canonico real, chequea que la fixture pase con exit 0. Se salta
// cuando --yaml ya apunta a otro archivo, para no recursar.
if (!yamlOverride) {
  const fixturePath = join(root, "specs", "015-cliente-tui", "contracts", "fixtures", "divergent-min.yaml");
  const selfCheck = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "--yaml", fixturePath], {
    encoding: "utf8",
  });
  if (selfCheck.status !== 0) {
    fail(
      `divergent-min.yaml fixture failed the check it exists to prove passes (exit ${selfCheck.status}):\n` +
        `${selfCheck.stdout}${selfCheck.stderr}`,
    );
  }
}

// ---------------------------------------------------------------------------
// EL CHEQUEO DE CIERRE DEL ANDAMIO (T037). Las entradas de la TUI entraron
// con `existsSync(archivo) && …`, el mismo andamio que ya usaron IntelliJ y
// Visual Studio para poder declarar un cliente antes de que su arbol
// exista — y con el mismo problema: un archivo ausente pasa en silencio,
// que es exactamente como un cuarto cliente podria entrar al canonico y no
// verificarse nunca.
//
// Esta regla lo cierra: SI `tui/go.mod` existe, TODAS las rutas de dominio
// que el canonico y sus contratos declaran para la TUI tienen que existir
// de verdad. Borrar un archivo del dominio pone CI en rojo en vez de volver
// mudo el chequeo que lo cubria.
// ---------------------------------------------------------------------------
const tuiGoMod = join(root, "tui", "go.mod");
if (existsSync(tuiGoMod)) {
  const tuiDomainFiles = [
    "pathref.go", "porcelain.go", "situation.go", "panelmodel.go", "layout.go",
    "usercopy.go", "confirms.go", "icons.go", "keymap.go", "actions.go",
    "intent.go", "watchrules.go", "version.go", "installhint.go",
    "statetoken.go", "invocationclass.go",
  ];
  for (const name of tuiDomainFiles) {
    const p = join(root, "tui", "internal", "domain", name);
    if (!existsSync(p)) {
      fail(`tui/go.mod exists but tui/internal/domain/${name} is missing (T037 closing check)`);
    }
  }
}

console.log(
  `check-client-product-surface: ok (min.vscode=${minFor("vscode")}, actions=${actionKeys.length}, panel_controls=${canonicalControls.length}, icons=${canonicalIcons.size}, title_actions=${titleActionIds.length}, confirms=${canonicalConfirming.size}, vs=${existsSync(vsVersion) ? "yes" : "no"}, tui=${existsSync(tuiGoMod) ? "yes" : "no"})`,
);
