# Contract: Superficie de producto multi-cliente (anti-drift)

## Problema

Dos UIs (VS Code webview + IntelliJ Swing) y dos codebases de strings
consumen el mismo producto. Sin fuente canónica, un fix de copy o de versión
mínima en un cliente deja al otro mintiendo.

## Fuente canónica

Archivo versionado en el monorepo (crear en implementación):

```text
contracts/client-product-surface.yaml
```

(esquema abajo). **Norma**: ningún cliente hardcodea estos valores sin leer
el canónico en build-time o sin test que falle si divergen.

### Esquema

**Los valores de abajo son ilustrativos del *shape*, no copy definitivo.**
T006 rellena cada string leyéndolo del código actual de la extensión, que es
la fuente del bootstrap: un valor tipeado a ojo acá y otro en `panelHtml.ts`
es exactamente el drift que este archivo existe para evitar. Los strings que
sí están verificados contra el código al 2026-08-08 van marcados `# verificado`.

```yaml
schema_version: 1
min_cli_version: "0.4.0"          # verificado: src/cli/version.ts
npm_install: "npm install -g git-review-workflow"
npm_update: "npm install -g git-review-workflow@latest"
docs_readme_url: "https://github.com/EzeVillo/git-review-workflow#readme"
support:
  star_url: "https://github.com/EzeVillo/git-review-workflow"
strings:
  # verificado: panelHtml.ts:911
  cli_missing_title: "The git-review CLI ({min} or newer) was not found."
  # verificado: panelHtml.ts:917 — ojo el "installed", que el borrador comía
  cli_outdated_title: "The installed git-review CLI is older than {min}."
  # verificado: commands/setBase.ts — degradación de la acción global sin candidatas
  no_base_candidates: "No branches to pick a base from were found."
  reload_or_wait: "Reload the window after installing, or wait — the panel checks again every few seconds."
  other_install_options: "Other install options"
  multi_root_error: >-
    Open a single-folder workspace that is a git repository. git review uses
    one root (like the CLI cwd); multi-root is not supported.
  # … empty states críticos listados en tasks al generar el YAML inicial
situations:
  - cli-missing
  - cli-outdated
  - no-review
  - finish-pending
  - review
  - finish-conflict
  - out-of-range
  - error
# matriz acción → situaciones. NO es un mirror: es la fuente normativa.
# Las 27 acciones de contributes.commands, cada una con las situaciones donde
# está habilitada y en qué superficie (panel | action | both), más el flag de
# busy/readonly. plugin-surface.md y el package.json de la extensión se
# verifican contra esto en CI.
actions: { … }
```

### Autoridad

La matriz situación×acción vive en tres documentos por legibilidad
(§ Acciones de `spec.md`, la tabla de `plugin-surface.md` y este YAML). Solo
**el YAML es normativo**: es el que lee el check de CI. Las otras dos son
resúmenes; ante divergencia se corrigen ellas, no el YAML.

## Obligaciones

1. **Al cambiar** `min_cli_version`, npm commands, o strings listados: un solo
   PR actualiza el YAML **y** regenera/verifica ambos clientes.
2. **CI**: job (puede ser script Node o Python del repo) que:
   - parsea el YAML;
   - grepea/constantes generadas en `vscode-extension` y `jetbrains-plugin`;
   - falla si hay divergencia.
3. **README**: la regla “DOS README” se extiende: cambios de superficie de
   cliente documentados en README EN+ES y, si aplica, mención del plugin.

## Qué no vive en el canónico

- Layout pixel-perfect / LAF
- IDs de acciones de cada plataforma
- Implementación de DiffManager vs vscode.diff

## Bootstrap

La primera implementación del YAML se rellena **desde el código actual de la
extensión** (no desde specs viejas), con un test de la extensión que ya pasa
contra esos strings.
