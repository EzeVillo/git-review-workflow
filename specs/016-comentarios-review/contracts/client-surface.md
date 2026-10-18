# Contrato: Comments en los cuatro clientes

Diseño de FR-025..FR-035, FR-043 y FR-046..FR-055. Cada cliente consume
[cli-porcelain.md](cli-porcelain.md); ninguno parsea Markdown, deduce recuentos
del filesystem ni interpreta el texto de stdout para decidir el resultado.

## Superficie canónica

Agregar dos acciones reales a `contracts/client-product-surface.yaml`:

| Id | Label | Disponibilidad | Efecto |
|----|-------|----------------|--------|
| `addComment` | Add comment | Review/compare activos; general también en finish-conflict | Compositor con destino explícito por captura |
| `saveComments` | Save comments | Compare activo, sin mutación concurrente | Conservar ambos documentos localmente sin salir |

Ambas se registran en las superficies equivalentes de producto de cada cliente.
El total pasa de **27 a 29** en la matriz, manifests/menús y gates. La clasificación
TUI incorpora dos nativas: 24 nativas + 4 delegadas + 1 excluida = 29.
No hay `not_in` nuevo ni se modifica la exclusión vigente de `openAllChanges`.

`comments_rows` declara Local y Shared y cinco controles propios de documento:

| Id de control | Label | Disponible | Icono si se usa énfasis icon |
|---------------|-------|------------|------------------------------|
| `initComments` | Create | Documento ausente, sesión activa | Texto |
| `openComments` | Open | Documento presente | `file` |
| `renumberComments` | Renumber | Presente y contorno interpretable | Texto |
| `openCommentDiff` | Diff | Presente; selector temporal de entradas | `diff` |
| `prepareSharedComments` | Prepare | Sólo Shared con entrega pendiente de review completada | Texto |

Son controles de fila: no van a `contributes.commands`, Tools ni `.vsct`.
Open/Renumber no modifican el otro documento. Diff pide `entries` y muestra
un selector temporal; no agrega lista permanente de comentarios al panel.
Prepare no se ofrece a resultados de compare ni inicia una sesión.

El bloque Comments vive en el cuerpo, después del contenido principal y antes
del inventario/pie existente. Dentro de review nunca se agrega `tools_section`.
Cuando no hay documentos sólo se ofrece Add comment; después de crear el
primero, el bloque muestra las dos filas, incluso la ausente con Create.
Fuera de sesión se muestran contextos conservados de la CLI con sus dos filas;
no se elige uno por recencia ni se ofrece capturar comentarios nuevos.

Add comment y Create no confirman. Cada formulario arranca sin destino elegido;
el usuario debe elegir Local o Shared antes de guardar. No se restaura el último
destino, aunque uno ya exista. Guardar sesión/documentos no reclasifica entradas.
Abort/forget conservan sus confirmaciones destructivas y explican qué prosa
no conservada se perderá. La elección de contexto ambiguo es una selección,
no una confirmación: se declara como diálogo de entrada junto al compositor,
respetando el gate que prohíbe modales de confirmación fuera de la puerta única.

Al nacer el bloque Comments desde un compositor, revelar el panel sin foco por
la puerta canónica. Incorporar `addComment` a `reveals` con condición explícita
`comments_block_born` y extender sus gates para verificar id y condición.
Crear el segundo documento, renumerar o guardar nuevamente no lo revela.
No se notifica un éxito que ya expresa el panel; una entrega fallida conserva
su diagnóstico y dice que el código se extrajo pero Shared no se preparó.
No abrir Markdown automáticamente al terminar ni añadir botón para agentes.

Labels, tooltips y fallbacks viven en `UserCopy` de cada cliente y en el
canónico cuando se comparten. Tooltips explican el efecto sobre su documento,
sin argv. STALE es el aviso único existente; detalles técnicos quedan a un clic.

## Captura, guardado y concurrencia

1. Capturar editor, selección/caret y procedencia del lado **antes** de mover
   foco. Normalizar selecciones invertidas; convertir líneas a 1-based
   inclusivas y excluir la última si la selección termina en su columna cero.
2. Obtener token de sesión/cursor y refs reales de la CLI. Si el buffer es sucio
   o no tiene versión, conservar ubicación con `unversioned`; nunca guardarlo
   como código para poder comentar ni afirmar que sus bytes son los del PR.
3. Abrir compositor multilínea con ubicación visible, destino sin elegir,
   Guardar y Cancelar. Cancelar no invoca `add` ni crea documentos.
4. Al confirmar, guardar únicamente el Markdown del destino si está abierto
   y sucio. Si guardar falla, devuelve falso, se cancela o sigue sucio, detener
   la operación. Volver a leer estado/bytes después de ese guardado: una
   revisión de bytes tomada antes ya sería obsoleta. Mantener el token original
   de sesión/cursor y rechazar si cambió mientras el formulario estaba abierto.
5. Dentro del lock de mutación del cliente invocar `add` con guardas y texto
   por stdin UTF-8. La CLI repite la validación bajo su propio lock de contexto.
   No agregar cuerpo a logs ni construir un comando de shell con el texto.
6. Refrescar antes de mostrar diagnósticos/resultados. El guardado manual de
   uno de los documentos sólo solicita refresco; la CLI recalcula recuentos.

Renumber, Diff y Prepare guardan sólo el documento afectado y reobtienen la
revisión de bytes antes de escoger/operar; Save comments guarda los dos de
esa comparación y no otro archivo. Antes de `save/finish/abort/forget` de una
sesión, gestionar los buffers de ambos documentos de esa sesión para no dejar
una pestaña sucia que los recree tras el descarte. Cancelar ese guardado detiene
la mutación; no ejecutar Save All ni modificar buffers de código por comments.

El `StateToken` actual (rama, tip, situación) no basta: un cambio de step
mantiene tip. Comments usa el token de captura emitido por la CLI más documento
y revisión. Un picker viejo no puede resolver por número visible repetido.

## Histórico y límites de captura por host

Los adaptadores de diff actuales leen HEAD/working tree o commit del paso.
Se añade un camino que consume exclusivamente la receta histórica resuelta.
Archivo actual ausente no impide abrir blobs antiguos. Un fallo al leer blob
no se convierte en texto vacío; vacío por adición/borrado está declarado en
la receta. La consulta nunca cambia de rama ni inicia una review.

| Cliente | Captura actual/general | Lado anterior | Presentación histórica |
|---------|------------------------|---------------|------------------------|
| VS Code | Editor/caret/selection | Diffs propios con asociación transitoria URI→refs/ruta/lado | `vscode.diff` sobre versiones Git inmutables |
| JetBrains | Editor/selección | DocumentContent de diffs propios con contexto asociado | `SimpleDiffRequest` con contenidos de blobs |
| Visual Studio | Vista/selección de texto | Vistas base/head de comparaciones propias identificables | Servicio nativo de diferencias sobre blobs consultados |
| TUI | General o archivo/contexto seleccionado, líneas explícitas | Lado explícito del contexto ofrecido | `comments diff` calculado, mostrado con pager/terminal |

Los IDE no adivinan el lado de un visor opaco o una coordenada inline no
mapeable: explican el límite y permiten actual/general. La TUI no captura
selección de otro proceso. Los contextos de diffs propios son transitorios,
no una base de datos histórica ni un parser de URI interna del host.

## Mapa de integración

| Cliente | Puntos existentes y ampliaciones |
|---------|----------------------------------|
| VS Code | `src/commands/comments.ts` nuevo; `draftActions.ts` como referencia, sin heredar el guardado que ignora `save=false`; modelos/guardas en `src/review/`; `draftWatch.ts` y `extension.ts` para rutas y eventos; `panelHtml.ts` y compositor webview con textarea; `openEntry.ts` para variante histórica |
| JetBrains | Dominio: registros/modelo/argv/copy; `host/EditorFiles.kt` como puerta VFS fuera del EDT y coordinación de guardado en EDT; `DraftWatcher.kt` y `GitReviewService.kt` para refresco; `ui/PanelActionDispatcher.kt`, `ReviewActions.kt`, `UiMessages` y `plugin.xml`; `diff/OpenEntryActions.kt` para blobs históricos |
| Visual Studio | Domain: registros/layout/argv/copy; Host: invocación stdin y vigilancia; `ToolWindows/PanelHost.cs` y `ActionDispatcher` para callbacks; `Vsix/VsHostActions.cs` para captura y save estricto; compositor WPF multilínea; `DocumentSaveListener` y `PanelController`; servicio de diferencias |
| TUI | `internal/domain/` registros/actions/layout/copy/keymap; `host/invoke.go` stdin, `watchset.go` rutas, `open.go` histórico; `ui/comments.go` nuevo overlay textarea, `program.go` interceptación del formulario y `render.go` filas; goldens |

VS Code requiere compositor con textarea, no InputBox de una línea. JetBrains
resuelve/refresca VFS fuera del EDT por su puerta única y vuelve al EDT para
`saveDocument` del documento exacto; comprueba `isDocumentUnsaved` después y
asegura persistencia antes de pasar el path al proceso según las APIs de la
plataforma mínima soportada. Visual Studio valida el HRESULT de
`SaveDocuments` y retorna resultado verificable desde `SavePathAsync` al host;
los adaptadores de editor quedan en el VSIX, con compatibilidad net472 y sin
introducir otro archivo con `#if`. Su compositor usa `AcceptsReturn`.

TUI reutiliza textarea de Bubbles, sin dependencia nueva. Enter agrega línea,
Ctrl+Enter confirma y Esc cancela; el compositor consume esas teclas antes del
keymap global. La acción sólo confirma si hay destino elegido y texto. Si una
terminal no distingue Ctrl+Enter, el botón Save navegable por Tab y Enter da
el mismo recorrido. Se declaran bindings y foco en el canónico y sus tests.

## Refresco y gates

Agregar `comments status --porcelain` al refresh después de comprobar versión.
Registrar sólo directorios/rutas reportados en los watchers existentes;
incluir guardados exactos de documentos. No leer Markdown desde un watcher.
Respetar el interruptor vigente de vigilancia TUI y probar explícitamente 0/1;
el refresh manual garantiza corrección. Este cambio no redefine su default.

Ampliar las listas cerradas de invocación en specs de VS Code
(`002-extension-vscode/contracts/cli-invocation.md` y sus ampliaciones de
`006-superficie-panel-completa`), `009-plugin-intellij` y
`015-cliente-tui/contracts/cli-invocation.md`, además de la tabla de argv
de Visual Studio y sus tests. El contrato presente es la ampliación vigente
de comments y debe quedar enlazado desde esas listas al implementar.

Gates obligatorios: 29 acciones en ambas direcciones, cinco controles fuera de
menús, orden/layout del bloque, dos filas sin precedencia, labels/tooltips,
condición de revelado, puerta única de confirmación, selección de destino sin
valor retenido, editor sucio/cancelación, stdin sin cuerpo en logs, picker
obsoleto, refs históricas, watchers, teclado/mouse y goldens de ambos tamaños.
No regenerar goldens masivamente sin revisar cada cambio de layout.

La primera CLI con estos argv debe publicarse antes de elevar cada piso en
el canónico y constante local. Mientras tanto no se hace pasar `0.9.0` por
una CLI que tiene comments. Se validan las cinco superficies en el mismo
alcance de entrega, con los tags y changelogs independientes actuales.
