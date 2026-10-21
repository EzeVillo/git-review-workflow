# Reauditoría de flujos de equipo y usabilidad — 19 de octubre de 2026

Seguimiento posterior del mismo día: los cinco defectos concretos de este informe
se corrigieron en [correcciones-auditoria-2026-10-19.md](correcciones-auditoria-2026-10-19.md).
Este documento conserva la evidencia y el dictamen de la ejecución original.

## Dictamen

Los recorridos ejecutados conservan los comentarios privados, las referencias
históricas y la separación entre revisiones. Los cuatro adaptadores superan sus
pruebas de comportamiento compartido. Esto todavía no acredita una aceptación
interactiva completa dentro de IntelliJ y Visual Studio.

Encontré cinco problemas adicionales: una advertencia falsa con CRLF limpio,
un banner de cierre que promete comentarios staged cuando no lo están, dos
defectos del compositor WPF y contextos indistinguibles al elegir una revisión
anterior. Para alguien nuevo, las mayores dificultades son entender cuándo se
comparte el feedback y resolver la respuesta del autor.

Esta ejecución conserva la auditoría anterior y sus correcciones preexistentes.
No modifiqué implementación, tests permanentes, ramas, commits ni configuración
de este repositorio. Añadí este informe y harnesses/artefactos locales ignorados
en `demo/auditoria-20261019/`. Los pushes de prueba se hicieron a remotos bare
locales descartables.

## Versiones comparadas

Se verificaron los tags del remoto con `git ls-remote --tags origin`. Las
versiones candidatas son las del working tree, incluidos sus archivos nuevos.

| Pieza | Último tag publicado | Candidato |
|---|---|---|
| CLI | v0.9.0 | 0.10.0 |
| VS Code | vscode-v0.4.0 | 0.5.0 |
| JetBrains | jetbrains-v0.4.0 | 0.5.0 |
| Visual Studio | visualstudio-v0.3.0 | 0.4.0 |
| TUI | tui-v0.1.0 | 0.2.0 |

Los clientes nuevos requieren CLI 0.10.0. La compatibilidad esperada con una CLI
anterior consiste en detectarla y ofrecer actualizarla; los comentarios no se
pueden ejecutar con aquella versión. Los tests de versión y del contrato cubren
ese límite.

## Hallazgos reproducidos

### P2 — Un checkout limpio con CRLF se marca como código sin guardar

Referencia: `bin/git-review-lib.sh:1158`.

Con `core.autocrlf=true`, comenzar una revisión y capturar una línea de un
archivo de texto sin modificar produce `unversioned 1`. `git diff --quiet`
confirma que el working tree coincide con el índice del PR materializado. La
comparación usa `hash-object --no-filters`: compara los CRLF del checkout con
los LF del objeto Git.

Al abrir el histórico, los clientes muestran «The captured lines included
unsaved changes…», aunque no se editó ni dejó sin guardar el archivo. Además,
la captura evita las validaciones de rango reservadas a ubicaciones
reproducibles. No observé pérdida de comentarios, pero la advertencia deja de
servir para distinguir cambios reales de la conversión habitual de Windows.

Corregir el reconocimiento de un checkout limpio sin debilitar la detección de
ediciones ni asumir que cualquier filtro de contenido conserva las coordenadas.

Evidencia: `extra-flows.sh`, `extra-flows.log` y el repositorio preservado en
`extra-fixtures/crlf`, dentro del directorio local de artefactos.

### P2 — Finish afirma que el feedback está staged y todavía requiere agregarlo

Referencias: `contracts/client-product-surface.yaml:447` y
`vscode-extension/src/views/panelHtml.ts:1375`; la copy se comparte con los demás
clientes.

Recorrido reproducido: revisión con un comentario Shared y sin correcciones de
código → Finish → `review-fixes/feature`. La CLI informa `finish pending` y
`comments-delivery delivered`, pero `git status --porcelain` muestra
`?? .review/`: `.review/comments.md` sigue sin seguimiento ni stage. Es el
comportamiento de entrega previsto por el diseño.

El banner dice «Your edits are staged and ready to commit…». Una persona que
haga un commit de lo staged siguiendo esa indicación no incluirá el feedback.
El problema también existe al combinar código staged con Shared sin stage.
Hace falta distinguir «código preparado» de «comentarios guardados en un archivo
que todavía tenés que agregar al commit». Ese próximo paso ocurre fuera del
panel y cumple la regla de copy del repositorio.

Evidencia: `comment-only-finish.log` y `comment-only-result.log`.

### P2 — El compositor de Visual Studio ignora el tema del host

Referencia: `visualstudio-extension/src/GitReview.VS/ToolWindows/CommentsComposer.cs:22`.

Se renderizó la clase de producción con `GitReviewDialogs.Chrome =
PanelChrome.DefaultDark`. La ventana conserva `Background=#FFFFFFFF` y
`Foreground=#FF000000`, frente al fondo esperado `#FF1E1E1E`. El explorador de
comentarios, renderizado en las mismas condiciones, sí usa el tema oscuro.

El compositor obtiene `Chrome` para algunos controles, pero no aplica la paleta
a la ventana y al formulario. Los botones también quedan mucho más pequeños
que los del explorador. La verificación WPF existente no cubre este formulario.

Evidencia: `native-preview.log`, `vs-composer-dark.png` y
`vs-browser-dark.png`. El harness referencia el proyecto de producción; las
imágenes son renders WPF, no capturas de una sesión completa dentro del IDE.

### P2 — El formulario WPF pierde el espacio de escritura al reducirse

Referencias: `CommentsComposer.cs:18`, `:26` y `:42`.

El compositor permite una ventana de 420 × 360. Renderizando su contenido a
420 × 320 —espacio compatible con el área cliente de esa ventana— con selección
de código y aviso de buffer modificado, la vista previa y las filas superiores
consumen el alto disponible. El área visible para escribir queda recortada.
Guardar y Cancelar siguen visibles, pero el cuerpo del comentario deja de ser
usable visualmente.

El render general sin selección sí ofrece espacio para escribir en ese tamaño.
El caso faltante es la combinación de alcance, fragmento y aviso. Ajustar el
reparto de alto/scroll y verificar el tamaño mínimo con esas filas presentes.

Evidencia: `vs-composer-selection-small.png`, comparado con
`vs-composer-small.png`; harness `native-preview/`.

### P2 — El selector muestra dos revisiones distintas con el mismo nombre

Referencias: `vscode-extension/src/commands/comments.ts:101`,
`visualstudio-extension/src/GitReview.VS/ToolWindows/CommentActions.cs:36` y las
construcciones equivalentes de `CommentsActions.kt` y `tui/internal/ui/comments.go`.

Se conservaron dos contextos explícitamente separados para la misma rama y se
abrió otra pasada. La CLI devuelve correctamente `ambiguous` con dos tokens
distintos, pero ambas filas tienen la etiqueta `feature`. Los cuatro clientes
usan sólo esa etiqueta en sus opciones: se ofrecen «New context», «feature» y
«feature», sin descripción ni vista previa para distinguir las revisiones.

Elegir el contexto correcto importa precisamente porque el linaje no permite
deducirlo. Mostrar dos opciones idénticas obliga a adivinar. Mantener la
identidad opaca interna y ofrecer información legible que permita reconocer la
conversación antes de seleccionarla.

Evidencia ejecutada: `ambiguous-labels.sh`, `ambiguous-labels.log`, exit 0. La
construcción del selector se verificó en el código de los cuatro clientes; no
se afirma una captura interactiva de cada selector dentro de su IDE.

## Historias de equipo comprobadas

Se reejecutó la matriz existente de whole/step/walk por fast-forward, merge
commit y squash, con clones separados de autor, Alice, Bob y Carol. Incluye
capturar Local y Shared, pausar/continuar, modificar código, extraer correcciones,
commitear el feedback en otra rama, integrar la respuesta del autor, abrir el
histórico y revisar ramas nacidas antes y después del merge.

También se ejercitaron revisores concurrentes con conflicto add/add, rebase y
force-push, una base local atrasada, el avance de la base durante la revisión,
buffers obsoletos, fallos de guardado, entrega parcial, undo, documentos vacíos,
rutas especiales e historia ausente. Son aserciones sobre Git y los documentos,
no sólo sobre el texto que imprime la CLI.

La extensión ejecutó sus tres recorridos de equipo dentro de Electron. C#,
Kotlin y Go ejecutaron las tres estrategias mediante sus invocadores reales.
Estas pruebas de Kotlin y C# no equivalen a accionar todos los controles dentro
de un IDE real.

La TUI se recompiló y ejecutó en un PTY de 120 × 40, con vigilancia activa:
Local → Shared → Local por teclado, counts 2/1, Finish, respuesta del autor,
merge, otro proceso sobre una rama nueva con base local atrasada, Shared y
Finish. Se verificó que la entrega nueva no arrastre la conversación anterior.

Añadí exploraciones independientes: actualizar con main una rama creada antes
del merge, y borrar/recrear el mismo nombre de rama después de integrar el PR,
con las tres estrategias. Fast-forward y merge commit resuelven contexto fresco.
Después de squash, reutilizar el nombre devuelve `ambiguous` y exige elegir
«New context». La continuación explícita y la rama nacida después del squash
funcionan. Es una protección coherente con el diseño de linaje incompatible,
no una pérdida de datos; conviene explicarla mejor al usuario.

## Usabilidad para alguien nuevo

**Lo que ayuda:** editar y ejecutar el PR en el editor habitual; capturar una
selección con su ubicación visible; separar explícitamente prosa privada y
compartida; conservar el histórico original; leer cuerpo y detalle sin abrir
Markdown; mantener etiquetas y orden consistentes entre clientes. Las guardas
evitan que un formulario antiguo escriba sobre otra sesión.

**La dificultad principal es el recorrido completo del feedback.** «Local» y
«Shared» no explican por sí solos quién puede leerlos, cuándo salen del gitdir
ni qué hay que commitear. Guardar un comentario, terminar la revisión e integrar
el feedback son tres momentos diferentes que requieren una explicación corta y
contextual. El banner de cierre merece prioridad por su afirmación incorrecta.

**Recibir la respuesta del autor es demasiado manual.** Las propias pruebas de
equipo resuelven `source-conflict` copiando `.review/comments.md` al documento
Shared del gitdir. La política de preservar ambas versiones es buena, pero el
panel no ofrece un recorrido claro para compararlas y elegir cómo reconciliar.
En VS Code, `panelHtml.ts:1735` muestra el código técnico del diagnóstico como
resumen plegable. Para un usuario nuevo, «source-conflict» y «context» explican
el mecanismo antes que la decisión que necesita tomar.

**Los controles del documento exigen exploración.** Ver comentarios y abrir
Markdown son acciones distintas; el explorador se alcanza desde una acción
llamada «View changes», incluso si sólo querés leer comentarios generales. Los
tooltips ayudan, pero la acción principal de leer feedback debería reconocerse
sin probar iconos. Renumerar tiene menor frecuencia y merece menor peso visual.

**La TUI exige más conocimiento.** El formulario expone ruta, lado y
coordenadas, con varios pasos de foco. El flujo funciona por teclado, pero su
carga de aprendizaje supera la de seleccionar código en un IDE. Lo consideraría
una interfaz para quien ya conoce el recorrido de la herramienta.

Prioridad sugerida: corregir el banner y CRLF; completar tema y tamaño mínimo
del compositor; explicar destinos y publicación; guiar la reconciliación del
feedback; mejorar descubribilidad y etiquetas. Son conclusiones de inspección
y recorridos técnicos, no resultados de una prueba con usuarios nuevos.

La revisión del webview también tomó como referencia las
[Web Interface Guidelines](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md),
especialmente etiquetas, feedback de errores, foco y manejo de contenido largo.

## Evidencia de esta ejecución

Los logs y scripts están en `demo/auditoria-20261019/`, ignorado por Git.

| Comprobación | Resultado |
|---|---|
| CLI completa, 1.388 casos | Exit 0: 1.383 aprobados y cinco omitidos en el contenedor; omisiones comprobadas en los complementos siguientes |
| Packaging y permisos del índice | 11 aprobados; smoke npm completado en otro contenedor |
| npm, archivo ilegible y stdin con PTY | Cuatro tests focalizados aprobados como usuario sin privilegios |
| Instaladores PowerShell | 13 casos de sus runners ejecutados en Windows; aprobados, con PATH de prueba aislado |
| VS Code | Compilación y tipos aprobados; 505 unitarias, un pending preexistente; 108 integraciones aprobadas |
| Contrato y assets | Checker de superficie, 41 tests del gate y checker del logo aprobados |
| JetBrains | `test`, `checkDomainNoIntellij`, `buildPlugin`, configuración y estructura aprobados |
| Visual Studio | 409 tests de dominio y 68 de host aprobados; VSIX/MSBuild/net472 aprobado |
| WPF existente | `--verify`: 30 fixtures aprobados; los renders adicionales detectan los defectos descritos |
| TUI | Formato, vet, tests de los cinco paquetes, detector de carreras y build aprobados; PTY aprobado |
| ShellCheck y whitespace | Sin diagnósticos; `git diff --check` aprobado |

Los intentos fallidos se conservan y no cuentan como verificaciones aprobadas:
montaje sin permisos ejecutables, copia inicial sin metadata Git para packaging,
CRLF del wrapper Gradle, dos builds de .NET que compartían obj y una caída del
renderer de Electron con la memoria compartida por defecto. Se repitieron las
comprobaciones afectadas con los requisitos correspondientes; Electron terminó
con exit 0 usando `--shm-size=1g`.

Para la CLI, el resultado definitivo es `cli-final.log` junto a
`cli-final.exit`. El wrapper serial anterior también falló al retornar de los
tests, por haber sido ajustado mientras se ejecutaba; no se usa su código de
salida como evidencia de aprobación. El runner final quedó fijo y termina
directamente con `exec bats`.

El primer harness Go también terminó con un error de shell después de sus
tests; `go-checks.log` y su exit 0 son la repetición completa válida. La primera
exploración adicional se detuvo al exigir contexto fresco automáticamente tras
reutilizar una rama después de squash. Esa expectativa era más fuerte que el
diseño conservador vigente: `squash-explicit-context.log` verifica la
continuación elegida explícitamente. Ese exit 1 no se cuenta como prueba
aprobada ni como pérdida de datos del producto.

## Límites

No se instalaron candidatos en los IDEs personales ni se publicaron paquetes.
IntelliJ y Visual Studio todavía necesitan aceptación interactiva completa con
selecciones, comparadores, buffers, cierre de ventanas y cambios de rama reales
dentro de cada IDE. El build, los tests de host y los renders no sustituyen esa
evidencia. Tampoco se reejecutó aquí toda la matriz de macOS y Windows ni el
Plugin Verifier multi-IDE.

El resultado acredita los recorridos enumerados y permite reproducir problemas
concretos. No afirma que todos los casos posibles estén cubiertos ni que los
cuatro clientes tengan idéntica usabilidad.
