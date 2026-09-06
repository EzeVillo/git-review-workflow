FROM git-review-vscode-tests
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg xdotool chromium fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
RUN npm install --prefix /opt/marketing playwright-core@1.55.0 --no-audit --no-fund
ENTRYPOINT ["sh", "/src/scripts/marketing/entrypoint.sh"]
