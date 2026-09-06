// Run in the marketing image with the example mounted at /fixture (read-only).
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const git = (...args) => execFileSync('git', ['-c', 'safe.directory=/fixture', '-C', '/fixture', ...args], {encoding: 'utf8'}).trim();
const branch = git('branch', '--show-current');
assert.equal(branch, 'review-fixes/rate-limit');
assert.equal(git('diff', '--cached', '--name-only'), 'src/RateLimiter.cs');
assert.equal(git('diff'), '');
const patch = git('diff', '--cached');
assert.ok(patch.includes('+        if (attempts >= Policy.MaxAttempts)'));
assert.ok(git('show', 'rate-limit:src/RateLimiter.cs').includes('attempts > Policy.MaxAttempts'));
const before = fs.readFileSync('/output/before-tests.txt', 'utf8');
const tests = fs.readFileSync('/fixture/bin/Test results.txt', 'utf8');
assert.match(before, /Failed RateLimiterTests\.BlocksRequestsAtTheLimit/);
assert.match(before, /Total tests: 3/);
assert.match(before, /Passed: 2/);
assert.match(before, /Failed: 1/);
assert.match(tests, /Test Run Successful\./);
assert.match(tests, /Total tests: 3/);
assert.match(tests, /Passed: 3/);
for (const name of ['AllowsRequestsBelowTheLimit', 'BlocksRequestsAtTheLimit', 'BlocksRequestsAboveTheLimit']) {
    assert.ok(tests.includes(`Passed RateLimiterTests.${name}`));
}
fs.writeFileSync('/output/verification.json', JSON.stringify({client: 'Visual Studio', host: 'Visual Studio 2026 Insiders', branch, tests, patch, testRunner: '.NET 8 / xUnit in Docker; unmodified output viewed in the IDE'}, null, 2));
console.log('PASS: original boundary fails; corrected tests pass; only the correction is staged; author branch is unchanged.');
