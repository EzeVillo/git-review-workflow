# Implementation Plan: Panel del plugin de IntelliJ con la superficie de acciones del panel de VS Code

**Branch**: `010-panel-intellij-acciones` | **Date**: 2026-08-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/010-panel-intellij-acciones/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

El panel del plugin tiene que ofrecer los mismos controles que el panel de la
extensión de VS Code, en el mismo orden, con los mismos rótulos, agrupados
igual y accionables con el mismo gesto — cambiando sólo con qué se dibujan.

El enfoque técnico que hace eso verificable en vez de opinable: **modelar la
disposición como dato en el dominio puro**. Una función
`panelLayout(model: PanelModel): PanelLayout` devuelve la secuencia ordenada de
bloques y controles; el Swing pasa a ser un renderer genérico de esa estructura
y deja de decidir nada; el canónico `contracts/client-product-surface.yaml` gana
un bloque `panel_layout:` que un test de Kotlin compara al 100% del lado
IntelliJ, y que del lado VS Code el verificador de Node comprueba extrayendo los
controles de `panelHtml.ts` por la forma de la llamada — rótulo, id, énfasis,
adyacencia dentro de la fila y orden dentro de la situación (contrato completo
en `contracts/panel-layout.md` § Verificación). Así cinco de las seis
dimensiones del invariante rector (existencia, orden, grupo, jerarquía, rótulo)
son aserciones automáticas en los tres sistemas operativos de CI; la sexta —las
condiciones de aparición— se verifica entera del lado del plugin y queda
enumerada en `panel_unverified` del lado de la extensión, para que su ausencia
sea una decisión escrita y no un olvido.

El resto es consecuencia: las acciones ya existen las 27 y no se agrega ninguna;
el ciclo de vida se mueve del cuerpo del panel a la barra del tool window; el
preview de Gradle pasa de volcar texto a renderizar el panel real, que es la
herramienta con la que se hace la comparación lado a lado.

## Technical Context

**Language/Version**: Kotlin 2.3.20 sobre JDK 25 (toolchain fijado en
`intellij-plugin/build.gradle.kts`; platform 2026.2)

**Primary Dependencies**: IntelliJ Platform Gradle Plugin 2.18.1, plataforma
IntelliJ IDEA (versión pinneada en `intellij-plugin/gradle.properties`, única
fuente de since-build), `Git4Idea`, Swing. **Sin dependencias nuevas de
runtime**: nada nuevo viaja en el `.zip` del plugin. La única incorporación es
de test — `testImplementation("org.yaml:snakeyaml")` — porque
`PanelLayoutContractTest` tiene que leer el canónico YAML desde Kotlin y el
plugin hoy sólo trae `junit-jupiter`. Se prefiere la dependencia a un parser
propio: el bloque `panel_layout:` usa flow style anidado, y un lector a mano
sería código de test sin tests. (El verificador de Node parsea a mano porque
sólo mira claves sueltas, no estructura.)

**Storage**: ninguno. La feature no persiste nada: todo el estado sigue viniendo
del porcelain de la CLI. El único estado nuevo es de componente (secciones
plegadas, temporizadores del esqueleto) y muere con la ventana.

**Testing**: JUnit 5 puro para dominio y renderer (`./gradlew test`, corre en
ubuntu/macOS/Windows en CI); `node scripts/check-client-product-surface.mjs`
para el canónico multi-cliente; `./gradlew runPanelPreview` y `runIde` para la
validación manual. `platformTest` sigue siendo el stub que ya era.

**Target Platform**: IntelliJ IDEA en Windows, macOS y Linux.

**Project Type**: plugin de escritorio dentro de un monorepo multi-cliente; la
CLI POSIX es la única fuente de verdad y no se toca.

**Performance Goals**: el panel se redibuja completo en cada modelo, como hoy.
Señal de carga antes de los 200 ms cuando la respuesta no es inmediata (SC-008),
con los mismos umbrales que la extensión (120 ms para el esqueleto, 800 ms de
techo para el *why*).

**Constraints**: el dominio no puede importar `com.intellij`
(`checkDomainNoIntellij` falla el build); sin scroll horizontal en el tool
window a ningún ancho; los controles de ícono necesitan nombre accesible; ningún
control puede ejecutar algo que la situación no permita.

**Scale/Scope**: 8 `Situation` que producen 9 pantallas (`no-review` se desdobla
en *setup* y *con base*), y 3 modos dentro de `review` / `finish-conflict`. **21
controles distintos en el cuerpo** del panel + 5 en la barra de título (26
`ControlId` en total: `refresh` es sólo de barra), y 4 acciones explícitamente
excluidas. Alrededor de 300 archivos en el caso grande del listado de whole.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` está **sin completar**: es la plantilla con
los placeholders (`[PRINCIPLE_1_NAME]`, etc.). No hay principios ratificados que
evaluar, así que no hay gate constitucional que pueda pasar o fallar. Se deja
constancia en lugar de inventar principios.

En su lugar, los gates que este repositorio sí tiene escritos y son vinculantes
(`CLAUDE.md`), evaluados contra el diseño:

| Gate del proyecto | Estado | Cómo lo cumple |
|---|---|---|
| La CLI es la única fuente de verdad; los clientes no derivan estado | **PASA** | El layout es una proyección pura de `PanelModel`; no consulta git ni config (FR-034) |
| El canónico anti-drift multi-cliente gobierna la superficie de producto | **PASA** | La feature lo extiende con `panel_layout:` y lo verifica de los dos lados |
| Dominio del plugin sin `com.intellij` | **PASA** | `PanelLayout` va en `domain/`; `checkDomainNoIntellij` lo verifica |
| Tests con asserts fuertes, sin falsos positivos | **PASA** | Igualdad estructural sobre el layout, no `contains` sobre texto renderizado |
| Paridad de producto, no de píxeles | **PASA** | Es literalmente el objeto de la feature; el invariante rector acota qué sí y qué no |
| Los documentos de trabajo van en español | **PASA** | Los cinco artefactos de esta feature |
| Los dos README se actualizan juntos | **N/A** | La feature no cambia la superficie de la CLI. El README del plugin sí se toca (ver estructura) |
| La landing sólo se toca si cambian sus cuatro duplicados | **N/A** | Ninguno cambia |

**Re-evaluación post-Phase 1**: sin cambios de gate. El diseño no introdujo
ningún estado persistido, ninguna invocación nueva a la CLI, ninguna dependencia
de runtime ni ninguna excepción a los gates. Sí agrega una dependencia **de
test** (snakeyaml) y un source set de fixtures; las dos están en *Complexity
Tracking* abajo.

## Project Structure

### Documentation (this feature)

```text
specs/010-panel-intellij-acciones/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── panel-layout.md  # Phase 1 output — disposición por situación
├── checklists/
│   └── requirements.md  # de /speckit-specify
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
contracts/
└── client-product-surface.yaml        # + panel_layout / title_actions / panel_excluded / panel_unverified

scripts/
└── check-client-product-surface.mjs   # + las 6 verificaciones vs panelHtml.ts
                                       #   y la coherencia con el bloque actions:

intellij-plugin/
├── build.gradle.kts                   # + source set `fixtures` + dependencia de test (snakeyaml)
├── src/main/kotlin/com/ezevillo/gitreview/
│   ├── domain/
│   │   ├── PanelLayout.kt             # NUEVO — Block, Control, ControlId, Emphasis,
│   │   │                              #   panelLayout(), titleBarActions(), requiresConfirmation()
│   │   └── PanelModel.kt              # sin cambios (se consume tal cual)
│   ├── ui/
│   │   ├── PanelRenderer.kt           # NUEVO — PanelLayout -> Swing, sin Project
│   │   ├── PanelChrome.kt             # NUEVO — colores e iconos inyectables (plugin vs preview)
│   │   ├── PanelActionDispatcher.kt   # NUEVO — ControlId (+ índice) -> acciones existentes
│   │   ├── ReviewPanel.kt             # REESCRITO — suscribe, pide layout, delega; sin when(situation)
│   │   ├── GitReviewToolWindowFactory.kt  # + acciones de título
│   │   └── actions/ReviewActions.kt   # + condiciones de disponibilidad (update); discard por índice
│   └── resources/META-INF/plugin.xml  # + grupo de acciones del tool window
├── src/test/kotlin/com/ezevillo/gitreview/
│   ├── domain/PanelLayoutContractTest.kt    # NUEVO — compara contra el canónico
│   ├── domain/PanelLayoutInvariantsTest.kt  # NUEVO — los invariantes de construcción
│   ├── domain/PanelLayoutReviewTest.kt      # NUEVO — walk y step (una situación por archivo,
│   ├── domain/PanelLayoutFinishTest.kt      #   agrupados por historia para que cada una
│   ├── domain/PanelLayoutEmptyStateTest.kt  #   sea entregable por separado)
│   ├── domain/PanelLayoutWholeTest.kt       # NUEVO
│   ├── domain/PanelLayoutDiagnosticsTest.kt # NUEVO
│   ├── domain/PanelLayoutFooterTest.kt      # NUEVO
│   ├── domain/PanelLayoutSkeletonTest.kt    # NUEVO
│   ├── domain/TitleBarActionsTest.kt        # NUEVO — la barra del tool window
│   ├── domain/ConfirmationContractTest.kt   # NUEVO — requiresConfirmation vs canónico (FR-032)
│   └── ui/PanelRendererTest.kt              # NUEVO — el renderer no pierde ni reordena
├── fixtures/com/ezevillo/gitreview/fixtures/
│   └── PanelFixtures.kt               # NUEVO — un PanelModel por situación, compartido test+preview
├── preview/com/ezevillo/gitreview/preview/
│   └── PanelPreviewMain.kt            # REESCRITO — renderiza con PanelRenderer, no volcado de texto
├── README.md                          # la superficie que describe cambia
└── CONTRIBUTING.md (raíz)             # la sección del plugin: cómo se valida la paridad
```

**Structure Decision**: se conserva la separación que la 009 ya estableció —
`domain/` puro y verificado por `checkDomainNoIntellij`, `host/` para la CLI,
`ui/` para Swing— y la feature cae casi entera del lado del dominio: la decisión
de qué se dibuja y en qué orden **baja** de `ui/ReviewPanel.kt` a
`domain/PanelLayout.kt`. `ui/` queda con tres piezas de responsabilidad única
(renderer, chrome, despachador) y un `ReviewPanel` que sólo conecta el servicio
con el renderer. No se crean módulos nuevos. Sí se agrega **un** source set,
`fixtures/`, siguiendo el molde con el que la 009 ya creó `preview/`: los
modelos de ejemplo los necesitan `test` y `preview` a la vez, y sin él habría
que duplicarlos o hacer que uno dependa de la salida del otro (que es peor:
acopla el preview a los tests).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No hay violaciones de gate. Se registra igual la única decisión que agrega una
capa, porque agregar indirección merece justificarse aunque nadie la prohíba:

| Decisión | Por qué se necesita | Alternativa más simple, y por qué se rechazó |
|---|---|---|
| `PanelLayout` como capa intermedia entre `PanelModel` y Swing | El invariante rector exige verificar orden, agrupación, énfasis, rótulo y habilitación. Sin una estructura de datos, esas cinco dimensiones sólo existen como efectos de `body.add(...)` dentro de una clase que necesita un `Project` | Dejar el `when (situation)` en `ReviewPanel` y cubrirlo con tests de UI headless: exigiría el harness de plataforma (hoy un stub) y sólo correría en el runner Linux, dejando el invariante sin cobertura en macOS y Windows — que es donde más se usa el IDE |
| `PanelChrome` inyectable (colores e iconos) | El preview corre fuera de la plataforma y `JBColor`/`AllIcons` pueden no resolver ahí; sin preview no hay comparación lado a lado barata, que es el criterio de aceptación central | Que el renderer use `JBColor` directo y el preview arranque un IDE sandbox: cada iteración de ajuste pasaría a costar un arranque de IDE |
| Source set `fixtures` | Los `PanelModel` de ejemplo los consumen `test` (11 archivos) y `preview` a la vez; son la entrada de toda la verificación | Duplicarlos en los dos lados (se separan al primer cambio de porcelain) o hacer que `preview` dependa de la salida de `test` (acopla la herramienta de comparación a la suite) |
| `testImplementation(snakeyaml)` | `PanelLayoutContractTest` lee el canónico YAML desde Kotlin; es de test, no viaja en el `.zip` | Un parser propio: sería código de test sin tests, sobre flow style anidado. Descartado también mantener una copia JSON del canónico: dos archivos que se separan |
