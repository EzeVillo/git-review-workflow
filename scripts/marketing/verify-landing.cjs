// Run in git-review-marketing with the checkout at /src and screenshots at /output.
// Exercises the public path prefix used by Netlify, without publishing anything.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require('/opt/marketing/node_modules/playwright-core');

const prefix = '/git-review-workflow/';
const root = '/src/docs';
const out = process.env.MARKETING_QA_OUT || '/output';
const types = {'.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
    '.svg': 'image/svg+xml', '.png': 'image/png', '.mp4': 'video/mp4', '.xml': 'application/xml'};

const server = http.createServer((request, response) => {
    const route = new URL(request.url, 'http://localhost').pathname;
    const file = path.resolve(root, decodeURIComponent(route.slice(prefix.length)) + (route.endsWith('/') ? 'index.html' : ''));
    if (!route.startsWith(prefix) || !file.startsWith(root + '/') || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        response.writeHead(404).end();
        return;
    }
    response.writeHead(200, {'content-type': types[path.extname(file)] || 'application/octet-stream'});
    fs.createReadStream(file).pipe(response);
});

async function main() {
    fs.mkdirSync(out, {recursive: true});
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const base = `http://127.0.0.1:${server.address().port}${prefix}`;
    const browser = await chromium.launch({executablePath: '/usr/bin/chromium', args: ['--no-sandbox']});
    try {
        const context = await browser.newContext({viewport: {width: 1440, height: 1000}, locale: 'en-US'});
        // Keep QA traffic out of the shared production metrics.
        await context.route('https://cloud.umami.is/**', route => route.abort());
        const page = await context.newPage();
        const errors = [];
        const missing = [];
        const outbound = new Set();
        page.on('pageerror', error => errors.push(error.message));
        page.on('response', response => { if (response.status() >= 400 && response.url().startsWith(base)) missing.push(response.url()); });
        page.on('request', request => {
            const host = new URL(request.url()).hostname;
            if (!['127.0.0.1', 'fonts.googleapis.com', 'fonts.gstatic.com'].includes(host)) outbound.add(host);
        });
        await page.goto(base);
        const guideRoutes = {en: 'guides/review-pull-requests-locally/', es: 'es/guias/revisar-pull-requests-localmente/'};
        for (const lang of ['en', 'es']) {
            await page.locator(`[data-lang="${lang}"]`).click();
            assert.equal(await page.locator('html').getAttribute('lang'), lang);
            assert.equal(await page.locator('[data-guide-link]').first().getAttribute('href'), guideRoutes[lang]);
            for (const width of [390, 768, 1440]) {
                await page.setViewportSize({width, height: 1000});
                const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
                assert.equal(overflow, false, `Landing ${lang} overflows at ${width}`);
                if (width !== 768) await page.screenshot({path: `${out}/landing-${lang}-${width}.png`});
            }
        }
        for (const lang of ['en', 'es']) {
            await page.goto(base + guideRoutes[lang]);
            assert.equal(await page.locator('html').getAttribute('lang'), lang);
            assert.equal(await page.locator('h1').count(), 1);
            assert.ok((await page.locator('article').innerText()).length > 3000);
            for (const width of [390, 768, 1440]) {
                await page.setViewportSize({width, height: 1000});
                assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, `Guide ${lang} overflows at ${width}`);
                if (width !== 768) await page.screenshot({path: `${out}/guide-${lang}-${width}.png`, fullPage: true});
            }
            const other = lang === 'en' ? 'es' : 'en';
            await page.locator(`nav a[hreflang="${other}"]`).click();
            assert.equal(await page.locator('html').getAttribute('lang'), other);
        }

        // Only the configured tracker is requested; QA blocks it before loading.
        assert.deepEqual([...outbound], ['cloud.umami.is']);
        await page.addInitScript(() => {
            window.qaEvents = [];
            window.qaCopies = [];
            window.umami = {track: (name, properties) => window.qaEvents.push({name, properties})};
            Object.defineProperty(navigator, 'clipboard', {configurable: true, value: {
                writeText: text => {
                    if (window.qaCopyDenied) return Promise.reject(new Error('Clipboard denied'));
                    window.qaCopies.push(text);
                    return Promise.resolve();
                }
            }});
        });
        await page.goto(base);
        await page.locator('[data-copy="#install-npm"]').click();
        assert.deepEqual(await page.evaluate(() => window.qaCopies), ['npm install -g git-review-workflow']);
        assert.deepEqual(await page.evaluate(() => window.qaEvents), [{name: 'install_command_copy', properties: {method: 'npm'}}]);
        await page.locator('[data-copy="#install-baseline"]').click();
        assert.equal(await page.evaluate(() => window.qaEvents.length), 1, 'Base config is not an installation');
        await page.evaluate(() => { window.qaCopyDenied = true; });
        await page.locator('[data-copy="#install-curl"]').click();
        assert.equal(await page.locator('[data-copy="#install-curl"]').getAttribute('data-copied'), null);
        assert.equal(await page.evaluate(() => window.qaEvents.length), 1, 'Denied copies are not counted');
        await page.evaluate(() => { window.qaCopyDenied = false; });
        for (const client of ['vscode', 'jetbrains']) {
            await page.locator(`[data-demo-client="${client}"]`).click();
            await page.locator('#ide-film').evaluate(async video => {
                video.muted = true;
                await video.play(); video.pause();
                await video.play(); video.pause();
            });
        }
        assert.deepEqual(await page.evaluate(() => window.qaEvents), [
            {name: 'install_command_copy', properties: {method: 'npm'}},
            {name: 'demo_play', properties: {interface: 'vscode'}},
            {name: 'demo_play', properties: {interface: 'jetbrains'}},
        ]);
        await page.evaluate(() => { window.umami.track = () => { throw new Error('Collector unavailable'); }; });
        await page.locator('[data-copy="#install-homebrew"]').click();
        assert.equal(await page.locator('[data-copy="#install-homebrew"]').getAttribute('data-copied'), 'true');
        await page.evaluate(() => { window.umami.track = () => Promise.reject(new Error('Collector offline')); });
        await page.locator('[data-copy="#install-windows"]').click();
        assert.equal(await page.locator('[data-copy="#install-windows"]').getAttribute('data-copied'), 'true');
        assert.deepEqual(errors, []);
        assert.deepEqual(missing, []);

        const noScript = await browser.newContext({javaScriptEnabled: false});
        const staticPage = await noScript.newPage();
        for (const lang of ['en', 'es']) {
            await staticPage.goto(base + guideRoutes[lang]);
            assert.ok((await staticPage.locator('article').innerText()).length > 3000, 'Guide works without JavaScript');
        }
        console.log('PASS: EN/ES guides and landing at 390/768/1440px; public path prefix; translations; clipboard success/failure; demo deduplication; collector failures; production tracker blocked in QA; guides without JavaScript.');
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
}

main().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
