import fs from 'node:fs';

const [version, checksum] = process.argv.slice(2);
if (!version || !checksum) {
  throw new Error('usage: marketplace-vsix-status.mjs VERSION SHA256 < MARKETPLACE_JSON');
}

// `vsce show --json` returns the literal string "undefined" before an
// extension has ever been published. Empty output is equivalent: neither has
// a Marketplace version that could conflict with the archive we are shipping.
const body = fs.readFileSync(0, 'utf8').trim();
if (!body || body === 'undefined') {
  process.exit(3);
}

let extension;
try {
  extension = JSON.parse(body);
} catch {
  throw new Error('VS Code Marketplace returned invalid extension metadata.');
}

const published = Array.isArray(extension.versions)
  ? extension.versions.find((item) => item.version === version)
  : undefined;
if (!published) {
  process.exit(3);
}

const property = Array.isArray(published.properties)
  ? published.properties.find((item) => item.key === 'Microsoft.VisualStudio.Services.VsixSha256')
  : undefined;
if (typeof property?.value !== 'string' || property.value.toLowerCase() !== checksum.toLowerCase()) {
  console.error(`Marketplace version ${version} has a different VSIX SHA-256.`);
  process.exit(2);
}
