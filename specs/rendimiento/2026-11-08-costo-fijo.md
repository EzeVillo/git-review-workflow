# Investigación del costo fijo en Windows

## Conclusión y alcance

Ezequiel pidió concentrarse en operaciones pequeñas y decidir si queda margen
viable. **Todavía no daría por agotado el costo fijo.** Hay un recorte incremental
demostrado de unos 0,47 s y una oportunidad mayor en la persistencia de la sesión.
Esta última merece un prototipo completo; no tiene todavía una mejora integral
demostrada. Los ajustes pequeños por sí solos no justifican prometer un Save de
uno o dos segundos.

Producto medido: commit 492877b, CLI 0.10.9. Se trabajó con copias aisladas,
sin cambiar código de producto, instalaciones, ventanas ni configuración del
sistema. El único cambio propio del repositorio es este informe; se conservan los archivos
ajenos. Sin push ni tags.

Fixture pequeño: walk de una entrada, un archivo de texto y el walkthrough del
autor, una corrección privada, Local y Shared preparados. Se contrastan rutas,
informes, prosa exacta, sesión y restauración del diff/cursor con Continue.
Cada fixture termina pausado. No mide clic, flush ni paint de IntelliJ.

## Dónde se va el tiempo

Se comparó la versión normal con una copia que agrega marcas de tiempo mediante
el builtin EPOCHREALTIME de Git Bash. Un calentamiento y dos muestras por variante,
Trace2 en ambas, sin suites concurrentes. Las medianas de Save fueron 6,10 s
normal y 6,04 s instrumentado: la diferencia entra en la variación observada,
sin una penalización apreciable del instrumento en esta muestra pequeña.

| Tramo instrumentado | Tiempo aproximado |
| --- | ---: |
| Validación inicial e identidad | 0,47 s |
| Guards de cierre y comprobación de destino | 0,28 s |
| Lock y dos preflights de custodia | 0,63 s |
| Preflight de transferencia previo a preparar el guardado | 0,29 s |
| Preparar contexto, destino y borrador | 0,20 s |
| Captura del código, ref y metadata del modo | 0,79 s |
| Copia de metadata común | 0,47 s |
| Transferir custodia, con sus relecturas y publicación | 1,11 s |
| Archivar borrador y su marcador | 0,13 s |
| Checkout y eliminación de la rama activa | 0,16 s |
| Liberar custodia | 0,11 s |
| Informe final completo | 1,17 s |

El arranque anterior a la primera marca agrega unos 0,23 s. Son medianas de
tramos, orientativas; no se suman para calcular la mediana integral.

Save solo ejecuta **55 procesos Git**, incluido el Git exterior que invoca el verbo:
24 config, 12 rev-parse, cuatro symbolic-ref, cuatro for-each-ref, tres
hash-object y los comandos de captura/cierre. Hay **15 escrituras de config**.
Los config incluyen siete cargas de metadata y dos consultas de configuración.
La secuencia paths + Save ejecuta 61 Git.

En una traza normal, los intervalos internos de los Git hijos suman 1,73 s,
frente a 6,09 s de Save. Esto no es tiempo de CPU ni una atribución exacta del
resto: quedan arranque de procesos, shell, utilidades, lectura y transformación
de datos. Sí descarta explicar los seis segundos sólo por el trabajo Git sobre
el código pequeño. El checkout cuesta unos 0,16 s incluyendo su cierre.

## Experimento conservador: conservar formato y controles

La copia experimental lee los manifests en la shell del llamador, conserva
las relecturas de custodia, evita sustituciones internas de algunos getters
y reúne los tres inventarios de refs del listado en una sola consulta.
Conserva el informe final completo y la representación del guard.

Dos calentamientos y cuatro muestras alternadas por variante, mismo fixture,
Trace2 y suites detenidas:

| Tramo | CLI 0.10.9 | Prototipo |
| --- | ---: | ---: |
| Save con estado completo | 6,01 s | 5,54 s |
| Consulta de rutas + Save | 6,89 s | 6,33 s |
| Procesos Git de la secuencia | 61 | 59 |

La reducción integral de Save es **0,47 s, 7,8 %**. Es margen real, pero acotado.
Pasaron 62 pruebas dirigidas con Bash 3.2: bytes, listado, guards, Save en cuatro
modos, custodia, worktrees enlazados y carreras de transferencia.

**No es una implementación lista para aplicar literalmente.** Una comprobación
adicional encontró una diferencia con un manifest malformado: una línea context
sin tab se interpreta vacía en el lector actual y como texto en el prototipo.
La versión definitiva necesitaría paridad explícita de esos casos y la matriz
completa. El dato de rendimiento corresponde a documentos válidos. El hallazgo
es otro motivo para mantener este código fuera del producto durante la pesquisa.

## Experimento de respuesta parcial: poco retorno

Sobre el prototipo anterior se probó devolver sólo status/list autoritativos,
sin calcular todavía los datos de autoría/config del pie. Se utilizó un sobre
distinto, save-core-probe, deliberadamente incompatible con el actual: no se
publicó un informe incompleto como si fuera completo.

Un calentamiento y dos muestras medidas por variante:

- Respuesta completa del prototipo: 5,38 s.
- Respuesta parcial experimental: 5,14 s.
- Ahorro del tramo esperado: **0,24 s, 4,5 %**; 59 → 56 Git en la secuencia.

El cálculo posterior del pie no está incluido ni implementado en los clientes.
No es la misma cantidad de trabajo total y no se suman estos ahorros a los de
la otra comparación. El informe completo actual resulta una decisión razonable:
no priorizaría cambiar cuatro clientes y su protocolo para este beneficio, que
además reintroduciría una consulta posterior. El 1,17 s del informe no es todo
información prescindible; buena parte publica inventario y estado nuevos.

## Procesos y persistencia: dónde está la opción de fondo

Git 2.52.0.windows.1, misma máquina y mismo ejecutable para comparar invocación
nativa y desde sh. Un calentamiento y tres muestras por experimento:

| Ensayo aislado | Mediana |
| --- | ---: |
| 20 consultas config desde Python nativo | 0,88 s |
| Las mismas 20 desde un loop sh | 1,28 s |
| 20 consultas capturadas por sustitución de comandos | 1,39 s |
| 60 capturas de printf builtin | 1,23 s |
| 60 printf builtin directos | 0,03 s |
| 15 escrituras config desde sh | 1,00 s |
| Escribir los 15 campos juntos y publicar por rename | 0,04 s |
| Seis cargas actuales de metadata | 0,87 s |
| Seis lecturas de un archivo de 15 campos en la shell | 0,03 s |

Los datos confirman dos costos distintos: lanzar Git y crear procesos de shell
para transformar datos pequeños. Cambiar sólo quién lanza los mismos comandos
no elimina el costo de esos comandos.

Los ensayos del archivo contienen campos ASCII sencillos. **Excluyen locks,
validación de rutas, guards, revisión, recuperación, durabilidad y migración.**
No implementan un backend ni demuestran que Save bajaría esos mismos segundos.
Muestran que el soporte físico no obliga a persistir cada campo por separado.

La interfaz de [git config 2.52](https://git-scm.com/docs/git-config/2.52.0)
escribe una clave/valor por invocación; cambiar varias claves como unidad no se
resuelve agregando un flag de lote a las llamadas actuales. La
[copia de rama](https://git-scm.com/docs/git-branch) copia también config y reflog,
pero el ensayo anterior ya mostró conflictos con config huérfana y fallos
parciales con config.lock. No se considera un reemplazo directo validado.

El objetivo del siguiente prototipo es **agrupar lectura y publicación del
estado de sesión**, conservando los comandos Git para índice, objetos y ramas
y el mismo porcelain. Esto no elige por sí solo un formato propio. La comparación
de alternativas se amplía abajo: SQLite y un auxiliar que agrupe config también
pueden lograrlo, con costos de producto diferentes. La recomendación inicial de
un formato propio fue prematura frente a esa comparación incompleta.

La contrapartida es real: hay que definir lectura legacy, comportamiento ante
CLI antiguas, exclusión entre mutaciones, relecturas frescas, bytes especiales,
sesiones por worktree y recuperación si falla una fase. Publicar un archivo
atómicamente no vuelve transaccionales refs, índice, checkout y custodia juntos.
El origen debe seguir recuperable hasta completar el destino. Tampoco se deben
reemplazar las claves sueltas por un blob que pierda actualizaciones concurrentes.

## Recomendación

1. Los recortes compatibles siguen siendo posibles, pero su magnitud probada
   ronda medio segundo. Integrarlos exige cerrar la paridad del parser y correr
   la verificación completa; no copiar el prototipo de investigación al producto.
2. Priorizar un prototipo completo de persistencia agrupada, manteniendo el
   mismo trabajo, informe final y garantías. **Cuatro segundos** sería un objetivo
   de evaluación razonable, no un tiempo ya obtenido ni una promesa. Si no logra
   una reducción clara de extremo a extremo, no adoptar la complejidad nueva.
3. Mantener por ahora la respuesta completa de Save. Adelantar el pie sólo
   mostró 0,24 s y no reduce el trabajo posterior. Un servicio que sólo mantenga
   viva la CLI, conservando el mismo motor, atacaría principalmente el arranque de
   unos 0,23 s. Es una inferencia del perfil, no un servicio implementado o medido.

No hay evidencia para conformarse ya con seis segundos. Tampoco para prometer
uno o dos con otra ronda de ajustes locales. La investigación cambia la
prioridad: el siguiente experimento valioso es la persistencia de la sesión.

## Ampliación: SQLite y alternativas que conservan config

Ante la pregunta de Ezequiel se separan dos decisiones: agrupar operaciones y
elegir el soporte. La primera tiene evidencia de costo; la segunda sigue abierta.
SQLite es una candidata razonable para estado local de una aplicación, un uso
que la [documentación oficial](https://www.sqlite.org/whentouse.html) contempla.
[No necesita un servidor](https://www.sqlite.org/serverless.html).

### Prueba aislada de SQLite en Windows

Se utilizó el módulo sqlite3 de Python ya instalado, SQLite 3.50.4, sin instalar
dependencias del producto ni cambiar su estado. Journal DELETE y synchronous
FULL, un calentamiento y cinco muestras medidas. Quince campos se insertan
nuevos en cada ensayo; se incluyen valores vacíos, apóstrofe, backslash, TAB,
LF y UTF-8 como BLOB con parámetros enlazados.

| Operación aislada | Mediana |
| --- | ---: |
| 15 inserciones, 15 commits, un proceso | 74 ms |
| 15 inserciones, una transacción, un proceso | 6,86 ms |
| Seis aperturas, lectura completa y cierre | 2,86 ms |
| Un auxiliar Python nuevo que guarda los 15 campos | 110 ms |
| 15 auxiliares Python nuevos, uno por campo | 1686 ms |

Los primeros tres ensayos incluyen conexión, lectura/escritura, commit cuando
corresponde y cierre; excluyen el arranque del intérprete. Los otros dos incluyen
arranque/import de Python. **No son mediciones de sqlite3.exe ni de Save.**
Se comprobaron bytes exactos, vacío frente a ausente, rollback, rechazo de un
segundo escritor durante una transacción y quick_check correcto.

SQLite no queda descartada por velocidad. La comparación demuestra también
que sustituir cada llamada individual por otro proceso puede mantener o
empeorar el problema. La integración debe agrupar trabajo. El formato de archivo
por sí solo no justifica prometer una latencia integral nueva.

### Opciones de producto

| Alternativa | Ventaja principal | Costo o incertidumbre |
| --- | --- | --- |
| Git config actual con menos procesos de shell | Conserva almacenamiento e instalación | Recorte integral probado de unos 0,47 s; paridad del prototipo todavía incompleta |
| Git config con auxiliar nativo transaccional | Explorar lotes sin migrar las claves existentes | Distribuir un binario/biblioteca y verificar equivalencia; almacenamiento medido abajo, Save integral pendiente |
| SQLite para metadata de sesión en gitdir | Transacciones, constraints, consultas y concurrencia estándar | Empaquetado, esquema/migración, diagnóstico y coordinación con Git |
| Archivo de sesión propio | Mantiene dependencia mínima si sigue siendo POSIX | Mantener serialización, locks, revisiones y publicación/recuperación propias |

La segunda opción no depende de una API imaginaria de Git CLI:
[git_config_lock de libgit2](https://libgit2.org/docs/reference/v1.9.2/config/git_config_lock.html)
permite bloquear el backend y agrupar cambios antes de git_transaction_commit.
Esto abre una vía que se había omitido. La comparación de almacenamiento se
incorpora abajo; **todavía no hay un auxiliar integrado en el producto**.
Hay que seleccionar explícitamente el destino de escritura y comprobar includes,
config por worktree, duplicados, bytes y compatibilidad con las fuentes que
actualmente interpreta Git. No se propone sustituir los comandos de objetos,
índice o checkout por libgit2.

SQLite puede evitar código propio de transacciones y parsing de metadata.
Los cuatro clientes podrían seguir usando la CLI y su mismo porcelain. Bajo la
arquitectura POSIX actual necesitaríamos empaquetar SQLite o un auxiliar que lo
integre; no conviene suponer que sqlite3 está instalado. En este Windows no se
encontró el ejecutable en PATH ni entre los archivos de Git, aunque hay un módulo
SQLite en Python y bibliotecas de SQLite incluidas en otras herramientas.

SQLite admite varios lectores y
[un escritor simultáneo](https://www.sqlite.org/lang_transaction.html).
Las transacciones de metadata deben ser cortas, con esperas acotadas y snapshots
nuevos donde el protocolo exige revalidar. No se debe sostener una transacción
vieja durante toda la operación y dar por vistas modificaciones concurrentes.
WAL no es obligatorio para este volumen; además tiene
[restricciones en sistemas de archivos de red](https://www.sqlite.org/wal.html).

Ninguna de estas opciones vuelve atómicos a la vez la base/config, los refs,
el índice y los Markdown. La recuperación entre fases sigue siendo necesaria.
La comparación de producto debe considerar ese protocolo y la compatibilidad,
además de cuántos milisegundos tarda una escritura.

**Prioridad revisada tras la comparación directa siguiente:** probar primero
un auxiliar de lotes que conserve config dentro del mismo Save. SQLite queda
como candidata si demuestra una ventaja integral que justifique la migración.
Un archivo propio sigue siendo una posibilidad, no una preferencia justificada.
El objetivo de cuatro segundos del apartado anterior es un criterio propuesto
para ese prototipo integral, no una proyección obtenida sumando microbenchmarks.

Evidencia de SQLite, JSON completo y script:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/sqlite-options/`.

## Comparación directa de velocidad: lotes de config y SQLite

Ezequiel aclaró que una migración a SQLite sólo tendría sentido si logra una
mejora relevante de velocidad. No fijó un umbral numérico. Para comparar la
oportunidad se midieron ambos motores, sin convertir una medición de escritura
en una promesa sobre Save.

Se obtuvo la biblioteca Win64 de
[LibGit2Sharp.NativeBinaries 2.0.324](https://www.nuget.org/packages/LibGit2Sharp.NativeBinaries/2.0.324)
desde NuGet en un directorio de experimentos. El paquete contiene libgit2 1.8.6;
se registró el SHA-512. Se invocaron sus APIs de config mediante ctypes y SQLite
3.50.4 mediante el módulo de Python existente. No se instaló una dependencia
del producto ni se modificaron archivos reales de un repositorio del usuario.

Un calentamiento y cinco muestras por método, orden alternado. Quince claves
de metadata y los mismos valores, incluidos vacío, comillas, backslash, TAB,
LF y UTF-8. Las bibliotecas ya estaban cargadas; se mide apertura, operaciones,
publicación y cierre. El caso Git CLI sí incluye sus 15 procesos nativos, pero
no agrega la shell de la CLI de producto.

| Operación aislada | Mediana |
| --- | ---: |
| Quince escrituras por el ejecutable Git | 738,30 ms |
| Quince escrituras libgit2 sin lote | 27,30 ms |
| Un lote libgit2 | 2,75 ms |
| Un lote libgit2 y flush explícito del archivo resultante | 4,98 ms |
| Una transacción SQLite | 7,17 ms |
| Seis snapshots completos con libgit2 | 3,19 ms |
| Seis aperturas/lecturas/cierres SQLite | 4,19 ms |

SQLite usa journal DELETE y synchronous FULL. Se activó explícitamente
[GIT_OPT_ENABLE_FSYNC_GITDIR](https://libgit2.org/docs/reference/v1.8.7/common/git_libgit2_opts.html)
y se agregó el ensayo con flush del archivo. Esto **no certifica equivalencia
exacta de durabilidad ante corte de energía** entre motores ni con Git.
Los números no incluyen arranque/import/carga de un auxiliar, protocolo con
la shell, lectura de todas las fuentes de configuración ni el resto de Save.

Se contrastaron los valores escritos por libgit2 con el propio Git, incluidos
bytes especiales. Se conservaron una clave ajena y un comentario. Descartar una
transacción sin commit dejó el archivo original intacto. Mientras el lote tenía
config.lock, el escritor Git externo fue rechazado (exit 255), sin sobrescribir
la configuración. No equivale a verificar todavía toda la semántica de Git.

**Conclusión de velocidad:** ambos accesos agrupados están en milisegundos para
este volumen. La diferencia absoluta entre 5 y 7 ms no justifica una decisión
de arquitectura para un Save de seis segundos. La ganancia importante aparece
al quitar procesos, lecturas repetidas y escrituras separadas. SQLite es rápida,
pero conservar Git config no impide obtener ese tipo de acceso rápido.

Esto cambia el orden del próximo experimento: integrar un auxiliar acotado para
lectura/escritura de metadata agrupada, con config actual, preservando los
comandos Git para el código. Medir Save completo con la misma respuesta y las
mismas guardas. Si el resultado integral queda casi igual, este ensayo aislado
no autoriza afirmar que se resolvió la latencia ni justifica adoptar el auxiliar.
Tampoco justifica migrar a SQLite sólo por su tiempo de escritura.

No se proyecta que Save vaya a tardar 5 o 7 ms. Los otros procesos y controles
siguen presentes; tampoco se suman los recortes de ensayos distintos como si
fueran una muestra de Save. La decisión final requiere la comparación integral.

Evidencia, paquete aislado, versiones, valores completos, script y JSON:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/backend-compare/`.

## Evidencia y reproducción

Artefactos, baseline, copias experimentales, diff del prototipo, trazas y JSON:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/fixed-cost/`.

Scripts y logs originales:
`C:/Users/ezevi_30ey2ks/AppData/Local/Temp/git-review-fixed-cost/`.

summary.json contiene el perfil instrumentado; prototype-summary.json la
comparación conservadora; core-summary.json la respuesta parcial;
micro-summary.json los costos aislados; git-breakdown.json el Git de Save solo.
Las muestras son pequeñas y sintéticas, sin UI ni flush. No son percentiles
ni garantías para otras instalaciones. No se modificó código de producto.
