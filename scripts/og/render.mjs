// Renders scripts/og/card.html to docs/og.png — the landing's link preview card.
//
//   node scripts/og/render.mjs
//
// Shot at 2x, so the file is 2400x1260 rather than the nominal 1200x630. Bigger
// is what the scrapers ask for: 1200x630 is a *minimum* for both Open Graph and
// Twitter, and everything downsamples on its own. Taking the shot at scale and
// shipping it is also the only way to stay crisp in one step — resampling in
// JavaScript would mean a PNG codec, and a headless browser is already here.
//
// Chrome is found by trying the known install paths in order: puppeteer would
// solve that too, at the price of a second Chromium in node_modules for one
// screenshot. Keep this dependency-free; `npm install` at the repo root must
// stay unnecessary for anyone who only wants to regenerate the card.
//
// If you change the size, change og:image:width / og:image:height in
// docs/index.html to match: Slack and Discord draw the small card until they
// have fetched and measured the image themselves.

import {execFileSync} from 'node:child_process';
import {existsSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const CARD = join(HERE, 'card.html');
const OUT = resolve(HERE, '../../docs/og.png');
const W = 1200, H = 630, SCALE = 2;

const CANDIDATES = [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
];

const chrome = CANDIDATES.find(existsSync);
if (!chrome) {
    console.error('error: no Chrome or Edge found. Looked at:\n  ' + CANDIDATES.join('\n  '));
    process.exit(1);
}

// A throwaway profile. A Chrome the user already has open would otherwise hand
// the command off to the running instance, which exits 0 and takes no shot.
const profile = mkdtempSync(join(tmpdir(), 'og-render-'));

try {
    execFileSync(chrome, [
        '--headless=new',
        '--disable-gpu',
        '--hide-scrollbars',
        '--no-first-run',
        '--no-default-browser-check',
        `--user-data-dir=${profile}`,
        `--force-device-scale-factor=${SCALE}`,
        `--window-size=${W},${H}`,
        // Long enough for the Google Fonts stylesheet and the woff2 files behind
        // it. Without the webfonts the card silently falls back to Consolas.
        '--virtual-time-budget=8000',
        `--screenshot=${OUT}`,
        pathToFileURL(CARD).href,
    ], {stdio: 'inherit'});
} finally {
    rmSync(profile, {recursive: true, force: true});
}

console.log(`wrote ${OUT} (${W * SCALE}x${H * SCALE})`);
