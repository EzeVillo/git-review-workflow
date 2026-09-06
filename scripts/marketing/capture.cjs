// Runs inside the real VS Code extension host. No mocked panels or CLI results.
const vscode = require('vscode');
const fs = require('node:fs');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const out = process.env.MARKETING_OUT;
const repo = process.env.MARKETING_REPO;
const git = (...args) => cp.execFileSync('git', args, {cwd: repo, encoding: 'utf8'}).trim();
const command = (...args) => vscode.commands.executeCommand(...args);
let recorder;
const chapters = [];
let started;
async function mark(name) {
    await delay(700);
    chapters.push({name, time: (Date.now() - started) / 1000});
    fs.writeFileSync(`${out}/chapters.json`, JSON.stringify(chapters, null, 2));
    cp.execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'x11grab', '-video_size', '1440x900', '-i', process.env.DISPLAY, '-frames:v', '1', `${out}/${name}.png`]);
    console.log(`CAPTURE ${name}`);
}

exports.run = async function () {
    const extension = vscode.extensions.getExtension('EzeVillo.git-review-workflow');
    assert.ok(extension);
    const api = await extension.activate();
    await api.refresh();
    await command('workbench.view.extension.gitReview');
    await command('workbench.action.closeAllEditors');
    await command('workbench.action.closeAuxiliaryBar');
    // Xvfb has no window manager: explicitly focus the visible Electron window.
    const windows = cp.execFileSync('xdotool', ['search', '--onlyvisible', '--class', 'Code'], {encoding: 'utf8'}).trim().split('\n');
    cp.execFileSync('xdotool', ['windowfocus', windows.at(-1)]);
    cp.execFileSync('xdotool', ['mousemove', '227', '420', 'mousedown', '1', 'mousemove', '440', '420', 'mouseup', '1']);
    await command('notifications.clearAll');
    const doc = await vscode.workspace.openTextDocument(`${repo}/src/rate-limit.js`);
    await vscode.window.showTextDocument(doc);
    await delay(2500);

    // Keep the native pickers visible, then select with actual keyboard input.
    const pick = vscode.window.showQuickPick;
    vscode.window.showQuickPick = function (items, options, token) {
        console.log('PICK', options?.title);
        const result = pick.call(this, items, options, token);
        const sample = items[0];
        let text = sample?.candidate ? 'rate-limit' : sample?.source ? 'Offline' : sample?.layout ? 'Walkthrough (recommended)' : 'A separate branch';
        setTimeout(() => {
            cp.execFileSync('xdotool', ['type', '--clearmodifiers', '--delay', '55', text]);
            setTimeout(() => cp.execFileSync('xdotool', ['key', 'Return']), 700);
        }, 900);
        return result;
    };
    recorder = cp.spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'x11grab', '-framerate', '30', '-video_size', '1440x900', '-i', process.env.DISPLAY, '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', '-pix_fmt', 'yuv420p', `${out}/raw.mp4`], {stdio: ['pipe', 'ignore', 'inherit']});
    started = Date.now();
    try {
        await mark('before');
        await delay(2000);
        await Promise.race([command('gitReview.startReview'), delay(30000).then(() => {throw new Error('Start wizard timed out');})]);
        const state = await api.refresh();
        assert.equal(state.state.mode, 'walk');
        assert.equal(state.situation, 'review');
        await command('gitReview.openChange');
        await mark('reading');
        await delay(4200);
        await command('gitReview.next');
        assert.equal((await api.refresh()).state.position, 2);
        await mark('reason');
        await delay(4500);
        await command('gitReview.openEntry');
        const editor = vscode.window.activeTextEditor;
        assert.ok(editor.document.uri.fsPath.endsWith('src/rate-limit.js'));
        const text = editor.document.getText();
        const index = text.indexOf('attempts > limit');
        assert.ok(index >= 0);
        const start = editor.document.positionAt(index);
        editor.selection = new vscode.Selection(start, editor.document.positionAt(index + 'attempts > limit'.length));
        await mark('edit');
        await delay(1500);
        await command('type', {text: 'attempts >= limit'});
        await editor.document.save();
        await command('hideSuggestWidget');
        editor.selection = new vscode.Selection(editor.selection.end, editor.selection.end);
        await delay(1700);
        const test = cp.spawnSync('node', ['--test'], {cwd: repo, encoding: 'utf8'});
        assert.equal(test.status, 0, test.stdout + test.stderr);
        const terminal = vscode.window.createTerminal({name: 'Tests', cwd: repo, shellPath: '/bin/bash', shellArgs: ['--noprofile', '--norc'], env: {PS1: '$ ', TERM: 'xterm-256color'}});
        terminal.show(true);
        await delay(500);
        cp.execFileSync('xdotool', ['mousemove', '950', '578', 'mousedown', '1', 'mousemove', '950', '450', 'mouseup', '1']);
        terminal.sendText('node --test');
        await delay(2700);
        await mark('tests');
        await delay(4000);
        await command('workbench.action.closePanel');
        await command('gitReview.finishReview');
        await api.refresh();
        assert.equal(git('branch', '--show-current'), 'review-fixes/rate-limit');
        assert.equal(git('diff', '--cached', '--name-only'), 'src/rate-limit.js');
        const patch = git('diff', '--cached');
        assert.ok(patch.includes('+  if (attempts >= limit)'));
        fs.writeFileSync(`${out}/verification.json`, JSON.stringify({client: extension.packageJSON.version, branch: git('branch', '--show-current'), tests: test.stdout, patch}, null, 2));
        await mark('finish');
        await delay(5000);
        // Show the exact result in the native SCM view for the final insert.
        await command('workbench.view.scm');
        await command('git.openChange', vscode.Uri.file(`${repo}/src/rate-limit.js`));
        await mark('result');
        await delay(4000);
    } finally {
        vscode.window.showQuickPick = pick;
        recorder.stdin.write('q');
        await new Promise(resolve => recorder.on('exit', resolve));
    }
};
