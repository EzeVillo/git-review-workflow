# VS Code and Visual Studio Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar automáticamente las extensiones de VS Code y Visual Studio desde tags independientes, adjuntando el VSIX construido al GitHub Release correspondiente.

**Architecture:** Dos workflows independientes reflejan los namespaces de versión de cada cliente. El de VS Code empaqueta y publica el VSIX con `vsce` en Ubuntu; el de Visual Studio prueba y crea el VSIX net472 con el MSBuild de Visual Studio en Windows, y lo publica mediante `VsixPublisher.exe` y un manifiesto de Marketplace versionado.

**Tech Stack:** GitHub Actions, Node.js 22, npm, `@vscode/vsce`, PowerShell, .NET 8, MSBuild/Visual Studio 2022, `VsixPublisher.exe`, Bats.

## Global Constraints

- Los tags son `vscode-vX.Y.Z` y `visualstudio-vX.Y.Z`; no comparten versión ni release con la CLI, TUI o JetBrains.
- El secreto existente es `VS_MARKETPLACE_TOKEN`; solo puede llegar a los comandos que publican, mediante variables de entorno.
- Cada workflow debe abortar antes de descargar dependencias si faltan el secreto o la coincidencia tag-versión.
- Los GitHub Releases adjuntan el VSIX generado y usan `--latest=false`.
- Las notas se extraen del CHANGELOG propio con `index($0, v) == 1`, nunca con `--generate-notes`.
- El VSIX de Visual Studio se construye exclusivamente en `windows-latest` con `visualstudio-extension/build-vsix.ps1`.
- Los documentos de desarrollo se escriben en español; los nombres de tests Bats son ASCII.

---

### Task 1: Fijar el contrato de los dos workflows mediante Bats

**Files:**
- Create: `tests/release-clients.bats`
- Modify: `tests/release-notes.bats:97-118`

**Interfaces:**
- Consumes: YAML textual en `.github/workflows/release-vscode.yml` y `.github/workflows/release-visualstudio.yml`; manifiesto `visualstudio-extension/marketplace/publishmanifest.json`.
- Produces: gates que obligan a conservar namespaces de tags, preflight del secreto, artefactos, publicación y cuerpo de release.

- [ ] **Step 1: Write the failing test**

Crear `tests/release-clients.bats` con estas verificaciones concretas:

```sh
#!/usr/bin/env bats

setup() {

	REPO="$BATS_TEST_DIRNAME/.."
	VSCODE="$REPO/.github/workflows/release-vscode.yml"
	VISUALSTUDIO="$REPO/.github/workflows/release-visualstudio.yml"
}

@test "release-clients: workflows use their isolated tag namespaces" {

	grep -Fq '"vscode-v*"' "$VSCODE"
	grep -Fq '"visualstudio-v*"' "$VISUALSTUDIO"
}

@test "release-clients: workflows require the shared Marketplace secret before build" {

	for workflow in "$VSCODE" "$VISUALSTUDIO"; do

		grep -Fq 'secrets.VS_MARKETPLACE_TOKEN' "$workflow"
		grep -Fq 'VS_MARKETPLACE_TOKEN is not set.' "$workflow"
	done
}

@test "release-clients: VS Code packages and publishes the exact VSIX" {

	grep -Fq 'npm run package' "$VSCODE"
	grep -Fq 'vsce publish --packagePath' "$VSCODE"
	grep -Fq 'git-review-workflow-${VERSION}.vsix' "$VSCODE"
}

@test "release-clients: Visual Studio builds and publishes the exact VSIX" {

	grep -Fq 'runs-on: windows-latest' "$VISUALSTUDIO"
	grep -Fq './build-vsix.ps1' "$VISUALSTUDIO"
	grep -Fq 'VsixPublisher.exe' "$VISUALSTUDIO"
	grep -Fq 'GitReview.VS.vsix' "$VISUALSTUDIO"
	grep -Fq 'publishmanifest.json' "$VISUALSTUDIO"
}

@test "release-clients: Visual Studio publish manifest is public and owns its listing metadata" {

	manifest="$REPO/visualstudio-extension/marketplace/publishmanifest.json"
	[ -f "$manifest" ]
	grep -Fq '"publisher": "EzeVillo"' "$manifest"
	grep -Fq '"internalName": "git-review-workflow-vs"' "$manifest"
	grep -Fq '"overview": "overview.md"' "$manifest"
	grep -Fq '"private": false' "$manifest"
}
```

Extender el loop de `release-notes.bats` para incluir los dos workflows nuevos en la comprobación de `index($0, v) == 1`, `--notes-file` y ausencia de `--generate-notes`.

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/run-docker.sh release-clients.bats release-notes.bats`

Expected: FAIL porque los workflows y el publish manifest todavía no existen.

- [ ] **Step 3: Keep the gates focused on release behavior**

No crear mocks de Marketplace ni copiar secretos a tests. Los asserts leen únicamente configuración versionada y requieren tanto publicación como GitHub Release no-latest.

- [ ] **Step 4: Run test to verify the gates remain meaningful**

Run: `./tests/run-docker.sh release-clients.bats release-notes.bats`

Expected: sigue FAIL hasta completar Tasks 2 y 3; los mensajes nombran el workflow o manifiesto faltante.

- [ ] **Step 5: Commit**

```sh
git add tests/release-clients.bats tests/release-notes.bats
git commit -m "test: cover client release workflows"
```

### Task 2: Publicar la extensión de VS Code desde `vscode-v*`

**Files:**
- Create: `.github/workflows/release-vscode.yml`
- Modify: `vscode-extension/CONTRIBUTING.md:170-220`

**Interfaces:**
- Consumes: tag `vscode-vX.Y.Z`, `vscode-extension/package.json`, `vscode-extension/CHANGELOG.md`, `VS_MARKETPLACE_TOKEN`.
- Produces: `git-review-workflow-X.Y.Z.vsix` publicado con `vsce` y adjunto a un GitHub Release no-latest.

- [ ] **Step 1: Write the minimal workflow**

Crear un workflow Ubuntu con el trigger y el preflight exactos:

```yaml
name: release-vscode

on:
  push:
    tags:
      - "vscode-v*"

permissions:
  contents: write
```

El primer step calcula `version="${GITHUB_REF_NAME#vscode-v}"`, extrae el campo `version` de `vscode-extension/package.json`, aborta si no coincide y publica `version` en `$GITHUB_OUTPUT`. El segundo step aborta con `VS_MARKETPLACE_TOKEN is not set.` si el secreto está vacío.

- [ ] **Step 2: Build and verify the package before publishing**

Usar `actions/setup-node@v4` con Node 22 y cache de npm para `vscode-extension/package-lock.json`. En `vscode-extension`, ejecutar:

```sh
npm ci
npm run test:unit
npm run package
test -s "git-review-workflow-${VERSION}.vsix"
```

Publicar el archivo verificado sin volver a empaquetar:

```sh
npx vsce publish --packagePath "git-review-workflow-${VERSION}.vsix" \
  --pat "$PUBLISH_TOKEN"
```

`PUBLISH_TOKEN` proviene exclusivamente de `${{ secrets.VS_MARKETPLACE_TOKEN }}`.

- [ ] **Step 3: Attach the produced VSIX and explicit release notes**

Extraer la sección de `vscode-extension/CHANGELOG.md` con:

```sh
awk -v v="## [${VERSION}]" '
  index($0, v) == 1 { on = 1; next }
  on && /^## \[/ { exit }
  on { print }
' vscode-extension/CHANGELOG.md >"$notes"
```

Usar el fallback `See vscode-extension/CHANGELOG.md` si está vacía y crear el release:

```sh
gh release create "$GITHUB_REF_NAME" "vscode-extension/git-review-workflow-${VERSION}.vsix" \
  --repo "$GITHUB_REPOSITORY" \
  --title "VS Code extension ${VERSION}" \
  --notes-file "$notes" \
  --latest=false
```

- [ ] **Step 4: Document the release command**

Al final de Packaging en `vscode-extension/CONTRIBUTING.md`, agregar que, tras actualizar el CHANGELOG y commitear, `git tag vscode-vX.Y.Z && git push origin vscode-vX.Y.Z` ejecuta las pruebas, empaqueta, publica y adjunta el VSIX. Indicar que requiere el secreto de repositorio `VS_MARKETPLACE_TOKEN`, sin revelar su valor.

- [ ] **Step 5: Run focused tests**

Run: `./tests/run-docker.sh release-clients.bats release-notes.bats`

Expected: los asserts de VS Code pasan; los de Visual Studio continúan fallando hasta la Task 3.

- [ ] **Step 6: Commit**

```sh
git add .github/workflows/release-vscode.yml vscode-extension/CONTRIBUTING.md
git commit -m "ci: release VS Code extension from tags"
```

### Task 3: Construir y publicar el VSIX de Visual Studio desde `visualstudio-v*`

**Files:**
- Create: `.github/workflows/release-visualstudio.yml`
- Create: `visualstudio-extension/marketplace/publishmanifest.json`
- Modify: `visualstudio-extension/CONTRIBUTING.md:225-260`

**Interfaces:**
- Consumes: tag `visualstudio-vX.Y.Z`, tres fuentes de versión, `visualstudio-extension/marketplace/overview.md`, VSIX de `build-vsix.ps1`, `VS_MARKETPLACE_TOKEN`.
- Produces: `GitReview.VS.vsix` publicado por `VsixPublisher.exe` y adjunto a un GitHub Release no-latest.

- [ ] **Step 1: Add the Marketplace publication manifest**

Crear `visualstudio-extension/marketplace/publishmanifest.json`:

```json
{
  "$schema": "http://json.schemastore.org/vsix-publish",
  "categories": ["source control", "other"],
  "identity": {
    "internalName": "git-review-workflow-vs"
  },
  "overview": "overview.md",
  "priceCategory": "free",
  "publisher": "EzeVillo",
  "private": false,
  "qna": true,
  "repo": "https://github.com/EzeVillo/git-review-workflow"
}
```

- [ ] **Step 2: Create the Windows workflow and preflight**

Crear `release-visualstudio.yml` con trigger `visualstudio-v*`, `contents: write` y un job `publish` en `windows-latest`. Antes de restaurar paquetes, usar PowerShell para comparar el sufijo del tag con `<Version>`, la versión de `<Identity>` y `<GitReviewClientVersion>`; abortar si cualquiera difiere. En un step separado, abortar con `VS_MARKETPLACE_TOKEN is not set.` si falta el secreto.

- [ ] **Step 3: Test, create the VSIX, and publish that exact output**

En `visualstudio-extension`, ejecutar:

```powershell
dotnet test GitReview.sln
./build-vsix.ps1
$vsix = 'src/GitReview.VS/bin/Release/net472/GitReview.VS.vsix'
if (-not (Test-Path -LiteralPath $vsix)) { throw "expected VSIX at $vsix" }
```

Resolver `VsixPublisher.exe` bajo `${env:VSINSTALLDIR}\VSSDK\VisualStudioIntegration\Tools\Bin`, comprobar que existe, y ejecutar:

```powershell
& $publisher publish `
  -payload (Resolve-Path -LiteralPath $vsix) `
  -publishManifest (Resolve-Path -LiteralPath 'marketplace/publishmanifest.json') `
  -personalAccessToken $env:PUBLISH_TOKEN
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

- [ ] **Step 4: Create the release with the same VSIX and its notes**

Extraer la sección de `visualstudio-extension/CHANGELOG.md` con el mismo awk de prefix match, aplicar fallback `See visualstudio-extension/CHANGELOG.md` y usar:

```powershell
gh release create $env:GITHUB_REF_NAME $vsix `
  --repo $env:GITHUB_REPOSITORY `
  --title "Visual Studio extension $env:VERSION" `
  --notes-file $notes `
  --latest=false
```

- [ ] **Step 5: Document the tag-based release**

En `visualstudio-extension/CONTRIBUTING.md`, documentar `git tag visualstudio-vX.Y.Z && git push origin visualstudio-vX.Y.Z` como el único disparador de publicación, el VSIX que el workflow compila y que `VS_MARKETPLACE_TOKEN` debe existir como secreto de Actions.

- [ ] **Step 6: Run focused tests**

Run: `./tests/run-docker.sh release-clients.bats release-notes.bats`

Expected: PASS; los cuatro workflows de release usan notas explícitas y los dos clientes tienen el contrato de publicación completo.

- [ ] **Step 7: Commit**

```sh
git add .github/workflows/release-visualstudio.yml \
  visualstudio-extension/marketplace/publishmanifest.json \
  visualstudio-extension/CONTRIBUTING.md
git commit -m "ci: release Visual Studio extension from tags"
```

### Task 4: Verificar la integración completa

**Files:**
- Modify: `tests/release-notes.bats:97-118`
- Modify: `tests/release-clients.bats`

**Interfaces:**
- Consumes: todos los workflows y manifiestos creados.
- Produces: evidencia reproducible de que el árbol mantiene las reglas de release y de clientes.

- [ ] **Step 1: Run the release and version gates**

Run: `./tests/run-docker.sh release-clients.bats release-notes.bats version-consistency.bats`

Expected: PASS.

- [ ] **Step 2: Run the relevant client checks**

Run: `node scripts/check-client-product-surface.mjs`

Expected: PASS.

Run: `npm ci && npm run test:unit` from `vscode-extension`.

Expected: PASS.

Run: `dotnet test GitReview.sln` from `visualstudio-extension`.

Expected: PASS.

- [ ] **Step 3: Validate workflow syntax without secrets**

Run: `npx --yes actionlint .github/workflows/release-vscode.yml .github/workflows/release-visualstudio.yml`

Expected: PASS; el linter no ejecuta publicación ni necesita el secreto.

- [ ] **Step 4: Inspect the final diff**

Run: `git diff --check HEAD~3..HEAD && git status --short`

Expected: no whitespace errors y árbol limpio después del commit final.

- [ ] **Step 5: Commit verification-only corrections if necessary**

```sh
git add tests/release-clients.bats tests/release-notes.bats \
  .github/workflows/release-vscode.yml .github/workflows/release-visualstudio.yml \
  visualstudio-extension/marketplace/publishmanifest.json \
  vscode-extension/CONTRIBUTING.md visualstudio-extension/CONTRIBUTING.md
git commit -m "test: verify client release automation"
```
