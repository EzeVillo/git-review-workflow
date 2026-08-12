import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

function readSvg(path) {
  const abs = join(root, path);
  if (!existsSync(abs)) {
    fail(`Missing ${path}`);
    return '';
  }
  return readFileSync(abs, 'utf8');
}

function rootTag(svg) {
  const match = svg.match(/<svg\b([^>]*)>/i);
  return match ? match[1] : '';
}

function attr(attrs, name) {
  const match = attrs.match(new RegExp(`\\b${name}="([^"]*)"`));
  return match ? match[1] : '';
}

function shapesOf(svg) {
  const tags = svg.match(/<(rect|circle|line|path|polyline|polygon|g)\b[^>]*>/gi) ?? [];
  return tags.map((tag) =>
    tag
      .replace(/\s(?:fill|stroke|stop-color|class|id)="[^"]*"/gi, '')
      .replace(/\s+/g, ' ')
      .trim(),
  );
}

const logo = readSvg('assets/logo.svg');
if (logo) {
  const attrs = rootTag(logo);
  if (attr(attrs, 'viewBox') !== '0 0 128 128') {
    fail('assets/logo.svg must use viewBox="0 0 128 128"');
  }
  if (attr(attrs, 'width') || attr(attrs, 'height')) {
    fail('assets/logo.svg must not declare fixed width or height');
  }
  if (/<image\b/i.test(logo) || /data:image\//i.test(logo)) {
    fail('assets/logo.svg must be pure vector SVG without embedded raster images');
  }
}

const colorIcon = readSvg('vscode-extension/media/icon.svg');
if (logo && colorIcon && JSON.stringify(shapesOf(logo)) !== JSON.stringify(shapesOf(colorIcon))) {
  fail('assets/logo.svg geometry must match vscode-extension/media/icon.svg');
}

// GitHub Pages publishes /docs only, so the landing page cannot reference
// assets/logo.svg and carries its own copy. Same generator writes both; drift
// between them would only show up as a stale favicon nobody looks at.
const siteLogo = readSvg('docs/logo.svg');
if (logo && siteLogo && siteLogo !== logo) {
  fail('docs/logo.svg must be identical to assets/logo.svg — regenerate, do not hand-edit');
}

const landing = readSvg('docs/index.html');
if (landing && !/<link[^>]*\brel="icon"[^>]*\bhref="logo\.svg"|<link[^>]*\bhref="logo\.svg"[^>]*\brel="icon"/.test(landing)) {
  fail('docs/index.html must use logo.svg as its favicon');
}

for (const file of [
  'jetbrains-plugin/src/main/resources/META-INF/pluginIcon.svg',
  'jetbrains-plugin/src/main/resources/META-INF/pluginIcon_dark.svg',
]) {
  const svg = readSvg(file);
  const attrs = rootTag(svg);
  if (attr(attrs, 'width') !== '40' || attr(attrs, 'height') !== '40') {
    fail(`${file} must keep JetBrains marketplace dimensions at 40x40`);
  }
}

for (const file of [
  'jetbrains-plugin/src/main/resources/icons/gitReviewToolWindow.svg',
  'jetbrains-plugin/src/main/resources/icons/gitReviewToolWindow_dark.svg',
]) {
  const svg = readSvg(file);
  const attrs = rootTag(svg);
  if (attr(attrs, 'width') !== '16' || attr(attrs, 'height') !== '16') {
    fail(`${file} must keep JetBrains tool-window dimensions at 16x16`);
  }
}

if (!process.exitCode) {
  console.log('logo asset contract ok');
}
