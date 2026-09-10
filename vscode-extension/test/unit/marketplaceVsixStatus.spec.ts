import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const checksum = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const extensionRoot = process.cwd();
const script = resolve(extensionRoot, 'scripts', 'marketplace-vsix-status.mjs');
const fixtures = resolve(extensionRoot, '..', 'tests', 'fixtures', 'vscode-marketplace');

function marketplaceStatus(fixture: string): number {
  try {
    execFileSync(process.execPath, [script, '0.4.0', checksum], {
      input: readFileSync(resolve(fixtures, fixture)),
      stdio: 'pipe',
    });
    return 0;
  } catch (error: unknown) {
    return (error as { status?: number }).status ?? 1;
  }
}

describe('marketplace VSIX status', () => {
  it('treats a not-yet-published extension as absent', () => {
    assert.equal(marketplaceStatus('not-published.txt'), 3);
  });

  it('treats an absent target version as absent', () => {
    assert.equal(marketplaceStatus('absent-version.json'), 3);
  });

  it('accepts a matching published VSIX', () => {
    assert.equal(marketplaceStatus('matching-hash.json'), 0);
  });

  it('rejects a mismatching published VSIX', () => {
    assert.equal(marketplaceStatus('mismatching-hash.json'), 2);
  });
});
