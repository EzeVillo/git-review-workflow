# Research: panel del plugin con la superficie de acciones del panel de VS Code

**Feature**: `010-panel-intellij-acciones` · **Fecha**: 2026-08-08

Todas las decisiones se toman contra el código real de los dos clientes, no
contra specs previas. Referencias verificadas en esta sesión:
`vscode-extension/src/views/panelHtml.ts`,
`vscode-extension/src/views/walkthroughViewProvider.ts`,
`vscode-extension/package.json` (`contributes.menus`),
`intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/**`,
`contracts/client-product-surface.yaml`,
`scripts/check-client-product-surface.mjs`.

## Hallazgo previo: la lista cerrada de controles del panel

`PANEL_MESSAGES` (walkthroughViewProvider.ts:10) es el conjunto **cerrado** de
lo que el webview puede accionar: 22 entradas. Descompuesto:

- **19 acciones del contrato** de las 27 → el panel las pinta.
- **8 acciones del contrato que el panel NO pinta**: `finishReview`,
  `saveReview`, `abortReview`, `previewEdits` viven en `view/title`;
  `goToEntry`, `forgetReview`, `previewEditsStat`, `showCliLog` viven sólo en
  la paleta de comandos.
- **3 controles que no son acciones del contrato**: `copyCliInstall`,
  `outOfRangeHelp`, `openSupport`.

Esto confirma el criterio de la spec: la matriz `surface:` del canónico no
alcanza como referencia (marca `both` para las cuatro de la paleta), y hay tres
controles del panel que la matriz no conoce.

---

## Decisión 1 — La disposición se modela como dato en el dominio puro

**Decisión**: agregar `domain/PanelLayout.kt` con una función pura
`panelLayout(model: PanelModel): PanelLayout` que devuelve la lista ordenada de
bloques y controles a dibujar, y `titleBarActions(model): List<Control>` para la
barra del tool window. El Swing pasa a ser un renderer genérico de esa
estructura, sin ningún `when (situation)` propio.

**Rationale**: el invariante rector de la spec exige verificar orden, grupo,
jerarquía, rótulo y habilitación (FR-001..FR-008, SC-001). Si esa información
sólo existe como secuencia de `body.add(...)` dentro de una clase que necesita
un `Project`, no hay forma de afirmarla en un test que corra en los tres
runners; quedaría como inspección visual. Como estructura de datos, cada
dimensión del invariante es una aserción de igualdad en JUnit puro, y el
`./gradlew test` que ya corre en ubuntu/macos/windows la protege.

Además respeta la separación que el plugin ya tiene y que
`checkDomainNoIntellij` verifica en cada build: el dominio no importa
`com.intellij`, así que el layout es testeable sin plataforma.

**Alternatives considered**:

- *Dejar el `when` en `ReviewPanel` y verificar con tests de UI headless*: exige
  el harness de plataforma (`platformTest`, que hoy es un stub que sólo
  `dependsOn(test)`) y sólo corre en el runner Linux; el invariante quedaría sin
  cobertura en macOS y Windows.
- *Describir el layout sólo en el YAML y que Swing lo lea en runtime*: acopla el
  arranque del plugin a un archivo de contrato que no viaja en el `.zip`, y
  convierte errores de compilación en errores de runtime.

---

## Decisión 2 — La paridad se verifica con un canónico y dos comprobaciones asimétricas

**Decisión**: extender `contracts/client-product-surface.yaml` con un bloque
`panel_layout:` (por situación: la secuencia de bloques y controles con rótulo,
grupo, énfasis y condición) y verificarlo así:

- **Lado IntelliJ — comparación estructural completa.** Un test de Kotlin
  (`PanelLayoutContractTest`) lee el YAML y compara, para cada situación
  fixture, la salida de `panelLayout(model)` control por control: identidad,
  rótulo, orden, grupo y énfasis. Cualquier divergencia falla el build.
- **Lado VS Code — comparación de pertenencia y rótulos.**
  `scripts/check-client-product-surface.mjs` verifica que cada rótulo del
  `panel_layout` exista literalmente en `panelHtml.ts`, que cada control tenga
  su mensaje en `PANEL_MESSAGES`, y —la dirección que más importa— que **ningún
  literal de botón de `panelHtml.ts` quede fuera del canónico**.

**Rationale**: el drift real que hay que atrapar es "alguien toca el panel de un
cliente y el otro se queda atrás". La comprobación de pertenencia lo detecta en
los tres casos frecuentes (agregar, renombrar o quitar un botón) sin
infraestructura nueva, y es exactamente el molde que el script ya usa para los
strings críticos. El orden del webview no se puede afirmar sin ejecutar su
script, y ese costo no se justifica: el YAML es el canónico, y el lado que
efectivamente se está construyendo en esta feature —el plugin— sí queda
verificado al 100%.

**Alternatives considered**:

- *Ejecutar `panelHtml()` en jsdom y extraer el DOM*: daría orden real del lado
  VS Code, pero agrega una dependencia de desarrollo a la extensión y un modo de
  ejecución nuevo para mantener. Se puede sumar después sin rehacer el canónico:
  el YAML ya tendría el orden esperado y sólo cambiaría quién lo compara.
- *Parsear `panelHtml.ts` con expresiones regulares para reconstruir el orden*:
  frágil ante cualquier refactor del render, y falla en silencio (deja de
  matchear y "pasa").
- *Snapshot de imágenes*: no verifica ninguna de las seis dimensiones del
  invariante y rompe con cada cambio de tema.

---

## Decisión 3 — El renderer se desacopla de `Project` para que el preview muestre el panel real

**Decisión**: partir la UI en dos: `ui/PanelRenderer.kt`, que recibe un
`PanelLayout` y un callback `(ControlId, Int?) -> Unit` y construye los
componentes Swing sin conocer `Project` ni `GitReviewService`; y
`ui/ReviewPanel.kt`, que suscribe el servicio, pide el layout y le pasa al
renderer un callback que despacha a las acciones existentes. `runPanelPreview`
usa el mismo renderer con un callback que no hace nada.

**Rationale**: hoy `runPanelPreview` imprime un volcado de texto del
`PanelModel` (PanelPreviewMain.kt:163) — sirve para leer el modelo, no para
mirar el panel. La extensión tiene el equivalente resuelto: `npm run preview`
renderiza el `panelHtml()` real. Con el renderer desacoplado, el preview del
plugin pasa a mostrar el panel de verdad y **es la herramienta con la que se
hace la comparación lado a lado** que pide SC-001, sin arrancar un IDE sandbox
por cada iteración.

**Riesgo identificado**: `JBColor` y los iconos de `AllIcons` fuera de una
aplicación IntelliJ pueden no resolver. Mitigación: el renderer toma los colores
y los iconos de un `PanelChrome` inyectado; el plugin le pasa la implementación
con `JBColor`/`JBUI`/`AllIcons` y el preview una basada en `UIManager` y en
glifos de texto. Si el riesgo no se materializa, la implementación colapsa a una
sola implementación — pero la inyección se decide ahora porque rehacerla después
toca todos los constructores.

**Alternatives considered**:

- *Dejar el preview como volcado de texto y validar sólo con `runIde`*: cada
  iteración cuesta un arranque de IDE sandbox, y la comparación lado a lado con
  el navegador se vuelve impracticable.
- *Renderer que dependa de `Project` y un `Project` falso en el preview*:
  construir un `Project` fuera de la plataforma no es viable sin el framework de
  test.

---

## Decisión 4 — Ancho variable real, en lugar del `width:220px` actual

**Decisión**: los textos se dibujan con componentes que envuelven contra el
ancho del viewport (área de texto no editable, sin borde ni fondo, o etiqueta
con recálculo de ancho), y el `JBScrollPane` declara que sigue el ancho del
viewport para que nunca aparezca scroll horizontal. Las filas de dos controles
usan un layout que los reparte al 50% y **se apilan conservando el orden**
cuando no entran (edge case de la spec).

**Rationale**: `ReviewPanel.wrapLabel` (ReviewPanel.kt:210) envuelve el texto en
HTML con `style='width:220px'`. Es un ancho fijo: en un tool window angosto el
texto se desborda y en uno ancho deja media pantalla vacía. Con controles reales
al lado, el problema deja de ser cosmético — un botón empujado fuera del área
visible es un control inalcanzable, que es exactamente lo que la feature viene a
eliminar. La extensión resuelve lo mismo con `.row button { flex: 1 }`
(panelHtml.ts:217).

**Alternatives considered**:

- *Mantener el HTML de la etiqueta y recalcular el ancho en cada resize*:
  funciona, pero repite el cálculo en cada bloque de texto y ya mostró ser fácil
  de olvidar (hoy hay un solo ancho para todo el panel).

---

## Decisión 5 — El ciclo de vida va como acciones de título del tool window

**Decisión**: registrar un grupo de acciones de título del tool window con
`Refresh`, `Finish`, `Save`, `Cancel` y `Preview edits`, en ese orden, con las
mismas condiciones que las cláusulas `when` de `contributes.menus.view/title`
(package.json): `Finish` sólo en `review`, no en solo lectura y no ocupado;
`Save` sólo en `review`; `Cancel` en `review` y `finish-conflict`;
`Preview edits` en `review` y `finish-conflict`. Y **quitar el botón `Refresh`
del cuerpo del panel** (ReviewPanel.kt:77), que hoy está en un lugar donde la
extensión no lo tiene.

**Rationale**: es el corolario 1 del invariante aplicado literalmente. Además el
propio panel de la extensión deja escrito el porqué de esa separación
(panelHtml.ts:958): la barra del cuerpo es identidad, el ciclo de vida es
chrome; duplicarlo adentro gastaba el ancho del sidebar.

**Nota de implementación**: `AnAction.update` debe apagar los controles según el
modelo y declararse en el hilo de fondo correspondiente; las acciones ya existen
(`FinishReviewAction`, `SaveReviewAction`, `AbortReviewAction`,
`PreviewEditsAction`, `RefreshAction`) y sólo se les agrega la condición de
disponibilidad, que hoy no tienen: en el menú están siempre habilitadas.

---

## Decisión 6 — Secciones plegables nativas, con el estado de apertura fuera del render

**Decisión**: el pie del estado vacío usa el componente plegable nativo de la
plataforma (separador con título y toggle), tres secciones, mismos títulos y
mismo orden que la extensión, plegadas por defecto. El estado de apertura vive
en el componente del panel (no en el modelo ni en el dominio) y sobrevive al
redibujado.

**Rationale**: la extensión tuvo exactamente este bug y lo dejó documentado
(panelHtml.ts:721): sin guardar el flag, expandir una sección se plegaba sola en
el primer refresh. El panel del plugin se redibuja entero en cada modelo
(`render()` hace `body.removeAll()`), así que el bug se reproduce igual. Y el
estado de apertura **no es estado del review** (FR-034): es del componente.

---

## Decisión 7 — Filas del inventario y de archivos: controles, no listas

**Decisión**: cada archivo del listado de whole y cada review del inventario se
dibujan como un control accionable de una línea, activable con **un clic**, no
como filas de una lista con doble clic. La marca de "último abierto" y los
badges van dentro de la fila.

**Rationale**: FR-006 y FR-018 fijan el gesto. En la extensión la fila **es** un
botón (`button(file.display, "openChange", "file-row", ...)`, panelHtml.ts:1169).
Una lista nativa con selección más doble clic sería lo idiomático de IDEA, pero
cambia el gesto: es justamente lo que el invariante prohíbe. Se conserva el
aspecto nativo (borde, hover y foco del tema) sin cambiar la interacción.

**Consecuencia a corregir**: `DiscardInventoryAction` (ReviewActions.kt:345) hoy
**pide el nombre de la rama escribiéndolo a mano** en un diálogo de entrada. Como
control de la fila eso no corresponde: el índice ya identifica la review, igual
que en la extensión, que postea el índice con el mensaje. La acción del menú
puede conservar su diálogo; el control del panel resuelve por índice.

---

## Decisión 8 — Los tiempos del esqueleto de carga viven en la UI

**Decisión**: replicar los dos umbrales de la extensión —el retardo antes de
mostrar el esqueleto y el techo de espera del *why*— en el componente del panel,
no en el dominio ni en el servicio.

**Rationale**: la extensión razona esto explícitamente (panelHtml.ts:1236): los
tiempos no son estado del review, sólo deciden *cuándo* se cambia de dibujo, y
eso sólo lo puede saber quien tiene la pantalla. Copiar la constante al servicio
la volvería estado compartido y rompería FR-034.

**Nota**: el servicio ya publica un modelo con `why = LOADING` antes de pedir el
*why* (GitReviewService.kt:95), así que la señal de las dos fases ya llega al
panel; falta la lógica de presentación.

---

## Decisión 9 — Iconos: los equivalentes de la plataforma

**Decisión**: los dos controles de navegación usan los iconos de flecha de la
plataforma con su nombre accesible ("Previous entry" / "Next entry"), y el
control de copiar el comando usa el icono de copiar de la plataforma. Ningún
icono se importa del webview.

**Rationale**: es la parte que el invariante sí libera ("con qué se dibuja"), y
FR-035 exige el nombre accesible porque son controles sin rótulo visible.

---

## Decisión 10 — Qué NO se toca en esta feature

- **La CLI, el porcelain y `PanelModel`**: la feature consume el modelo tal
  como está. Si un control necesitara un dato que el modelo no tiene, se
  revisaría — pero el repaso control por control de la tabla no encontró
  ninguno.
- **`platformTest`**: sigue siendo el stub que hoy es. Wirearlo es trabajo de la
  009 sin terminar, no de ésta; el layout queda cubierto por tests de dominio
  que corren en los tres sistemas operativos.
- **El menú `Tools → git review`**: no se recorta (FR-007 y la spec).
- **La extensión de VS Code**: no se modifica. El único archivo compartido que
  se toca es el canónico de contratos y su verificador.
