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

La opción que merece el siguiente prototipo es **representar y publicar el
estado de sesión como una unidad versionada dentro del gitdir**, conservando
los comandos Git actuales para índice, objetos y ramas. Los clientes podrían
seguir leyendo el mismo porcelain. El beneficio vendría de reducir consultas,
serializaciones y escrituras, con un formato propio acotado a nuestro estado.

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
