# Correcciones de la reauditoría — 19 de octubre de 2026

Se corrigieron los cinco defectos de
[la reauditoría](reauditoria-equipo-ux-2026-10-19.md). Se conservaron los cambios
preexistentes del checkout; no se crearon commits ni tags ni se publicaron paquetes.

## Decisión de producto

El usuario pidió que Shared quede staged al terminar, en vez de corregir sólo
el banner. Esa decisión reemplaza el contrato anterior de entrega sin stage.
Finish y Prepare entregan `.review/comments.md` después de extraer código y lo
incorporan al índice junto con las correcciones, sin commit ni push adicionales.
Local permanece privado en el gitdir. Una review sólo con comentarios no fabrica
un commit de correcciones.

La entrega conserva su entrada original del índice y la última entrada que la
propia CLI publicó. La transacción toma `index.lock`, compara esas versiones y
modifica únicamente el path entregado. No adopta una versión concurrente como
baseline ni vuelve a leer el índice liberado para atribuirse una escritura ajena.
Un lock ocupado o un conflicto de stage deja la entrega pendiente y recuperable.
Repetir Prepare es idempotente; actualizar su entrega propia sigue permitido.
Undo conserva las guardas de salida y restaura el índice previo al Finish.

## Otros defectos corregidos

- **CRLF limpio:** se reconoce la conversión de fin de línea que aplica Git,
  tanto por `core.autocrlf` como por atributos. Se mantienen las validaciones
  de rango. Si hay clean filter, ident o conversión de encoding, no se usa ese
  mecanismo para declarar reproducibles las coordenadas. Una edición real o
  un buffer marcado explícitamente sin guardar sigue siendo `unversioned`.
- **Tema del compositor WPF:** ventana, texto, selectores, popup y botones usan
  la paleta del host. Los templates de los selectores no heredan colores del SO.
- **Tamaño mínimo:** alcance y destino permanecen visibles; fragmento y aviso
  tienen scroll acotado y el cuerpo conserva espacio de escritura. Guardar y
  Cancelar mantienen tamaño y acceso por teclado.
- **Contextos con el mismo nombre:** la CLI agrega una descripción de candidato
  con ordinal de presentación, fecha UTC de creación disponible, presencia/counts
  y asunto revisado. Los cuatro clientes la muestran. El ordinal no reemplaza
  el token como identidad; status no expone cuerpos. Los contextos anteriores
  sin fecha y los registros antiguos sin descripción siguen siendo legibles.

README y referencia CLI se actualizaron en ambos idiomas, junto con los contratos,
AGENTS.md y decisiones.md. Las auditorías originales se conservan como evidencia
histórica del comportamiento anterior.

## Verificación

Los logs y renders locales viven en `dist/comments-fixes-20261019/`, ignorado por Git.

| Comprobación | Evidencia |
|---|---|
| CLI, familia completa de comentarios | Tanda final: 338 aprobados, sin omisiones, exit 0; incluye nueve regresiones nuevas. |
| Regresiones finales de entrega | 35 aprobadas: nueve casos nuevos y recorridos de Finish, Undo, Prepare, conflictos e I/O. |
| VS Code | Compilación y tipos; 506 unitarias aprobadas, un pending preexistente; 108 integraciones aprobadas en Electron. |
| JetBrains | Suite completa, frontera de dominio, buildPlugin y verificaciones de configuración/estructura aprobadas. |
| Visual Studio | 409 tests de dominio y 68 de host; MSBuild/net472/VSIX aprobados. |
| WPF | 30 fixtures existentes y 40 comprobaciones del compositor: dos temas, dos tamaños, con/sin selección, incluyendo destino visible y colores reales de los selectores. Renders revisados visualmente. |
| TUI | Tests de cinco paquetes y detector de carreras aprobados; selector conserva descripción visible y token elegido. |
| Contrato y assets | Checker, 41 tests del gate y checker del logo aprobados. |
| ShellCheck y whitespace | Lista completa de CI más helper de equipo aprobada; revisión focal de la librería y `git diff --check` aprobadas. |

Las pruebas de snapshots ahora desactivan explícitamente `diff.autoRefreshIndex`:
la observación de una entrada creada por cacheinfo no debe refrescar sus bytes.
No se relajó la comparación del índice en los errores de Undo.

Se conservaron los intentos fallidos. El primer runner paralelo no tenía GNU
parallel; el primer contenedor JDK no tenía Git. Se corrigieron los entornos y
se repitieron las comprobaciones. La primera repetición de Electron detectó tres
aserciones del fixture que omitían el newline de Git, interrumpían su limpieza y
contaminaban la spec siguiente; corregidas, la suite completa aprobó los 108 casos.
Los primeros checks WPF fallaron por tema y recorte antes de corregir el formulario.

## Límites

Este cambio cierra los cinco defectos concretos. La reconciliación guiada de la
respuesta del autor y otras mejoras de descubribilidad conservan su alcance
separado. No se ejecutó la aceptación interactiva completa dentro de IntelliJ o
Visual Studio ni la matriz nativa de tres SO; T154/T155 permanecen pendientes.
Los paquetes se compilaron sin instalarlos en los IDE personales. No se publicó
ninguna versión ni se modificaron las decisiones pendientes de release.
