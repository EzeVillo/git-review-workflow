# Quickstart: validar el panel del plugin

**Feature**: `010-panel-intellij-acciones`

Guía de validación, no de implementación. El detalle de la disposición está en
[contracts/panel-layout.md](contracts/panel-layout.md) y los tipos en
[data-model.md](data-model.md).

## Prerrequisitos

- JDK 21 (el wrapper de Gradle vive en `jetbrains-plugin/`, no en la raíz; pin en `gradle.properties`).
- Node (para el verificador del canónico y para el preview de la extensión).
- Shell: en Git Bash / POSIX usá `./gradlew`; en PowerShell `.\gradlew.bat`.
  No mezclar: en MINGW64 `.\gradlew.bat` falla con `command not found`.

## 1. Verificación automática (lo que corre en CI)

Es el gate de la feature: si esto pasa, la paridad estructural está afirmada.

```bash
cd jetbrains-plugin && ./gradlew test
```

Cubre el layout completo:

- `PanelLayoutContractTest` — compara el layout de cada situación contra el
  canónico (identidad, rótulo, orden, agrupación, énfasis, habilitación).
- `PanelLayoutInvariantsTest` — los cinco invariantes de construcción del
  `Control`, y que ningún id excluido sea construible.
- `PanelLayout{Review,Finish,EmptyState,Whole,Diagnostics,Footer,Skeleton}Test`
  — una situación por archivo, agrupadas por historia.
- `TitleBarActionsTest` — las cinco acciones de la barra y sus condiciones.
- `ConfirmationContractTest` — `requiresConfirmation` contra el `confirms:` del
  canónico (FR-032).
- `PanelRendererTest` — el renderer no pierde ni reordena controles.

Son tests de dominio en JUnit puro, así que corren en ubuntu, macOS y Windows.

```bash
node scripts/check-client-product-surface.mjs
```

Verifica el otro lado con las seis comprobaciones de
`contracts/panel-layout.md` § Verificación: rótulo, id y **énfasis** de cada
control; que ningún botón del panel de la extensión quede fuera del canónico
—lo que más importa—; la adyacencia de los dos controles de cada fila; y el
orden de los controles dentro de cada situación. Verifica también que el bloque
nuevo no contradiga el `actions:` que ya estaba en el mismo archivo.

```bash
cd jetbrains-plugin && ./gradlew check
```

Incluye `checkDomainNoIntellij`: el layout es dominio puro y no puede importar
`com.intellij`. Si falla acá, el layout se contaminó y deja de ser testeable en
los tres sistemas operativos.

## 2. Comparación lado a lado (el criterio SC-001)

La prueba de que "está igual, sólo cambia el estilo". Dos ventanas, las mismas
nueve situaciones.

```bash
cd vscode-extension && npm run preview
```

Imprime una URL `file://` con los nueve estados del panel de la extensión, a
ancho de sidebar y con selector de tema. Es el panel real: usa `panelHtml()` sin
editar.

```bash
cd jetbrains-plugin && ./gradlew runPanelPreview
```

Levanta el mismo conjunto de estados renderizados por el `PanelRenderer` real
del plugin, sin arrancar un IDE.

**Qué mirar, en este orden**: que estén los mismos controles; que estén en el
mismo orden; que las filas agrupen igual; que el control principal sea el mismo;
que los rótulos coincidan palabra por palabra. Si algo no coincide, es un fallo
de la feature — no una diferencia de plataforma.

**Qué NO se puede afirmar acá**: los botones del preview no ejecutan nada (el
callback es un no-op), y los colores son los del tema del sistema, no los del
IDE del usuario. Para comportamiento, el punto 3.

## 3. Prueba manual en un IDE de verdad

```bash
./tests/sandbox.sh
```

Arma el repositorio de juguete y dice cómo entrar. Después:

```bash
git -C <sandbox>/work review start feature/checkout
```

Entra en modo walk (el sandbox commitea un walkthrough).

```bash
cd jetbrains-plugin && ./gradlew runIde
```

Abrí **solo** `<sandbox>/work` y, si hace falta, apuntá **Tools → git review →
Path to git-review** al `bin/git-review` de este checkout. El tool window `git
review` está a la derecha.

Recorrido mínimo que ejercita las historias P1 de la spec:

1. **Leer y avanzar** — abrir el archivo, abrir el diff, avanzar hasta el final
   y volver. En la primera y la última entrada, los controles del extremo tienen
   que verse deshabilitados, no desaparecer.
2. **Cerrar el ciclo** — `Save` desde la barra del tool window, comprobar que la
   review aparece en el inventario del estado vacío, y continuarla desde su
   propia fila (**Continue**), sin ningún selector de por medio.
3. **Arrancar desde cero** — `git -C <sandbox>/work config --unset
   reviewworkflow.base` y verificar que el panel pide la base como acción
   principal y que ningún texto manda al menú.
4. **Finish trabado** — provocar el conflicto y comprobar que el banner ofrece
   **Undo** y **Continue** y que la fila de navegación **no está**.
5. **Whole** — arrancar una review de una rama sin walkthrough y abrir el diff
   de un archivo con **un** clic.
6. **Confirmaciones** (FR-032) — accionar **Discard** desde una fila del
   inventario y **Clean** desde el aviso de finish pendiente: los dos tienen que
   pedir confirmación antes de ejecutar, con el mismo texto que cuando se los
   invoca desde `Tools → git review`. Cancelar el diálogo no debe dejar rastro.
7. **Anclaje** (FR-008) — mover el tool window a la izquierda o abajo, cerrar el
   IDE sandbox y volver a abrirlo: tiene que quedar donde el revisor lo dejó. El
   `anchor="right"` es el valor por defecto, no una imposición.

Para las situaciones que el sandbox no produce (`cli-missing`, `cli-outdated`),
apuntá la setting a un path inexistente o a una CLI vieja.

## 4. Regresión del menú

`Tools → git review` tiene que seguir teniendo las 27 acciones, incluidas las
cuatro que el panel **no** dibuja: `Go to Entry`, `Forget…`, `Preview Edits
(stat)` y `Show CLI Log`. Si alguna desapareció, la feature se pasó de alcance.

## 5. Accesibilidad

Con el foco en el panel, recorrerlo entero con Tab: todos los controles tienen
que ser alcanzables, con foco visible, y en el orden en que se leen (SC-010).
Los dos controles de navegación no tienen rótulo: verificá que anuncien
`Previous entry` y `Next entry`.

## Señales de que algo salió mal

| Síntoma | Causa probable |
|---|---|
| Un control aparece en el plugin y no en la extensión | Se pintó una acción de la paleta; ver `panel_excluded` en el canónico |
| `PanelLayoutContractTest` falla y el panel "se ve bien" | El canónico y el layout se separaron: uno de los dos miente. La referencia es el panel de la extensión |
| Scroll horizontal en el tool window | El ancho fijo del texto volvió (research §4) |
| Una sección del pie se pliega sola al refrescar | El estado de apertura se guardó en el modelo en vez de en el componente (research §6) |
| El preview arranca pero el panel no dibuja colores | `JBColor` fuera de la plataforma; el renderer tiene que tomarlos del chrome inyectado (research §3) |
| El panel se quedó sin `Refresh` | T009a (barra del tool window) tiene que ir **antes** de T010, que retira el `header()` del cuerpo |
| Una acción destructiva del panel ejecuta sin preguntar | El despachador no pasó por `requiresConfirmation`; `ConfirmationContractTest` debería haberlo atrapado |
