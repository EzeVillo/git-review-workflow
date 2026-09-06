#!/bin/sh
set -eu
mkdir -p /work/bin /work/vscode-extension /output /media
cp -R /src/bin/. /work/bin/
chmod +x /work/bin/git-review /work/bin/git-review-verbs/*
cp /src/vscode-extension/package.json /src/vscode-extension/package-lock.json \
    /src/vscode-extension/esbuild.js /src/vscode-extension/tsconfig.json /work/vscode-extension/
cp -R /src/vscode-extension/src /src/vscode-extension/scripts /src/vscode-extension/media /work/vscode-extension/
chown -R node:node /work /output /media
exec su node -c 'cd /work/vscode-extension && npm ci && npm run compile && node -e "require(\"@vscode/test-electron\").downloadAndUnzipVSCode(\"1.136.1\")" && xvfb-run -a -s "-screen 0 1440x900x24" node /src/scripts/marketing/launch.cjs && node /src/scripts/marketing/render.mjs /output /media'
