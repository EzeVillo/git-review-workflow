// Run in the marketing image, with the checkout mounted at /src.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const {chromium} = require(process.env.MARKETING_PLAYWRIGHT || '/opt/marketing/node_modules/playwright-core');
const root = '/src/docs/media';
const out = process.env.MARKETING_QA_OUT || '/output';
fs.mkdirSync(out, {recursive: true});
const clients = ['vscode', 'jetbrains', 'visualstudio'];
for (const client of clients) {
    const file = `${root}/${client}-demo-en.mp4`;
    const probe = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file], {encoding: 'utf8'}));
    assert.equal(probe.streams.length, 2, 'Video includes its original instrumental soundtrack');
    assert.equal(probe.streams[0].codec_name, 'h264');
    assert.equal(probe.streams[0].width, 1920);
    assert.equal(probe.streams[0].height, 1080);
    assert.equal(probe.streams[1].codec_name, 'aac');
    assert.equal(probe.streams[1].channels, 2);
    assert.equal(probe.streams[1].sample_rate, '48000');
    assert.ok(Math.abs(Number(probe.streams[1].duration) - 40) < .1);
    assert.ok(Math.abs(Number(probe.format.duration) - 40) < .3, probe.format.duration);
    execFileSync('ffmpeg', ['-v', 'error', '-i', file, '-f', 'null', '-']);
assert.ok(!fs.existsSync(`${root}/${client}-demo-es.mp4`), 'Only the English film ships');
assert.ok(!fs.existsSync(`${root}/${client}-poster-es.png`), 'Only the English poster ships');
const {spawnSync} = require('node:child_process');
const loudness = spawnSync('ffmpeg', ['-hide_banner', '-i', file, '-af', 'loudnorm=I=-18:TP=-1.5:LRA=9:print_format=json', '-vn', '-f', 'null', '-'], {encoding: 'utf8'});
assert.equal(loudness.status, 0, loudness.stderr);
const levels = JSON.parse(loudness.stderr.slice(loudness.stderr.lastIndexOf('{')));
assert.ok(Number(levels.input_i) >= -20 && Number(levels.input_i) <= -16, `Music loudness: ${levels.input_i} LUFS`);
assert.ok(Number(levels.input_tp) <= -1, `Music true peak: ${levels.input_tp} dBTP`);
console.log(`${client}: ${levels.input_i} LUFS, ${levels.input_tp} dBTP, AAC stereo 48 kHz.`);
for (const name of ['reading-order', 'edit-and-test', 'finish-review']) {
    const file = `${root}/${client}-${name}.gif`;
    const probe = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file], {encoding: 'utf8'}));
    assert.equal(probe.streams[0].width, 960);
    assert.ok(Number(probe.format.duration) >= 6 && Number(probe.format.duration) <= 10);
    execFileSync('ffmpeg', ['-v', 'error', '-i', file, '-f', 'null', '-']);
}
}
(async () => {
    const browser = await chromium.launch({executablePath: '/usr/bin/chromium', args: ['--no-sandbox']});
    try {
        const page = await browser.newPage({viewport: {width: 1440, height: 1000}, reducedMotion: 'reduce'});
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        await page.goto('file:///src/docs/index.html', {waitUntil: 'load'});
        await page.locator('[data-lang="en"]').click();
        assert.equal(await page.locator('#ide-film').getAttribute('preload'), 'none');
        assert.equal(await page.locator('#ide-film').getAttribute('autoplay'), null);
        assert.equal(await page.locator('#ide-film').getAttribute('controls'), '');
        await page.locator('#demo').scrollIntoViewIfNeeded();
        await page.screenshot({path: `${out}/landing-desktop.png`});
        for (const client of clients) {
          await page.locator(`[data-demo-client="${client}"]`).click();
          assert.equal(await page.locator(`[data-demo-client="${client}"]`).getAttribute('aria-pressed'), 'true');
          assert.equal(await page.locator('#ide-film').evaluate(v => v.paused), true);
          for (const lang of ['en', 'es']) {
            await page.locator(`[data-lang="${lang}"]`).click();
            assert.equal(await page.locator('html').getAttribute('lang'), lang);
            assert.equal(await page.locator('#ide-film').getAttribute('src'), `media/${client}-demo-en.mp4`);
            assert.equal(await page.locator('#ide-film').getAttribute('poster'), `media/${client}-poster-en.png`);
            const playback = await page.locator('#ide-film').evaluate(async video => {
                await video.play();
                await new Promise(resolve => setTimeout(resolve, 600));
                video.pause();
                return {time: video.currentTime, width: video.videoWidth, duration: video.duration};
            });
            assert.ok(playback.time > 0, `Video must play in ${lang}`);
            assert.equal(playback.width, 1920);
            assert.ok(Math.abs(playback.duration - 40) < .3);
          }
          await page.goto(`file:///src/docs/index.html#demo-${client}`);
          assert.equal(await page.locator('#ide-film').getAttribute('src'), `media/${client}-demo-en.mp4`);
        }
        for (const width of [390, 768, 1440]) {
            await page.setViewportSize({width, height: 1000});
            await page.locator('#demo').scrollIntoViewIfNeeded();
            const layout = await page.evaluate(() => ({page: document.documentElement.scrollWidth, viewport: innerWidth, film: document.querySelector('#ide-film').getBoundingClientRect().width}));
            assert.ok(layout.page <= width, `Horizontal overflow at ${width}: ${layout.page}`);
            assert.ok(layout.film <= width);
            if (width === 390) await page.screenshot({path: `${out}/landing-mobile.png`});
        }
        const missing = await page.evaluate(() => [...document.querySelectorAll('[data-i18n]')].filter(el => !el.textContent.trim()).map(el => el.dataset.i18n));
        assert.deepEqual(missing, []);
        assert.deepEqual(errors, []);
        console.log('PASS: Three English 1080p films with music play in both page languages; nine GIFs decode; client selection and deep links work; 390/768/1440px layouts have no overflow; no page errors.');
    } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
