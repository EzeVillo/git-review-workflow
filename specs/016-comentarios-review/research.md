# Investigación: comentarios portables de una review

Fecha: 2026-10-18. La primera parte conserva la evidencia reunida al especificar;
la segunda cierra las decisiones técnicas de Phase 0 de `speckit-plan`.
Ver [el registro de decisiones](decisiones-pendientes.md) y [plan.md](plan.md).

## Método y fuentes

Se revisaron las reglas del repositorio, la skill local de GitHub
[`speckit-specify`](../../.claude/skills/speckit-specify/SKILL.md), la taxonomía
de `speckit-clarify`, la plantilla y los puntos de código de prosa, custodia,
cierre, porcelain y clientes.

No hay overrides, presets ni extensiones de plantilla; se usa
[spec-template.md](../../.specify/templates/spec-template.md) conservando sus
encabezados y completando en español. No hay `extensions.yml` ni hooks de
`specify`. La numeración es secuencial: corresponde `016-comentarios-review`.
La constitución conserva placeholders de ejemplo, sin reglas adicionales vigentes.

## Hallazgos

### 1. El borrador del walkthrough aporta custodia, no un contenedor genérico

[walk_draft_path](../../bin/git-review-lib.sh#L863) usa el gitdir de la copia de
trabajo; tiene contraparte archivada. `walk_use_draft`, `walk_review_draft_src`
y `walk_read` resuelven nombre y precedencia.

**Consecuencia**: Adoptar prosa de trabajo fuera del working tree, con identidad
y custodia propias. D02 y D08 ya fijan creación en review/compare y continuidad
entre pasadas. D19 y D20 completan identidad y descarte cuando ya había contenido.

### 2. El significado de build es diferente

[walkthrough:1599](../../bin/git-review-verbs/walkthrough#L1599) ordena según los
números anteriores y renumera. Los comentarios conservan el orden físico acordado.

**Consecuencia**: Reutilizar por nombre cambiaría el orden elegido. La acción
de comentarios repara números y no hereda la prioridad del walkthrough.

### 3. Paths únicos y cobertura del PR no sirven como identidad de comentarios

[walk_parse](../../bin/git-review-lib.sh#L1097) emite número/path; `walk_body`
busca por path. El build [rechaza duplicados](../../bin/git-review-verbs/walkthrough#L1414).
El update calcula archivos conservados, añadidos y quitados según el rango.

**Consecuencia**: Admitir varios bloques por path, entradas generales y
conservarlas aunque el archivo deje de cambiar. No reutilizar ese reconciliador.
Tampoco separar Markdown por cualquier `##` sin respetar código cercado.

### 4. La normalización de paths tiene puertas normativas

[changed_paths](../../bin/git-review-lib.sh#L464),
[walk_normalize](../../bin/git-review-lib.sh#L513) y el trim de los lectores
resuelven los bytes invisibles enumerados por `AGENTS.md`.

**Consecuencia**: Toda comparación nueva de rutas escritas contra git respeta
esas puertas. Pertenecer al diff no es un requisito para conservar un comentario.
Un path se representa como dato, sin ejecutarlo ni usarlo sin validar para
construir nombres internos que puedan escapar de su directorio.

### 5. HEAD no identifica el código observado

[start:422](../../bin/git-review-verbs/start#L422) mueve HEAD al límite inferior
con `reset --soft` y registra el tip en metadata. Step reconstruye cada paso
desde commits y cursor. Además puede haber ediciones del usuario en el working tree.

**Consecuencia**: Capturar extremos reales del paso/rango y lado del diff.
D17 confirma sólo referencias resueltas por entrada y D18 excluye instantáneas
de código. No prometer reconstrucción histórica de cambios sin commit ni
inventar una versión para entradas manuales que carecen de referencias.

### 6. finish y save incluyen todos los archivos del working tree

[finish:537](../../bin/git-review-verbs/finish#L537) hace `git add -A`; el camino
step y `save` también capturan el árbol. Walkthrough tiene una guarda para no
crear su sidecar de autor dentro de `review/*`.

**Consecuencia**: Escribir `.review/` durante una review incorpora ese archivo
a las ediciones de código, y en step las banca por commit. Con D05/D06 se propone
mantener también el compartido en preparación fuera del working tree, cargado
desde el documento que ya trae el PR. Ambos siguen disponibles al navegar.
D16 ya confirma escritura del compartido tras completar el cierre, verificando
que no se sustituyan cambios concurrentes del destino.

### 7. Terminar sin ediciones ya está implementado

[finish:530](../../bin/git-review-verbs/finish#L530) evita un commit de sesión
innecesario y llega al destino, incluida una rama `review-fixes` sin cambios.
[Compare](../../bin/git-review-verbs/finish#L341), en cambio, es de sólo lectura
y se cierra mediante su cancelación/limpieza existente.

**Consecuencia**: Una review sólo con comentarios no necesita fabricar un diff.
D21 incorpora Guardar comments localmente en compare. Ese resultado independiente
de la sesión debe sobrevivir a la salida, sin habilitar `finish`, guardar código
ni cerrar implícitamente. El descarte elimina sólo lo posterior no conservado.

### 8. save/continue protegen la prosa contra colisiones

[save:92](../../bin/git-review-verbs/save#L92) verifica custodia antes de mover
y registra si esa review archivó el borrador.
[continue:99](../../bin/git-review-verbs/continue#L99) restaura sólo el propio y
rechaza sustituir uno nuevo existente.

**Consecuencia**: Copiar sólo el `mv` pierde esas garantías. Cubrir colisiones
y documentos escritos durante la pausa, además del recorrido feliz.

### 9. clean y forget tienen políticas diferentes

[clean:196](../../bin/git-review-verbs/clean#L196) conserva borradores.
[forget:190](../../bin/git-review-verbs/forget#L190) elimina el archivado que
pertenece a la review guardada descartada. `abort` elimina ramas y ediciones;
no tiene hoy una política propia de comentarios.

**Consecuencia**: D09 descarta el trabajo al abortar o eliminar la guardada,
pero `save`/`continue` conserva ambos documentos. D20 confirma restaurar las
notas anteriores; D21 conserva el resultado local guardado expresamente antes
de descartar. El compartido previo versionado nunca se borra por ello.

### 10. Los IDE abren prosa y la CLI la interpreta

[openDraft](../../vscode-extension/src/commands/draftActions.ts#L72) abre la ruta
reportada y [saveDraftDocument](../../vscode-extension/src/commands/draftActions.ts#L115)
guarda sólo el documento afectado. `walkthroughRowActions.ts` copia punteros
para agentes. JetBrains usa `PanelActionDispatcher.kt` y la puerta VFS
`host/EditorFiles.kt`; Visual Studio despacha desde su host del panel.

**Consecuencia**: Pasar la ubicación y la intención a la CLI; evitar cuatro
escritores/parsers de Markdown. Si falla guardar, detener la operación para no
renumerar una versión vieja del disco.

### 11. Editar prosa privada necesita su propia señal de refresco

[draftWatch.ts](../../vscode-extension/src/review/draftWatch.ts) explica que
editar el gitdir no cambia refs ni índice. Obtiene rutas de porcelain y distingue
vigilancia de directorios y señal de guardado. Los otros IDE tienen sus watchers;
la TUI tiene vigilancia opcional con reglas propias.

**Consecuencia**: La CLI reporta presencia/recuento. Integrar los documentos al
refresco existente, sin prometer vigilancia continua donde está desactivada.

### 12. La TUI abre el editor configurado, sin selección de otro proceso

[open.go](../../tui/internal/host/open.go) construye esa apertura y explica si
el editor falta. Dominio y UI mantienen la separación de argv y ejecución.

**Consecuencia**: Reutilizar ese mecanismo para Markdown o composición del texto.
La ubicación viene del contexto o de la CLI; no prometer capturar selecciones
de editores externos. D10 elige cuadro de entrada en los IDE y delega CLI;
se propone argumento/stdin y editor configurado como entrada interactiva.

### 13. Declarar la nueva superficie y publicar en orden

[client-product-surface.yaml](../../contracts/client-product-surface.yaml)
distingue acciones, controles de fila, confirmaciones, revelado y pisos por
cliente. Sus 27 acciones no incluyen controles que sólo tienen sentido en su fila.

**Consecuencia**: Clasificar cada control y extender contratos, porcelain y
listas cerradas de invocación. Una acción real modifica también el canónico y
los gates; no se oculta como control de fila. Publicar primero la CLI requerida
antes de subir el piso de los clientes. El bloque de comentarios dentro de una
review no se agrega como pie de herramientas de autoría, prohibido actualmente.

### 14. Distintos heads del mismo PR necesitan referencias distintas

[openEntry.ts](../../vscode-extension/src/commands/openEntry.ts) abre en whole/walk
el lado anterior desde `HEAD` y el posterior desde el working tree; en step
resuelve los blobs del commit. JetBrains
[OpenEntryActions.kt](../../jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/diff/OpenEntryActions.kt)
distingue blobs y archivos editables. Visual Studio
[RangeChanges.cs](../../visualstudio-extension/src/GitReview.VS/Diff/RangeChanges.cs)
también consulta el rango contra `HEAD`; su host abre comparaciones con el
servicio de diferencias. La TUI delega las diferencias al entorno de terminal.

**Consecuencia**: Esos caminos muestran la review activa, pero un path antiguo
puede llevar a otro head. D17 confirma guardar base/head resueltos por entrada
y calcular el diff al consultar. No se guarda un parche ni código adjunto.
Un comentario B1/H1 y otro B2/H2 siguen siendo distintos al avanzar a H3.
Los clientes conservan su presentación nativa y la CLI resuelve los extremos.
Se retira Ctrl+click: no se agrega proveedor de enlaces ni protocolo de URI.

### 15. Un archivo con referencias no transporta los objetos de git

[resolve_lower_bound / fold_lower](../../bin/git-review-lib.sh#L409) puede
producir un árbol y después un commit sintético. `save` mantiene alcanzables
su tip y límite inferior mediante los padres de su commit guardado. Un buffer
o cambio sin commit puede no estar contenido en ningún commit del PR.

**Consecuencia**: D18 excluye transporte y retención nueva de código. Se consulta
lo ya disponible y se diagnostican objetos faltantes. Si el archivo actual fue
borrado pero existe en un antepasado registrado, sigue consultable; ausencia en
HEAD no significa ausencia en la historia. Límites sintéticos y contenido sin
commit no deben prometerse como disponibles en otro clon por anotar un SHA.
Abrir el diff calculado no implica iniciar otra review histórica, fuera de alcance.

### 16. Un único archivo versionado puede heredarse en otro PR

El archivo compartido es contenido normal de la rama y no hay una API de
proveedor en el modelo. Al integrar un PR, su `.review/comments.md` puede
quedar en la base y luego aparecer en la rama de otro PR.

**Consecuencia**: D19 confirma empezar de cero en otro PR y continuar sólo en
nuevas pasadas del mismo. El plan debe resolver contexto/inicialización sin una
API de proveedor, usando el rango completo y sin inferir pertenencia desde un
delta aislado o un nombre de rama que puede reutilizarse. Si la identidad no se
puede inferir con certeza, la inicialización explícita evita mezclar documentos.

### 17. Dos documentos independientes no se reconcilian como dos versiones

D06 permite usar Local para dudas privadas y Compartido para observaciones al
autor, o darles otros usos. El compartido en preparación parte del archivo del
PR; no parte de Local. Ambos requieren custodia al pausar y retomar.

**Consecuencia**: D15 confirma copiar/pegar bloques manualmente y no agregar
importación de archivos completos ni controles dedicados. El control de
concurrencia de D16 debe comparar el documento de destino contra
su contenido inicial, no contra Local ni sólo contra su recuento de entradas.

### 18. Guardar comments conserva prosa, no una sesión de código

Los borradores activos actuales dependen de su custodia en la sesión o en la
review guardada; al descartarlas se pueden eliminar sus archivos. El nuevo
control solicitado en D21 debe producir un resultado local cuya conservación
no dependa de que siga existiendo esa sesión de comparación.

**Consecuencia**: Distinguir en el plan los documentos en preparación del último
resultado conservado expresamente. Guardar comments no es `git review save`:
no crea una review-saved de código ni escribe `.review/comments.md`. La salida
de compare puede descartar trabajo posterior y respetar el último resultado
guardado. Ambos documentos siguen separados si se conservan los dos.

## Verificación de la etapa de especificación

La entrega modifica documentos, sin comportamiento ejecutable. Docker está
instalado pero su daemon Linux no está disponible; no se ejecutaron suites ni
se recurrió a correrlas nativamente en Windows. Esto no impide editar ni
verificar documentalmente la especificación.

## Phase 0: decisiones técnicas del plan

Se aplicó la skill local [speckit-plan](../../.claude/skills/speckit-plan/SKILL.md).
Su instrucción de despachar investigación se cubrió con tres revisiones de
sólo lectura: custodia/identidad/cierre, formato/CLI/histórico y cuatro clientes.
No se aplicaron skills de superpowers. No hay `extensions.yml`: sin hooks
before_plan/after_plan. La constitución continúa sin ratificar.

### T01. Parser propio y renumeración que preserva bytes

- **Decisión**: máquina de estados awk POSIX, orden físico y cambios exclusivos
  de dígitos. Normalización existente para interpretar, línea original para
  escribir; conservar BOM, CRLF y LF final. Una fence abierta hace código del
  resto; un límite ambiguo de metadata detiene la escritura completa.
- **Motivo**: `walk_parse/walk_body` buscan por path y walkthrough build ordena
  por números y rechaza repetidos. No expresan comentarios independientes.
- **Alternativas descartadas**: adaptar su reconciliador, parsear cada `##`,
  cuatro parsers de clientes o añadir runtime Markdown a la CLI.
- **Contrato**: [comments-format.md](contracts/comments-format.md).

### T02. Contexto documental y rango completo

- **Decisión**: token de documento/PR, registro local por origen/destino y
  linaje, comparación de marcador en tip y base completa. Excluir contextos
  integrados. Ambigüedad requiere `--new-context` o `--use-context`.
- **Motivo**: el código sólo tiene source/tip; nombre de rama, delta y existencia
  del archivo no distinguen un documento heredado. Dos PR externos con idéntico
  linaje son indistinguibles para Git: la inicialización explícita lo cubre.
- **Alternativas descartadas**: inferir por nombre móvil, número de proveedor,
  asumir que todo archivo del tip pertenece al PR o usar el lower incremental.

### T03. Tres capas de prosa y propiedad por sesión

- **Decisión**: baseline/checkpoint de descarte, preparación editable y resultado
  por generaciones. Gitdir propio del worktree, claves comunes a todos los
  modos y transferencia de custodio al guardar/continuar.
- **Motivo**: `finish/save` capturan el working tree entero y step banca código;
  `walk_draft_path` por source no es una identidad suficiente para compare.
  Una generación completa evita guardar sólo uno de los documentos ante fallo.
- **Alternativas descartadas**: editar `.review/comments.md` durante step,
  un único archivo Local/Shared, mover dos archivos sin preflight ni propietario.

### T04. Continuar Shared sin perder preparación anterior

- **Decisión**: comparar fuente, resultado y baseline fuente del mismo Shared;
  si ambas versiones cambiaron conservarlas y diagnosticar sin merge. Local
  nunca participa. Archivo heredado puede ser baseline de publicación sin ser
  semilla del contexto nuevo.
- **Motivo**: finish puede dejar el archivo sin commit o la entrega pendiente;
  una pasada posterior no debe perder ese preparado por cargar la fuente vieja.
- **Alternativas descartadas**: escoger el más reciente, regenerar Shared desde
  Local o sustituir por el source en toda pasada.

### T05. Entrega posterior al código e idempotencia

- **Decisión**: entregar Shared modificado antes de `record_exit`; tras fallo,
  marcar código terminado y documento pendiente. Retry de documento separado
  de replay; snapshot de undo actualizada sólo para su path.
- **Motivo**: `record_exit` identifica ediciones posteriores para proteger
  `finish --abort`. Registrar antes confundiría la escritura propia con trabajo
  posterior; registrar todo al reintentar absorbería cambios ajenos nuevos.
- **Alternativas descartadas**: entregar antes de extraer código, repetir finish
  completo o declarar éxito total cuando falta el archivo.

### T06. Locks y comprobación optimista de editores

- **Decisión**: lock por contexto, guardas dentro del lock, temporal hermano,
  comparación exacta inmediatamente antes de rename y candidatos recuperables.
- **Motivo**: coordina CLI y rechaza cambios externos detectados. POSIX no
  ofrece CAS de archivos frente a un editor que no coopera; existe una ventana
  entre la última comparación y rename. Se declara ese límite sin prometer
  inmunidad absoluta ni perder baseline/candidato para recuperación.
- **Alternativas descartadas**: comparar sólo cantidad/mtime, truncar en sitio
  o presentar un lock propio como bloqueo universal de editores.

### T07. Referencias ligeras, consulta por posición y revisión de bytes

- **Decisión**: base/head OID completos, rutas por lado y rango; ordinal físico
  más revisión de documento para el picker. Resolver árboles/blobs al consultar.
  La receta diferencia lado inexistente de objeto perdido. Código sin commit
  se señala como no reproducible.
- **Motivo**: HEAD es el lower durante una review, step cambia de par y el
  número puede repetirse/moverse. Git admite comparar árboles y blobs; no hace
  falta conservar parches. Fuente: [git-diff](https://git-scm.com/docs/git-diff).
- **Alternativas descartadas**: número como identidad, HEAD actual, snapshots,
  refs de retención, Ctrl+click o reviews históricas completas.

### T08. Familia CLI y entrada de texto

- **Decisión**: ocho subcomandos, destino obligatorio, argumento/stdin/editor;
  status dedicado de sólo lectura integrado al refresh. No cambiar wire records
  existentes de status/config/list. Texto de clientes por stdin sin log de cuerpo.
- **Motivo**: concentra autoridad sin alterar contratos previos ni mantener una
  preferencia global. El editor de Git ya define precedencia y comando shell:
  [git-var](https://git-scm.com/docs/git-var). Sólo ese comando configurado se
  interpreta como comando; el texto del comentario sigue siendo dato.
- **Alternativas descartadas**: reutilizar último destino, elegir por archivo
  existente o inferir el resultado parseando stdout humano.

### T09. Adaptadores de captura y guardado estricto

- **Decisión**: formulario multilínea por host; procedencia transitoria de los
  lados de diffs propios, sin parser de URIs internas. Guardar sólo Markdown
  afectado y validar resultado/postcondición. Buffer de código sucio no se guarda.
- **Motivo**: `draftActions.ts` ignora el booleano de save; Visual Studio ignora
  HRESULT de SaveDocuments; JetBrains necesita comprobar documento aún sucio.
  Sus helpers actuales no garantizan FR-032. VS Code documenta el booleano en
  [TextDocument.save](https://code.visualstudio.com/api/references/vscode-api#TextDocument);
  JetBrains separa documentos/guardado en su [SDK](https://plugins.jetbrains.com/docs/intellij/documents.html).
- **Alternativas descartadas**: Save All, continuar tras cancelación, atribuir
  coordenadas de un buffer distinto al blob del PR o afirmar soporte de cualquier visor.

### T10. Dos acciones y cinco controles, sin lista permanente

- **Decisión**: `addComment/saveComments` son acciones; Create/Open/Renumber/Diff/
  Prepare son de fila. Canónico 29, bloque del cuerpo, revelado condicionado al
  nacimiento del bloque y sin aviso duplicado.
- **Motivo**: captura no tiene sujeto de fila y Save comments afecta al par de
  compare. Open y Renumber pertenecen a un documento; no inflan menús.
- **Alternativas descartadas**: colar todos como acciones, ocultar Add como fila,
  tools de autor dentro de review o lista permanente de comentarios.

### T11. Límites concretos de hosts y vigilancia

- **Decisión**: Visual Studio usa vistas de texto públicas para coordenadas;
  TUI usa textarea existente, ubicación explícita y pager; no selección de
  otro proceso. Fuentes: [GetSelection](https://learn.microsoft.com/en-us/dotnet/api/microsoft.visualstudio.textmanager.interop.ivstextview.getselection?view=visualstudiosdk-2022)
  y [Bubbles textarea v1.0.0](https://pkg.go.dev/github.com/charmbracelet/bubbles@v1.0.0/textarea).
- **Motivo**: reutiliza infraestructura sin dependencia nueva ni equivalencias
  de host inventadas. TUI hereda vigilancia efectiva y Refresh.
- **Hallazgo previo, fuera del cambio**: AGENTS describe default de vigilancia
  apagado y `tui/cmd/git-review-ui/main.go`/`internal/host/watch.go` describen
  encendido. Comments no redefine ese default; sus tests fijan 0 y 1.
- **Alternativas descartadas**: coordinar selecciones de editores externos o
  incorporar una corrección no solicitada del default de vigilancia.

### T12. Publicación CLI antes de pisos de clientes

- **Decisión**: diseñar y verificar las cinco superficies, publicar primero la
  CLI con comments y sólo después fijar los pisos publicados de clientes.
- **Motivo**: `0.9.0` actual no implementa comments. No se inventa ahora un número
  de versión futura ni se deja pasar una CLI sin estos verbos.
- **Alternativas descartadas**: reutilizar el piso actual, copiar el de otro
  cliente o subirlo a una versión no publicada.

## Resultado de Phase 0

No quedan incógnitas técnicas sin resolución para generar modelo/contratos.
Las limitaciones de identidad externa, disponibilidad de objetos y CAS POSIX
son límites declarados de la solución, no respuestas pendientes de producto.
La investigación no implementa ni prueba el producto. La validación documental
de Phase 1 se registra al final de [plan.md](plan.md).
