const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const {runTests} = require('/work/vscode-extension/node_modules/@vscode/test-electron');
const root = fs.mkdtempSync('/tmp/grv-film-');
const repo = path.join(root, 'rate-limit');
const user = path.join(root, 'profile');
const out = process.env.MARKETING_OUT || '/output';
fs.mkdirSync(repo); fs.mkdirSync(`${user}/User`, {recursive: true}); fs.mkdirSync(out, {recursive: true});
process.env.PATH = `/work/bin:${process.env.PATH}`;
process.env.MARKETING_REPO = repo;
process.env.MARKETING_OUT = out;
const git = (...args) => cp.execFileSync('git', args, {cwd: repo, encoding: 'utf8'});
const write = (name, content) => {fs.mkdirSync(path.dirname(`${repo}/${name}`), {recursive: true}); fs.writeFileSync(`${repo}/${name}`, content);};
git('init', '-b', 'main'); git('config', 'user.name', 'Demo Reviewer'); git('config', 'user.email', 'demo@example.com'); git('config', 'reviewworkflow.base', 'main');
write('package.json', '{"name":"rate-limit","type":"module","scripts":{"test":"node --test"}}\n');
write('README.md', '# Rate limiter\n\nKeep the login endpoint safe.\n');
git('add', '.'); git('commit', '-m', 'Create login service');
git('switch', '-c', 'rate-limit');
write('src/policy.js', '// One place to define the login policy.\nexport const MAX_ATTEMPTS = 5;\nexport const WINDOW_SECONDS = 60;\n');
write('src/rate-limit.js', `import { MAX_ATTEMPTS } from './policy.js';

// Block the next request once the limit is reached.
export function checkRateLimit(attempts, limit = MAX_ATTEMPTS) {
  if (attempts > limit) {
    return { allowed: false, retryAfter: 60 };
  }

  return { allowed: true, retryAfter: 0 };
}
`);
write('test/rate-limit.test.js', `import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkRateLimit } from '../src/rate-limit.js';

test('allows requests below the limit', () => {
  assert.equal(checkRateLimit(4).allowed, true);
});

test('blocks the request at the limit', () => {
  assert.equal(checkRateLimit(5).allowed, false);
});

test('tells the client when to retry', () => {
  assert.equal(checkRateLimit(6).retryAfter, 60);
});
`);
git('add', '.'); git('commit', '-m', 'Add login rate limiting');
git('review', 'walkthrough', 'init');
let walk = fs.readFileSync(`${repo}/.review/walkthrough.md`, 'utf8');
walk = walk.replace(/<!-- heads-up:[\s\S]*?-->/, 'Protect the login endpoint without locking out valid requests. Start with the policy, then check the boundary.');
const entries = [
    ['src/policy.js', 'The policy allows five attempts per minute. Read this first: the boundary in the limiter must match it.'],
    ['src/rate-limit.js', '> key\nCheck the exact boundary: once five attempts are used, the next request must be blocked.'],
    ['test/rate-limit.test.js', 'Exercise the boundary and the retry hint. Run these tests before finishing the review.'],
];
entries.forEach(([name, why], i) => {const from = `## ?. ${name}\n<!-- why: -->`; if (!walk.includes(from)) throw new Error(`Missing ${name}`); walk = walk.replace(from, `## ${i + 1}. ${name}\n${why}`);});
write('.review/walkthrough.md', walk); git('review', 'walkthrough', 'build'); git('add', '.review'); git('commit', '-m', 'Explain the reading order');
const before = cp.spawnSync('node', ['--test'], {cwd: repo, encoding: 'utf8'});
if (before.status !== 1 || !before.stdout.includes('blocks the request at the limit')) throw new Error('The demo must begin with a failing boundary test');
fs.writeFileSync(`${out}/before-tests.txt`, before.stdout);
fs.writeFileSync(`${user}/User/settings.json`, JSON.stringify({
    'workbench.colorTheme': 'Default Dark Modern', 'window.zoomLevel': 0,
    'editor.fontSize': 20, 'editor.lineHeight': 30, 'editor.minimap.enabled': false,
    'editor.scrollBeyondLastLine': false, 'editor.renderLineHighlight': 'none',
    'editor.stickyScroll.enabled': false, 'diffEditor.renderSideBySide': false,
    'editor.quickSuggestions': false, 'editor.suggestOnTriggerCharacters': false,
    'workbench.startupEditor': 'none', 'workbench.tips.enabled': false,
    'workbench.editor.enablePreview': false, 'window.commandCenter': false,
    'breadcrumbs.enabled': false, 'terminal.integrated.fontSize': 18,
    'terminal.integrated.shellIntegration.enabled': false,
    'gitReview.defaultSource': 'offline', 'git.openRepositoryInParentFolders': 'never',
    'security.workspace.trust.enabled': false, 'extensions.ignoreRecommendations': true,
    'telemetry.telemetryLevel': 'off', 'update.mode': 'none', 'git.autofetch': false,
    'chat.disableAIFeatures': true
}, null, 2));
fs.mkdirSync('/work/vscode-extension/marketing', {recursive: true});
fs.copyFileSync('/src/scripts/marketing/capture.cjs', '/work/vscode-extension/marketing/capture.cjs');
runTests({vscodeExecutablePath: '/work/vscode-extension/.vscode-test/vscode-linux-x64-1.136.1/code',
    extensionDevelopmentPath: '/work/vscode-extension', extensionTestsPath: '/work/vscode-extension/marketing/capture.cjs',
    launchArgs: [repo, `--user-data-dir=${user}`, '--no-sandbox', '--disable-gpu', '--skip-welcome', '--skip-release-notes', '--disable-workspace-trust', '--window-size=1440,900'],
}).catch(error => {console.error(error); process.exitCode = 1;});
