# Lectura de metadata en la shell de la operación

## Objetivo y alcance

Reducir el costo fijo identificado en el perfil de escalabilidad de Save sin
cambiar POSIX, el modelo de ramas ni el significado de pausar. CLI 0.10.9 usa
una lectura sin stdout por campo en Save, en los preflights compartidos de
custodia y en las filas del listado porcelain. Los cuatro clientes reciben
el cambio mediante la CLI; sus versiones permanecen iguales.

El cargador conserva la representación octal canónica que gobierna el guard.
El mismo proceso AWK produce una segunda vista donde los valores comunes se
consumen por asignación en la shell del llamador. Controles y backslashes
usan el decodificador anterior. Se conservan Unicode, espacios, ausente/vacío,
último valor en claves duplicadas y la eliminación previa de LF finales al
extraer un escalar. Los datos nunca se evalúan como código.

La vista no sale de la operación. Los preflights vuelven a leer config y gitdir
en sus límites originales; una recarga fallida invalida ambas vistas. La
escritura de cursor invalida la vista rápida sólo después de escribir con éxito.
Save sin --porcelain conserva su salida y sigue sin calcular informes finales.

## Comparación nativa en Windows

Baseline eb9653e (producto 0.10.8), dos operaciones de calentamiento y cuatro
muestras alternadas por variante sobre el mismo fixture walk con Local, Shared
y una corrección privada. Trace2 en ambas. Se mide paths y Save con guard y
estado final; preparación, guard inicial, Continue y aserciones quedan fuera.
Suites detenidas. No mide flush de buffers, clic, refresco o paint de IntelliJ.

| Tramo | Anterior | Nuevo |
| --- | ---: | ---: |
| Consulta de rutas | 0,87 s | 0,86 s |
| Save con estado final | 6,73 s | 5,92 s |
| Consulta + Save | 7,60 s | 6,85 s |
| Procesos Git de la secuencia | 61 | 61 |

Save baja **0,80 s (12,0 %)** de mediana; la secuencia baja **0,75 s (9,9 %)**.
Las medianas del total se calculan sobre muestras completas, sin sumar medianas
de tramos. El número de Git no cambia: se eliminan sustituciones de la shell,
no las consultas frescas ni las escrituras de config.

Se comprueban rutas e informes finales exactos, main limpio después de guardar,
Local y Shared byte por byte, misma sesión y restauración del diff y cursor al
retomar. La versión anterior acepta el guard emitido por la candidata. Cada
fixture termina pausado con su prosa. Es una muestra pequeña y sintética, no
un percentil ni una garantía para otro repositorio.

## Contraste de escala

Sobre los fixtures whole del perfil anterior, con Local y una corrección privada:
10000 archivos con PR de 10, PR de 1000 y PR de 10000. Archivos determinísticos
comprimibles de 1 KiB, mismo fixture por variante, un calentamiento por variante
seguido de dos muestras medidas por variante. Suites detenidas, Trace2 en ambas.
Save incluye estado final; guard inicial, Continue, aserciones y UI quedan fuera.

| Archivos del repo / cambiados | Anterior | Nuevo |
| --- | ---: | ---: |
| 10000 / 10 | 6,73 s | 6,05 s |
| 1000 / 1000 | 7,97 s | 7,17 s |
| 10000 / 10000 | 14,56 s | 14,60 s |

En el caso de 10000 cambiados **no hay una mejora observable del total** con esta
muestra. Los rangos se superponen: 14,03–15,09 s antes y 14,25–14,95 s después.
El tiempo interno de switch varía de una mediana de 8,11 a 8,60 s; no incluye
spawn y no es una atribución completa del costo. No se vende el ahorro del
caso pequeño como una solución a este escenario.

Los tres mantienen 52 procesos Git. Se comprueban informes list/config exactos,
main limpio, Local byte por byte, misma sesión y diff restaurado al retomar.
Todos los fixtures terminan pausados. Datos completos en scaling-summary.json.
La biblioteca medida en el caso pequeño coincide por SHA-256 con la final;
el contraste de escala ya usa el estampado de versión 0.10.9.

## Límites y trabajo pendiente

El resultado justifica conservar este corte, pero casi seis segundos siguen
siendo demasiado para una operación interactiva pequeña. No se da por resuelto
Save ni se extrapola el porcentaje al IDE.

Las escrituras separadas de config y los bancos de step siguen pendientes de
agrupación con guardas y recuperación. Los PR que cambian miles de archivos
siguen pagando su restauración al volver a la rama de origen. Evitar ese I/O
requiere diseñar otro flujo de checkout; este cambio no lo elimina.

Evidencia, script, baseline, muestras y hash del código medido:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/config-read/`.

## Verificación

- 1562 casos Bats completos, cinco omisiones previstas y ningún fallo.
- 58 dirigidos con Bash 3.2: bytes, guards, cursor, custodia concurrente y Save.
- Ocho casos nativos Windows: los siete del nuevo lector y Save con estado
  final en whole, step, walk y compare, conservando código y prosa al retomar.
- 123 integraciones reales de VS Code con esta CLI.
- TUI: gofmt, go vet y go test, incluidos host y golden.
- ShellCheck completo de los archivos de CI; 52 tests de contratos y diez de
  reparto de CI, con inventario y distribución válidos.
- npm pack, instalación en un prefijo temporal y versión 0.10.9 comprobada.

Logs y snapshots de verificación:
`C:/Users/ezevi_30ey2ks/AppData/Local/Temp/git-review-config-read/`.

El siguiente corte del costo fijo debe agrupar refs de step y persistencia de
metadata con recuperación definida. Para el caso de miles de archivos cambiados
hay además una decisión de flujo: una sesión en un worktree dedicado podría
separar la pausa de la restauración del checkout principal. Hace falta diseñar
esa experiencia y custodia; todavía no se implementó ni cambió Save por sorpresa.
Sin push, tags ni publicación. Los archivos y ventanas ajenos permanecen intactos.
