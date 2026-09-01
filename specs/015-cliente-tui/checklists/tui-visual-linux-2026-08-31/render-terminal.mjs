import {execFileSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const framesDir = join(here, 'frames');
const htmlDir = join(here, 'html');
const imagesDir = join(here, 'images');
mkdirSync(htmlDir, {recursive: true});
mkdirSync(imagesDir, {recursive: true});

const chromeCandidates = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
];
const chrome = chromeCandidates.find(existsSync);
if (!chrome) throw new Error('Chrome/Edge not found');

function escapeHtml(value) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

const colors = {
  30: '#1b1f27', 31: '#ff6b6b', 32: '#58d68d', 33: '#f4d35e',
  34: '#64a8ff', 35: '#c792ea', 36: '#55d6d2', 37: '#d9e1ee',
  90: '#697386', 91: '#ff8787', 92: '#69db9a', 93: '#ffe066',
  94: '#82b1ff', 95: '#d8a0f0', 96: '#7de3df', 97: '#ffffff',
};

function ansiToHtml(input) {
  let state = {bold: false, dim: false, fg: null};
  let cursor = 0;
  let out = '';
  const sgr = /\x1b\[([0-9;]*)m/g;
  for (let match; (match = sgr.exec(input)); ) {
    out += styled(escapeHtml(input.slice(cursor, match.index)), state);
    cursor = sgr.lastIndex;
    const codes = (match[1] || '0').split(';').map(Number);
    for (const code of codes) {
      if (code === 0) state = {bold: false, dim: false, fg: null};
      else if (code === 1) state.bold = true;
      else if (code === 2) state.dim = true;
      else if (code === 22) { state.bold = false; state.dim = false; }
      else if (code === 39) state.fg = null;
      else if (colors[code]) state.fg = colors[code];
    }
  }
  out += styled(escapeHtml(input.slice(cursor)), state);
  return out;
}

function styled(text, state) {
  if (!text) return '';
  const css = [];
  if (state.bold) css.push('font-weight:700');
  if (state.dim) css.push('opacity:.58');
  if (state.fg) css.push(`color:${state.fg}`);
  return css.length ? `<span style="${css.join(';')}">${text}</span>` : text;
}

function dimensions(name) {
  const match = name.match(/-(80x24|120x40)$/);
  if (!match) throw new Error(`missing terminal dimensions in ${name}`);
  const [cols, rows] = match[1].split('x').map(Number);
  return {cols, rows};
}

function titleFor(name) {
  return name.replace(/-(80x24|120x40)$/, '').replaceAll('-', ' ');
}

function page(name, ansi, cols, rows) {
  const title = titleFor(name);
  return `<!doctype html>
<html><head><meta charset="utf-8"><style>
*{box-sizing:border-box}html,body{margin:0;background:#0b0e14;color:#d9e1ee}
body{font-family:Inter,Segoe UI,sans-serif;width:max-content;min-width:100vw;min-height:100vh;padding:16px}
.window{overflow:hidden;border:1px solid #2a3443;border-radius:12px;background:#10151d;box-shadow:0 16px 48px #0008}
.bar{height:36px;display:flex;align-items:center;gap:8px;padding:0 14px;background:#1a202b;border-bottom:1px solid #2a3443;font:600 12px/1 Inter,Segoe UI,sans-serif;color:#aab6c8}
.dot{width:10px;height:10px;border-radius:50%}.red{background:#ff5f57}.yellow{background:#febc2e}.green{background:#28c840}
.label{margin-left:6px}.meta{margin-left:auto;color:#718096;font-weight:500}
pre{margin:0;padding:18px 20px;width:${cols}ch;height:${rows * 20 + 36}px;overflow:hidden;background:#0e131b;color:#d9e1ee;font:14px/20px "Cascadia Mono",Consolas,"DejaVu Sans Mono",monospace;white-space:pre;tab-size:4}
</style></head><body><div class="window"><div class="bar"><i class="dot red"></i><i class="dot yellow"></i><i class="dot green"></i><span class="label">${escapeHtml(title)}</span><span class="meta">Debian 12 · tmux ${cols}×${rows}</span></div><pre>${ansiToHtml(ansi)}</pre></div></body></html>`;
}

function screenshot(htmlPath, pngPath, width, height, scale = 2) {
  const profile = mkdtempSync(join(tmpdir(), 'tui-visual-'));
  try {
    execFileSync(chrome, [
      '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
      '--no-default-browser-check', `--user-data-dir=${profile}`,
      `--force-device-scale-factor=${scale}`, `--window-size=${width},${height}`,
      `--screenshot=${resolve(pngPath)}`, pathToFileURL(resolve(htmlPath)).href,
    ], {stdio: 'ignore'});
  } finally {
    rmSync(profile, {recursive: true, force: true});
  }
}

const entries = readdirSync(framesDir).filter((name) => name.endsWith('.ansi')).sort();
const rendered = [];
for (const entry of entries) {
  const name = basename(entry, '.ansi');
  const {cols, rows} = dimensions(name);
  const ansi = readFileSync(join(framesDir, entry), 'utf8');
  const htmlPath = join(htmlDir, `${name}.html`);
  const pngPath = join(imagesDir, `${name}.png`);
  writeFileSync(htmlPath, page(name, ansi, cols, rows));
  const width = Math.ceil(cols * 8.45 + 74);
  const height = rows * 20 + 70;
  screenshot(htmlPath, pngPath, width, height);
  rendered.push({name, pngPath, cols, rows});
}

const groups = [
  ['atlas-estados-80x24', rendered.filter((x) => x.name.endsWith('80x24') && !x.name.startsWith('overlay-') && !x.name.startsWith('focus-') && !x.name.includes('mouse-off'))],
  ['atlas-overlays-80x24', rendered.filter((x) => x.name.startsWith('overlay-') || x.name.includes('mouse-off'))],
  ['atlas-foco-80x24', rendered.filter((x) => x.name.startsWith('focus-'))],
  ['atlas-responsive-120x40', rendered.filter((x) => x.name.endsWith('120x40'))],
];

for (const [atlasName, items] of groups) {
  const cardWidth = 760;
  const cardHeight = atlasName.includes('120x40') ? 590 : 455;
  const rows = Math.ceil(items.length / 2);
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
  *{box-sizing:border-box}body{margin:0;padding:28px;background:#070a0f;color:#edf2f7;font-family:Inter,Segoe UI,sans-serif}
  h1{margin:0 0 8px;font-size:28px}p{margin:0 0 24px;color:#91a0b6}.grid{display:grid;grid-template-columns:repeat(2,${cardWidth}px);gap:22px}
  figure{margin:0;background:#10151d;border:1px solid #263142;border-radius:14px;padding:12px;overflow:hidden}figcaption{font:600 13px/1.3 Inter,Segoe UI,sans-serif;margin:0 0 10px;color:#b8c4d6}
  img{display:block;width:100%;height:${cardHeight - 50}px;object-fit:contain;object-position:top left;background:#0b0e14;border-radius:8px}
  </style></head><body><h1>${escapeHtml(atlasName.replaceAll('-', ' '))}</h1><p>Frames ANSI capturados de git-review-ui real dentro de tmux sobre Debian 12.</p><div class="grid">${items.map((item) => `<figure><figcaption>${escapeHtml(titleFor(item.name))}</figcaption><img src="${pathToFileURL(item.pngPath).href}"></figure>`).join('')}</div></body></html>`;
  const htmlPath = join(htmlDir, `${atlasName}.html`);
  writeFileSync(htmlPath, html);
  screenshot(htmlPath, join(imagesDir, `${atlasName}.png`), cardWidth * 2 + 78, rows * (cardHeight + 22) + 105, 1);
}

console.log(`rendered ${rendered.length} terminal PNGs and ${groups.length} atlases`);
