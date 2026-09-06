// Editorial assembly from real IDE footage. Run in the capture container.
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import {renderMusic} from './music.mjs';
import {clients} from './clients.mjs';
const source = process.argv[2] || '/output';
const dest = process.argv[3] || '/media';
const clientId = process.argv[4] || 'vscode';
const client = clients[clientId];
if (!client) throw new Error(`Unknown client: ${clientId}`);
fs.mkdirSync(dest, {recursive: true});
// PowerShell 5.1's UTF-8 writer can prepend a BOM to hand-authored cut lists.
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const chapters = readJson(`${source}/chapters.json`);
const at = name => {const item = chapters.find(c => c.name === name); if (!item) throw new Error(`Missing chapter ${name}`); return item.time;};
const ffmpeg = args => execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-threads', '2', ...args], {stdio: 'inherit'});
const encode = ['-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '21', '-pix_fmt', 'yuv420p', '-r', '30', '-movflags', '+faststart'];
const font = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
const bold = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf';
const logo = fs.readFileSync('/src/assets/logo.svg').toString('base64');
const shot = fs.readFileSync(`${source}/reason.png`).toString('base64');
const copy = {
    en: {hook: 'AI wrote it.<br><em>You own<br>the review.</em>', sub: 'Follow the why. Fix the code.<br>Keep your changes.', end: 'Review it in the IDE<br>you already use.', cta: client.cta, labels: ['Open the PR. Stay in your editor.', 'Follow the reasoning, file by file.', 'Catch the edge case. Fix it here.', 'Run the tests. Know it works.', 'Your corrections, on a separate branch.'], kicker: `GIT REVIEW  /  ${client.name.toUpperCase()}`, time: '40 SECONDS · REAL IDE CAPTURE'},
};
function card(lang, ending) {
    const c = copy[lang];
    const shotLayout = clientId === 'vscode' ? 'left:850px;top:160px;width:1440px' : 'left:750px;top:190px;width:1120px';
    const html = `<!doctype html><meta charset="utf-8"><style>
    *{box-sizing:border-box}body{margin:0;width:1920px;height:1080px;overflow:hidden;background:#0B0E14;color:#DCE2ED;font-family:'DejaVu Sans',sans-serif}
    .rail{position:absolute;left:92px;top:74px;font-size:24px;letter-spacing:5px;color:#7A8699}h1{position:absolute;left:92px;top:170px;margin:0;font-size:${ending ? 100 : 94}px;line-height:1.12;letter-spacing:-5px;font-weight:700}em{font-style:normal;color:#4CC46B}.sub{position:absolute;left:96px;top:650px;font-size:30px;line-height:1.6;color:#AAB6C9}.shot{position:absolute;${shotLayout};border:1px solid #354154;border-radius:12px;box-shadow:0 30px 90px #0008}.logo{position:absolute;left:96px;bottom:75px;width:84px;height:84px}.brand{position:absolute;left:204px;bottom:96px;font-family:'DejaVu Sans Mono';font-size:32px}.meta{position:absolute;right:96px;bottom:82px;letter-spacing:3px;font-size:20px;color:#7A8699}.line{position:absolute;left:96px;top:135px;width:85px;height:5px;background:#4CC46B}.cta{position:absolute;left:100px;top:535px;background:#4CC46B;color:#0B0E14;padding:23px 34px;font-size:30px;border-radius:6px}.url{position:absolute;left:102px;top:660px;font-size:24px;color:#AAB6C9}.mark{position:absolute;right:210px;top:310px;width:360px;height:360px;opacity:.95}
    </style><div class="rail">${c.kicker}</div><div class="line"></div>
    ${ending ? `<h1>${c.end}</h1><div class="cta">${c.cta}</div><div class="url">ezevillo.github.io/git-review-workflow</div><img class="mark" src="data:image/svg+xml;base64,${logo}">` : `<img class="shot" src="data:image/png;base64,${shot}"><h1>${c.hook}</h1><div class="sub">${c.sub}</div>`}
    <img class="logo" src="data:image/svg+xml;base64,${logo}"><div class="brand">git review</div><div class="meta">${c.time}</div>`;
    const base = `${source}/${ending ? 'end' : 'poster'}-${lang}`;
    fs.writeFileSync(`${base}.html`, html);
    execFileSync('chromium', ['--headless', '--no-sandbox', '--disable-gpu', '--hide-scrollbars', '--no-pdf-header-footer', '--window-size=1920,1080', '--force-device-scale-factor=1', `--screenshot=${base}.png`, `file://${base}.html`], {stdio: 'ignore'});
    return `${base}.png`;
}
// Cuts remove waiting, never substitute fabricated output. The edit and tests
// remain at real speed. The start wizard is accelerated to fit the short format.
const cuts = fs.existsSync(`${source}/cuts.json`) ? readJson(`${source}/cuts.json`) : [
    [at('before') + 2, at('reading') - at('before') - 1, 6],
    [at('reason') - 1.1, 6, 6],
    [at('edit') - .2, 5, 5],
    [at('tests') - .4, 5, 5],
    [at('finish') - 3.3, 7, 7],
];
const music = renderMusic(`${source}/soundtrack.wav`);
for (const lang of ['en']) {
    const c = copy[lang];
    const poster = card(lang, false), end = card(lang, true);
    fs.copyFileSync(poster, `${dest}/${clientId}-poster-${lang}.png`);
    const parts = [];
    for (const [name, image, duration] of [['intro', poster, 5], ['outro', end, 6]]) {
        const file = `${source}/${name}-${lang}.mp4`;
        ffmpeg(['-loop', '1', '-i', image, '-t', String(duration), '-vf', 'fade=t=in:st=0:d=0.25', ...encode, file]);
        parts.push(file);
    }
    const middle = [];
    for (let i = 0; i < cuts.length; i++) {
        const [start, length, duration] = cuts[i];
        const textfile = `${source}/caption-${lang}-${i}.txt`;
        fs.writeFileSync(textfile, clientId === 'visualstudio' && i === 3 ? 'Three tests. All green.' : c.labels[i]);
        const file = `${source}/scene-${lang}-${i}.mp4`;
        // A tighter editorial crop makes the author's note and boundary readable.
        // Tests and finish return to the full frame, including the branch status.
        const crop = clientId === 'vscode' && (i === 1 || i === 2) ? 'crop=1280:774:0:30,scale=1440:870:flags=lanczos' : 'crop=1440:870:0:30';
        const filter = `setpts=PTS-STARTPTS,setpts=${duration / length}*PTS,${crop},pad=1920:1080:240:160:color=0x0B0E14,drawbox=x=240:y=137:w=72:h=4:color=0x4CC46B:t=fill,drawtext=fontfile=${bold}:textfile=${textfile}:fontsize=49:fontcolor=0xDCE2ED:x=240:y=55,drawtext=fontfile=${font}:text='git review / ${client.name}':fontsize=19:fontcolor=0x7A8699:x=240:y=1047,fade=t=in:st=0:d=0.18`;
        ffmpeg(['-ss', String(start), '-t', String(length), '-i', `${source}/raw.mp4`, '-vf', filter, '-t', String(duration), ...encode, file]);
        middle.push(file);
    }
    const list = `${source}/concat-${lang}.txt`;
    fs.writeFileSync(list, [parts[0], ...middle, parts[1]].map(file => `file '${file}'`).join('\n'));
    ffmpeg(['-f', 'concat', '-safe', '0', '-i', list, '-i', music,
        '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
        '-af', 'loudnorm=I=-18:TP=-1.5:LRA=9,afade=t=out:st=38.2:d=1.8',
        '-t', '40', '-movflags', '+faststart', `${dest}/${clientId}-demo-${lang}.mp4`]);
}
for (const [name, start, duration] of [['reading-order', at('reason') - 1.1, 6], ['edit-and-test', at('edit') + .6, 9], ['finish-review', at('finish') - 3.3, 8]]) {
    // Interactive Windows capture has pauses between actions. Reuse the edited
    // scenes so the excerpt includes both the correction and real test output.
    const assembled = clientId === 'visualstudio';
    const seek = assembled ? {'reading-order': 9, 'edit-and-test': 17, 'finish-review': 27}[name] : start;
    const input = assembled ? `${dest}/${clientId}-demo-en.mp4` : `${source}/raw.mp4`;
    const crop = assembled ? 'crop=1440:870:240:160' : 'crop=1440:870:0:30';
    ffmpeg(['-ss', String(seek), '-t', String(assembled && name === 'finish-review' ? 7 : duration), '-i', input, '-filter_complex', `fps=10,${crop},scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3`, '-loop', '0', `${dest}/${clientId}-${name}.gif`]);
}
console.log(`Rendered English video with original music, poster and three GIFs into ${dest}`);
