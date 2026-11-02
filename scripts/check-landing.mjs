// Static deployment checks. No packages, network requests, or build step needed.
import assert from 'node:assert/strict';
import {existsSync, readFileSync, readdirSync} from 'node:fs';
import {join, relative, resolve, sep} from 'node:path';

const root = resolve(process.cwd(), 'docs');
const base = new URL('https://git-review.ezevillo.com/');
const read = path => readFileSync(path, 'utf8');
const attrs = tag => Object.fromEntries([...tag.matchAll(/([\w:-]+)\s*=\s*"([^"]*)"/g)]
    .map(([, name, value]) => [name, value.replaceAll('&amp;', '&')]));
const tags = (html, name) => [...html.matchAll(new RegExp(`<${name}\\b[^>]*>`, 'gi'))]
    .map(match => attrs(match[0]));

function htmlFiles(dir) {
    return readdirSync(dir, {withFileTypes: true}).flatMap(entry => {
        const path = join(dir, entry.name);
        return entry.isDirectory() ? htmlFiles(path) : entry.name.endsWith('.html') ? [path] : [];
    });
}

function localFile(url) {
    const name = decodeURIComponent(url.pathname.slice(base.pathname.length));
    const file = resolve(root, name.endsWith('/') || !name ? name + 'index.html' : name);
    assert.ok(file.startsWith(root + sep), `Path outside docs: ${url.href}`);
    return file;
}

const pages = new Map();
for (const path of htmlFiles(root)) {
    const html = read(path);
    const route = relative(root, path).split(sep).join('/').replace(/index\.html$/, '');
    const url = new URL(route, base).href;
    const links = tags(html, 'link');
    const meta = tags(html, 'meta');
    const language = tags(html, 'html')[0]?.lang;
    assert.ok(['en', 'es'].includes(language), `${path}: missing page language`);
    assert.equal((html.match(/<h1\b/gi) ?? []).length, 1, `${path}: expected one H1`);
    assert.match(html, /<title>[^<]+<\/title>/, `${path}: missing title`);
    assert.ok(meta.some(tag => tag.name === 'description' && tag.content?.trim()), `${path}: missing description`);
    assert.equal(links.filter(tag => tag.rel === 'canonical').length, 1, `${path}: expected one canonical`);
    assert.equal(links.find(tag => tag.rel === 'canonical').href, url, `${path}: incorrect canonical`);
    assert.equal(meta.find(tag => tag.property === 'og:url')?.content, url, `${path}: incorrect social URL`);
    assert.doesNotMatch(html, /https:\/\/ezevillo\.github\.io/, `${path}: obsolete public URL`);
    assert.ok(!meta.some(tag => tag.name === 'robots' && /noindex/i.test(tag.content)), `${path}: noindex`);
    pages.set(url, {path, html, links, language});
}

for (const [url, page] of pages) {
    // Includes stylesheets, images, video posters, scripts, and fragment targets.
    for (const match of page.html.matchAll(/<(?:a|link|img|script|video|source)\b[^>]*>/gi)) {
        const tag = attrs(match[0]);
        for (const name of ['href', 'src', 'poster']) {
            if (!tag[name]) continue;
            const target = new URL(tag[name], url);
            if (target.origin !== base.origin || !target.pathname.startsWith(base.pathname)) continue;
            const file = localFile(target);
            assert.ok(existsSync(file), `${page.path}: missing ${tag[name]}`);
            if (target.hash && file.endsWith('.html')) {
                const id = decodeURIComponent(target.hash.slice(1));
                const ids = [...read(file).matchAll(/\bid="([^"]*)"/g)].map(match => match[1]);
                assert.ok(ids.includes(id), `${page.path}: missing fragment ${tag[name]}`);
            }
        }
    }
    const alternates = page.links.filter(tag => tag.rel === 'alternate' && tag.hreflang);
    if (url !== base.href) {
        assert.deepEqual(alternates.map(tag => tag.hreflang).sort(), ['en', 'es', 'x-default'], `${page.path}: missing translations`);
        assert.equal(alternates.find(tag => tag.hreflang === page.language)?.href, url, `${page.path}: missing self hreflang`);
    }
    for (const alternate of alternates) {
        const translated = pages.get(alternate.href);
        assert.ok(translated, `${page.path}: translation is not a published page`);
        if (alternate.hreflang === 'x-default') continue;
        assert.equal(translated.language, alternate.hreflang, `${page.path}: translation language mismatch`);
        assert.ok(translated.links.some(tag => tag.rel === 'alternate' && tag.href === url
            && tag.hreflang === page.language), `${page.path}: nonreciprocal translation`);
    }
}

const sitemap = read(join(root, 'sitemap.xml'));
const urls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map(match => match[1]);
assert.equal(new Set(urls).size, urls.length, 'Duplicate sitemap URL');
assert.deepEqual([...urls].sort(), [...pages.keys()].sort(), 'Sitemap must contain exactly the published HTML pages');
console.log(`landing: ${pages.size} pages; local links, assets, fragments, canonical URLs, translations, and sitemap ok`);
