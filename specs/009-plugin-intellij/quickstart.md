# Quickstart de validación: 009-plugin-intellij

Guía para validar el plugin localmente. No es tutorial de usuario final.

## Prerrequisitos

1. **IntelliJ IDEA** en la línea pinneada — la que diga
   `intellij-plugin/gradle.properties`, única fuente del pin (2026.2 / branch
   platform **262** al planear).
2. **JDK** del platform (ver `intellij-plugin/gradle.properties`).
3. **git** en PATH.
4. **CLI** `git-review-workflow` ≥ `min_cli_version` del canónico
   (`contracts/client-product-surface.yaml`), o path al dispatcher vía setting.
5. Repo de prueba: `./tests/sandbox.sh` desde la raíz del monorepo (Linux/macOS
   o entorno que corra el sandbox; en Windows usar el sandbox ya materializado
   o WSL según CONTRIBUTING).

## Build y tests de dominio

```sh
cd intellij-plugin
./gradlew test          # Windows: gradlew.bat test — unit de dominio, sin IDE
./gradlew verifyPlugin  # cuando exista
```

Esperado: verde en parsers, situation, panel model, intent, housekeeping,
unquote, version, resolveCommand (Windows sh branch en tests con assume) y en
la tabla de paridad argv de las 27 acciones.

## Platform tests (headless, Linux)

```sh
./gradlew -p intellij-plugin platformTest
```

Levanta un IDE headless: wiring del tool window, activación perezosa
(SC-006: con el tool window cerrado no hay proceso de `git review`) y una
lectura de estado real. Es el mismo job que corre CI en el runner ubuntu; en
Windows/macOS la cobertura de IDE real es la matriz smoke de más abajo.

## Preview del panel (sin IDE)

```sh
./gradlew :runPanelPreview   # o main de preview/ documentado en README del módulo
```

Esperado: estados lado a lado (o seleccionables) alimentados por fixtures
porcelain reales: walk, step, whole, finish-*, cli-*, empty setup, etc.

## Run IDE con el plugin

Equivalente a F5 / Extension Development Host de la extensión VS Code.
Documentación de contrib: monorepo `CONTRIBUTING.md` → *The IntelliJ IDEA plugin*.

```sh
# desde intellij-plugin/
./gradlew runIde          # Git Bash / Linux / macOS
# PowerShell: .\gradlew.bat runIde  (no usar .\gradlew.bat desde MINGW64)
```

1. Abrir el sandbox como único root git (`File → Open` → `<sandbox>/work`).
2. Si la CLI no está en el PATH del sandbox IDE:
   **Settings → Tools → git review → Path to git-review** →
   path absoluto a `bin/git-review` del monorepo.
3. Tool window **git review** → no debe haber corrido CLI antes del open.
4. Con review walk activa (preparar vía terminal en el sandbox):
   - panel muestra posición y entry;
   - Open / Diff / Why / Next / Prev (panel y/o **Tools → git review**).
5. Abort/Save/Finish solo con confirmaciones correctas.
6. Sin CLI en PATH ni setting de path: situación cli-missing + copy npm.

La UI es Swing nativo (no clon HTML del webview); la paridad exigida es de
acciones/situaciones/argv, no de layout idéntico a VS Code.

## Matriz smoke multi-OS (release)

En cada SO (Windows, macOS, Linux):

| # | Caso | OK si |
|---|------|--------|
| 1 | `--version` vía plugin | min version gate |
| 2 | status con path acentuado en rango | lista + open |
| 3 | start `--offline` o local | review activa |
| 4 | open change de un archivo del rango apenas termina el start | diff correcto y no vacío (SC-010: no queda vacío por caché SCM) |
| 5 | dispatcher path POSIX en Windows | no ENOENT opaco |

## Anti-drift

```sh
# script a introducir en implementación, p.ej.:
node scripts/check-client-product-surface.mjs
```

Falla si extensión o plugin divergen del YAML canónico.

## Paridad argv

Con **Show CLI Log** del plugin: ejecutar Start / Finish / Clean y contrastar
líneas con la extensión VS Code en el mismo repo (o con la tabla de
[contracts/cli-invocation.md](./contracts/cli-invocation.md)).
