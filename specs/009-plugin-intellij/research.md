# Research: 009-plugin-intellij

**Date**: 2026-08-08  
**Fuente de verdad del comportamiento**: código de `vscode-extension/` + `bin/`,  
no specs `002`–`008`.

## Decisión 1 — Ubicación del código

**Decision**: monorepo en `intellij-plugin/` (hermano de `vscode-extension/`).

**Rationale**: el contrato CLI↔cliente se versiona junto; los cambios de
porcelain y de textos anti-drift tocan un solo PR; mismo patrón que ya usa el
repo para la extensión.

**Alternatives considered**:
- Repo aparte → desacopla releases pero multiplica drift y PRs cruzados.
- Submódulo git → fricción operativa sin beneficio claro.

## Decisión 2 — Stack del plugin

**Decision**: Kotlin + IntelliJ Platform Gradle Plugin **2.x** (pin al latest
estable al implementar; docs actuales: **2.18.1**), target **IntelliJ IDEA
2026.2** → branch platform **262** (la numeración JetBrains es
`20YY.N → (YY)(N)`: 2025.2 → 252, 2026.1 → 261, 2026.2 → 262; el `261` que
circulaba en el primer borrador de esta feature era de 2026.1). El par
línea/JDK se **verifica contra la tabla oficial de build ranges el día de
implementación** (T001) y se estampa en un solo lugar,
`intellij-plugin/gradle.properties`; `plugin.xml` toma de ahí
`since-build`/`until-build`.

**Rationale**: el usuario pidió “la última versión” de IDE y solo IDEA.
Kotlin es el idioma idiomático de plugins JetBrains modernos; Gradle Plugin
2.x es el sucesor soportado del 1.x.

**Alternatives considered**:
- Java only → más verboso; sin ganancia de mantenibilidad.
- IDEA 2025.3 / JDK 21 → más conservador, pero no es “última”.
- Multi-IDE (WebStorm…) → fuera de alcance de testing del v1.

**Nota operativa**: el toolchain local/CI debe traer el JDK que exija esa
línea de platform. Si al implementar 2026.2 aún no está ampliamente
disponible en runners, se pinnea la última línea **estable publicada** en ese
momento y se documenta el since-build exacto en `plugin.xml` — sin bajar el
producto a “cualquier IDE viejo”.

## Decisión 3 — UI del panel: Swing nativo

**Decision**: `ToolWindow` + UI Swing (Kotlin UI DSL / componentes JB),
**sin** JCEF para el panel principal.

**Rationale**: theming `JBColor`/`UIManager`, a11y e HiDPI gratis; no depende
de `JBCefApp.isSupported()` (remotos / algunos Linux); el modelo
`PanelModel` ya separa proyección de pintura en la extensión.

**Alternatives considered**:
- JCEF + markup de `panelHtml.ts` → reusa CSS pero pelea con theming nativo,
  fallback cuando no hay CEF, y un tool window que “no se siente IntelliJ”.
- Compose for Desktop en IDE → prematuro / no estándar en tool windows de
  plugins de plataforma.

**Harness de preview**: app standalone Swing (o `main` de preview en el
módulo) que alimenta el mismo `PanelModel` con fixtures parseadas por el
parser real — equivalente mantenible de `npm run preview`.

## Decisión 4 — Arquitectura en capas

**Decision**: tres capas estrictas:

1. **domain / cli** (puro JVM): parsers porcelain, situation, panel model,
   intent, housekeeping args, unquote, version, timeouts de clase,
   resolveCommand — **cero** imports de IntelliJ Platform.
2. **host / platform**: `GeneralCommandLine` + `CapturingProcessHandler`,
   `GitRepositoryManager` / change listeners, `DiffManager`, settings
   `PersistentStateComponent`, `AnAction`, diálogos.
3. **ui**: tool window Swing que solo pinta `PanelModel` y emite intents
   tipados hacia el host.

**Rationale**: la extensión ya demostró que ~2.5k LOC sin vscode son el
activo real; portar esa capa a Kotlin con JUnit da paridad verificada, no
“confiada”. Mantiene testeable el 80 % del valor sin arrancar el IDE.

**Alternatives considered**:
- Traducir todo mezclado con APIs de IntelliJ → imposible unit-testear parsers.
- Compartir TypeScript vía Graal → complejidad absurda para este tamaño.

## Decisión 5 — Invocación de procesos

**Decision**: `GeneralCommandLine` + `CapturingProcessHandler` (o
`OSProcessHandler` con capturadores), charset **`StandardCharsets.UTF_8`**
forzado en stdout/stderr; `GitExecutableManager.getInstance().getExecutable(...)`
(o API equivalente vigente) para localizar `git`; env de red:
`GIT_TERMINAL_PROMPT=0` + askpass no-op (script/binario embebido o
`echo`/comando vacío multiplataforma documentado); timeouts propios por
clase (15s / 120s / 300s) con destroy del process tree best-effort.

**Windows sin extensión nativa**: mismo workaround que `invoke.ts`:
comando `sh`, args `[dispatcherPath, verb, …]`.

**Rationale**: replica las trampas ya pagadas en Node (charset Windows,
dispatcher POSIX, hang de credenciales).

**Alternatives considered**:
- `Runtime.exec` crudo → peor escaping y control.
- Terminal embebido del IDE para todo → no sirve para parsear porcelain.

## Decisión 6 — Repo root y señales

**Decision**: roots solo desde Git4Idea (`GitRepositoryManager`);
`pickSoleTarget` idéntico (0 o ≥2 → sin target). Listeners:
`GitRepositoryChangeListener` / eventos de root set change → refresh
coalescido. **Prohibido** leer estado de review desde el modelo VCS del IDE.

**Rationale**: espejo de Decisión 7 de la extensión (vscode.git solo root +
“algo cambió”), con API más rica — la disciplina es aún más importante.

## Decisión 7 — Diffs

**Decision**: inventario de cambios del rango vía `git diff` /
`git diff-tree` con `-z --name-status` (y `--no-renames` en rango HEAD como
la extensión), parseado en domain (`NameStatus`). Presentación:
`DiffManager` + `DiffContentFactory` + `SimpleDiffRequest` / chain multi-file
para open-all. Lados before/after y fallbacks A/D/M como `openEntry.ts`.

**Rationale**: no reutilizar “change list” del IDE post-start (caché stale).

## Decisión 8 — Activación perezosa

**Decision**: `ToolWindowFactory` no corre CLI en `isApplicable` / create
eager. Contenido del tool window y primer `status --porcelain` solo al
mostrar el window o al invocar una acción. Actions pueden registrarse lazy
(`ActionManager`).

**Rationale**: FR-017 / SC-006; fácil de violar en IntelliJ.

## Decisión 9 — Anti-drift multi-cliente

**Decision**: archivo canónico versionado en repo, en la **raíz**:

```text
contracts/client-product-surface.yaml
```

Decidido: raíz (no `docs/contracts/`, que es superficie publicada en Pages) y
YAML (no JSON: admite comentarios, y el consumidor de build-time es un script
del repo). Contiene: `min_cli_version`,
comandos npm install/update, URLs de docs, matriz situación→acciones
habilitadas, y strings críticos de empty/cli states.

- Tests en **ambos** clientes (o un check CI shell/node/kotlin) fallan si el
  cliente embebe valores distintos.
- `panelModel` / textos de panel leen de ese archivo en build time
  (codegen ligero) **o** tests snapshot comparan constantes generadas.

**Rationale**: el riesgo #1 del segundo producto es drift de copy y de
matriz de acciones. Resolverlo en la spec/plan, no “después”.

**Alternatives considered**:
- Solo disciplina humana “actualizar los dos” → ya falla con dos README;
  con dos UIs falla más.
- Un solo paquete npm compartido → no ayuda a Kotlin.

## Decisión 10 — Estrategia de port de tests

**Decision**: traducir `vscode-extension/test/unit/*.spec.ts` de la capa
pura a JUnit 5 en `intellij-plugin/.../domain` **caso por caso** (mismos
fixtures de strings porcelain). No reescribir specs de integración VS Code;
añadir tests de platform acotados (tool window model wiring, process
invoke con git-review real en sandbox) donde la infra lo permita.

**Rationale**: los unit tests **son** la especificación ejecutable del
contrato cliente.

## Decisión 11 — CI

**Decision**: job nuevo en GitHub Actions: JDK platform + Gradle
`check` / `verifyPlugin` / tests unitarios del módulo en **ubuntu, macos y
windows**, más **platform tests headless acotados en el runner Linux**
(decisión de alcance del v1: wiring del tool window, activación perezosa de
SC-006 y una lectura de estado real; los tres SO no pagan el costo del IDE
headless, sí el smoke manual del quickstart). Mantener jobs existentes de CLI
+ extensión. Documentar que el repo pasa a toolchain tri-lingüe
(sh + TS + Kotlin).

## Decisión 12 — Distribución

**Decision**: construir `.zip`/plugin artifact con Gradle; `plugin.xml` con
id `com.ezevillo.gitreview` (o el id final alineado al publisher);
firma y publish Marketplace como tarea operativa con token — no bloquea el
desarrollo local. README del plugin + mención en README raíz (EN+ES).

## Decisión 13 — Orden de implementación (mantenible, no “big bang ciego”)

Aunque el **release** es paridad total, el **orden de merge** es por
capas:

1. Scaffold Gradle + domain (parsers, situation, panel model) + JUnit.
2. Invoke + state machine + tool window read-only.
3. Open entry/diff/why + navigate.
4. Start/continue/finish/abort/save.
5. Housekeeping, compare, preview, walkthrough, anti-drift, packaging.

Cada capa deja el plugin usable en un subconjunto de historias; el v1 no
se etiqueta “completo” hasta SC-001–SC-010.

## Open items resueltos por default (sin preguntar)

| Item | Default |
|------|---------|
| Familia de IDEs | Solo IntelliJ IDEA |
| Versión IDE | Última estable (2026.2 / branch 262 al planear; se reverifica en T001) |
| Panel | Swing |
| Repo | `intellij-plugin/` |
| JCEF | No en v1 |
| Multi-root picker | No; error de un solo cwd |
| i18n UI | Inglés como la extensión |
