# Latencia de los clientes y validación del contexto de una acción

## Diagnóstico inicial (6 de noviembre)

El sandbox de IntelliJ carga el plugin 0.5.1. En su log del 6 de noviembre,
`next` tarda aproximadamente 1,45 s, pero la lectura completa anterior y la
posterior cuestan otros 1,4 s cada una. El refresco publica primero el panel y
después consulta Comments, aunque mantiene la operación ocupada hasta terminar.
Cancel agrega una consulta de custodia de documentos antes de descartar.

El volumen de salida no explica esa latencia: una consulta del sandbox devolvió
298 bytes de estado y 1.029 bytes de comentarios. El costo está en crear procesos,
consultar Git, reconstruir el recorrido y comprobar documentos y revisiones.

| Cliente | Validación previa de una navegación normal | Lectura posterior |
|---|---|---|
| IntelliJ | Vuelve a leer el estado completo, sin Comments | Estado y Comments; espera ambos |
| Visual Studio | Modelo en Next/Prev; prelectura completa en otras mutaciones | Estado y Comments; navegación además repite el refresco |
| VS Code | Contrasta el modelo que ya tiene | Estado y Comments; espera el refresco |
| TUI | Contrasta el modelo que ya tiene | Ya separa estado principal y detalles |

La comprobación evita actuar sobre otra review si la rama o la sesión cambió
desde que se mostró el panel o se abrió una confirmación. No corresponde quitarla.
Pedir todo el panel para comparar su identidad es trabajo innecesario.

## Primer cambio autorizado: validación dentro de la invocación

La CLI publica un testigo opaco `guard` junto al estado. El cliente conserva
ese testigo con el modelo que originó la acción y lo envía mediante
`git review --expect-state <guard> <comando> ...`. La CLI vuelve a calcular la
identidad antes de ejecutar el verbo. Si difiere, devuelve el código 4 sin
ejecutarlo. El cliente recarga el estado completo y muestra su aviso de estado
obsoleto. No reintenta automáticamente una acción sobre una review diferente.

El testigo identifica el gitdir, HEAD, rama y metadata de la review. No incluye
el working tree ni el contenido de los buffers: editar código no debe invalidar
la intención de navegar o guardar.

Este primer corte emite el testigo durante una review activa, incluido un Finish
en conflicto. Fuera de ella se conserva el recorrido anterior: Start, Compare y
los cierres pendientes requieren información de inventario y configuración que
no corresponde reemplazar por la identidad de una review activa.

Los cuatro clientes usan el mismo contrato. Donde ya se hacía una prelectura
completa, el caso coincidente la evita. Donde se contrastaba sólo el modelo,
se agrega comprobación contra el repositorio real. Si una CLI anterior no emite
testigo se conserva el comportamiento anterior; no se inventa un token local.

Esto no sustituye los locks y precondiciones propios de los verbos ni las
revisiones de los documentos Local/Shared. Tampoco convierte una operación Git
externa concurrente en una transacción de la CLI. El objetivo de este corte es
reemplazar la validación costosa, manteniendo las protecciones existentes.

## Alternativas identificadas en el primer corte

- Devolver el estado actualizado desde la mutación y reutilizar su lectura
  (implementado para Next/Prev en el segundo corte, el 7 de noviembre).
- Liberar la navegación al confirmar el estado principal, dejando Comments y
  explicación en segundo plano con rechazo de respuestas antiguas
  (implementado en el segundo corte).
- Omitir consultas de guardado de comentarios cuando no hay buffers sin guardar.
- Reducir otros procesos internos de las consultas de la CLI.
- Eliminar el refresco posterior duplicado de navegación en Visual Studio
  (incluido en el segundo corte).

El prototipo local de `next/prev --porcelain` se apartó durante el primer corte.
El segundo corte incorpora una respuesta completa con capacidad explícita,
emisor compartido con status, fallback y pruebas en los cuatro clientes.

## Verificación y medición

Se comprobarán coincidencia, cambio de rama/HEAD/metadata, gitdirs distintos,
ediciones permitidas, cierres pendientes y ausencia de efectos al rechazar.
Los clientes deben conservar el testigo de la acción, refrescar ante código 4 y
mantener la compatibilidad con reportes sin `guard`.

### Windows nativo: secuencia de llamadas

Se comparó el código anterior (`47acbcb`) con este cambio en un repositorio
temporal con dos entradas de walk, alternando Next y Prev. Se ejecutaron cuatro
muestras por variante, con el estado inicial ya cargado fuera del tiempo medido.
El flujo anterior hace versión → estado → mutación → versión → estado → Comments;
el nuevo hace mutación con validación → versión → estado → Comments.

| Medición | Anterior | Con validación en la CLI |
|---|---:|---:|
| Mediana hasta completar la mutación | 5,05 s | 2,68 s |
| Mediana de la secuencia completa | 10,11 s | 6,96 s |
| Rango de la secuencia completa | 8,60–10,39 s | 6,51–8,13 s |

La reducción observada del total fue del 31 %. La mutación sin prelectura sigue
teniendo costo: la CLI comprueba el testigo antes de ejecutar el verbo. Se
comprobó que cada muestra moviera el cursor esperado y conservara el diff.

Es una medición de las llamadas bloqueantes de la CLI en Windows, **no de un clic
real en IntelliJ**. No incluye render, explicación ni `GitRepository.update()`.
Las dos instancias de IntelliJ seguían abiertas y había pruebas en Docker en
paralelo; cuatro muestras no caracterizan todos los repositorios ni una máquina
en reposo. La variación del refresco posterior también influye en el total.
La mejora esperada se concentra en IntelliJ y las mutaciones de Visual Studio
que hacían una prelectura, no en clientes que ya la omitían.

Evidencia local: `ide-context-guard/benchmark.py` y `windows-benchmark.json`
en los artefactos del chat. El fixture es independiente del sandbox del usuario.

### Validación funcional

- CLI: coincidencia y rechazo sin efectos al cambiar rama, HEAD, cursor, sesión
  de Comments o gitdir; ediciones de código permitidas; metadata de otras
  reviews; SHA-1/SHA-256; tokens inválidos y compatibilidad de reportes.
- IntelliJ: 382 tests, compilación y estructura del ZIP 0.5.2.
- Visual Studio: 424 tests de dominio, 74 de host, build VSIX 0.4.2 y verificación
  WPF con 30 fixtures.
- VS Code: 534 tests unitarios, un caso pendiente preexistente y 123 casos de
  integración con el host real de la extensión.
- TUI: formato, `go vet` y tests de todos los paquetes.
- Contrato de producto: 52 tests y comprobación de los cuatro clientes; ShellCheck.

Las instancias de IntelliJ abiertas durante la primera medición conservaban el
plugin 0.5.1 cargado. El ZIP 0.5.2 se generó para las pruebas locales; requería
recargar el plugin mediante el flujo de desarrollo o instalar el ZIP y reiniciar.
No se publicaron versiones en las tiendas.

## Segundo corte: navegación y estado en una misma operación (7 de noviembre)

La prueba manual del usuario confirmó que el sandbox ya carga 0.5.2. Un Next
de esa instancia mantuvo ocupado el cliente durante 5,08 s: 1,81 s de validación
y navegación, 1,50 s de status, 1,38 s de Comments y 0,39 s de versión y refresco
del IDE. El primer cambio había eliminado la prelectura; no resolvía los costos
posteriores. El 31 % del benchmark anterior no era una medición del clic real.

La corrida del commit `8a6c6d3` terminó con 88 jobs correctos y 17 fallidos,
todos en macOS. El log de lint identifica `git-review-lib.sh:135`: Bash 3.2,
usado como `/bin/sh` en macOS, no interpreta el patrón `case` dentro de aquella
sustitución de comandos. Se reemplaza por una comparación de prefijo y se
comprueban sintaxis y funcionamiento con ese parser, además de Windows y Linux.

El contrato de contexto se conserva. Para Next/Prev, el dispatcher entrega el
token al verbo, que valida su propia lectura de config, rama y HEAD antes de
cargar o recuperar el recorrido. Ese snapshot y la secuencia ya cargada sirven
para ejecutar y responder. El emisor de status es compartido: no se ejecuta
otro status ni se calcula de nuevo el walkthrough. El cursor sólo se incorpora
a la respuesta después de que su escritura tenga éxito; step también incorpora
su nuevo HEAD, archivos y bancos de ediciones.

Los cuatro clientes comprueban `capability navigation-state` antes de pedir
`--porcelain`. Consumen la respuesta como estado principal completo de la CLI,
con guard nuevo. Una respuesta inválida, un fallo o una CLI anterior conservan
la lectura completa. No hay actualización optimista del cursor en los clientes.
En un límite de la secuencia, la CLI informa `navigation unchanged` y un
`notice` operativo, sin ofrecer en prosa un botón que el panel ya tiene.

En IntelliJ, VS Code y Visual Studio, las acciones de review dejan de esperar
a Comments después de publicar el estado principal. La TUI ya separaba esa
lectura; ahora puede iniciar sus detalles a partir de la respuesta de navegación.
Las respuestas secundarias antiguas se rechazan por generación; se mantienen la
vigilancia de documentos, las consultas fallidas como diagnóstico y las guardas
propias de Comments. Visual Studio también elimina su refresco de navegación
duplicado. Cancel y Finish conservan las lecturas necesarias de inventario,
configuración y custodia; no reciben una respuesta de navegación.

IntelliJ agrega al log la duración de su lock de mutación y si Comments sigue
pendiente al liberarlo. El siguiente paso manual es probar el ZIP 0.5.3 y medir
esa línea junto con la publicación del cursor y la respuesta de los controles.
La medición de la CLI no sustituye esa prueba del IDE.

Este segundo corte queda local, sin commit ni push, por pedido del usuario.
La corrida remota anterior sigue en rojo hasta que se autorice subir un arreglo.

### Medición del segundo corte

Se comparó el flujo de 0.5.2 / CLI 0.10.2 (`8a6c6d3`) con el de 0.5.3 /
CLI 0.10.3, sobre un walk temporal de dos entradas en Windows nativo. Fueron
cuatro muestras por variante, alternando Next/Prev y el orden de las variantes.
El estado mostrado y su guard se cargaron fuera del tiempo medido.

| Mediana de las llamadas | Anterior | Segundo corte |
|---|---:|---:|
| Hasta disponer del estado principal | 3,48 s | 1,55 s |
| Comments, en paralelo con el porqué | 1,41 s | 1,43 s |
| Tiempo bloqueante representado por esas llamadas | 4,89 s | 1,55 s |
| Rango de ese tiempo bloqueante | 4,78–5,09 s | 1,54–1,58 s |

El flujo anterior esperaba Comments, pero no el porqué; la medición los separa
y computa sólo Comments dentro de su bloqueo. En el flujo nuevo, ambos son
secundarios. Se verificaron el cursor, el diff y la igualdad entre la respuesta
y un status fresco en cada muestra. El hash de los archivos de la CLI medidos
coincide con los del checkout final.

No es una medición del clic real: excluye `GitRepository.update()`, render y
despacho del IDE. Tampoco elimina el trabajo de Comments; cambia cuándo se
espera y protege su publicación. El ZIP es el que debe confirmar la experiencia
real. Los resultados crudos y el script están en los artefactos del chat,
`navigation-state/windows-benchmark.json` y `navigation-state/benchmark.py`.

### Verificación del segundo corte

- CLI: 1.527 casos en la suite completa de Docker, con los skips previstos de
  plataforma; sin omisiones ni fallos. Incluye límites en walk/step, recuperación
  del borrador, fallas de snapshot y de escritura, guard y efectos reales en Git.
- Bash 3.2: sintaxis y 25 casos funcionales de navegación, contexto y procesos.
  Es una comprobación del parser de macOS en Linux, no una corrida nativa macOS.
- Windows nativo: los 20 casos de navegación y guard, todos correctos.
- IntelliJ: 387 tests, dominio sin imports del IDE, build y estructura del ZIP.
  Incluye rechazo de Comments antiguos y tickets atómicos del porqué.
- VS Code: 538 tests unitarios, un pendiente preexistente y 123 integraciones
  con el host real de la extensión.
- Visual Studio: 424 tests de dominio, 78 de host, build VSIX net472 y las
  30 fixtures de verificación WPF.
- TUI: formato, `go vet` y todos los tests, incluidos los golden.
- ShellCheck, los 62 tests de contratos/reparto y el control del producto pasan.

El ZIP local es `jetbrains-plugin/build/distributions/git-review-workflow-0.5.3.zip`.
Su descriptor y sus clases se verificaron; el sandbox abierto durante este trabajo
todavía contiene el JAR 0.5.2. No se reemplazó ese plugin ni se cerró el IDE.
Para la prueba manual hay que cargar 0.5.3 y reiniciar o volver a ejecutar el
flujo local de desarrollo. El log debe permitir contrastar la publicación del
cursor, `Mutation lock released after ...ms` y la finalización posterior de Comments.

## Tercer corte: prosa con la navegación y guardado previo sin consultas innecesarias

Ezequiel probó IntelliJ 0.5.3 y confirmó «ahora sí mucho mejor». El log de las
15:54 muestra tres Prev con locks de 1.744, 1.785 y 1.747 ms; sus llamadas de
navegación tardaron 1.601, 1.661 y 1.621 ms. Comments y el porqué completaron
después. Es evidencia del uso real del plugin y complementa el benchmark del
segundo corte. El sandbox abierto ya carga 0.5.3.

Este corte implementa dos mejoras adicionales:

- Los tres IDE consultan primero si tienen algún documento sin guardar. Sólo
  cuando el host confirma que todos están guardados omiten el inventario de
  Comments anterior a Save/Cancel/Finish y cierres equivalentes. Si existe
  cualquier buffer sucio, el host no puede responder o falla la consulta, se
  conserva el inventario y el guardado selectivo. La custodia y las guardas de
  cierre continúan en la CLI. El atajo no depende del inventario del panel.
- La navegación walk devuelve el porqué de la entrada actual en registros
  opcionales `why`/`why-line`. Se extrae en la misma pasada de AWK que reúne
  las banderas de las entradas y del documento ya cargado. Los cuatro clientes
  lo publican con el estado principal. Si falta o es inválido, consultan sólo
  el porqué como antes; Comments sigue independiente y protegido por generación.

El scanner es compartido con `status --why`, incluidas la eliminación de
marcadores y las líneas vacías iniciales/finales. La prosa se encuadra por
líneas y escapa barras, tabs y CR; no se evalúa ni se usa como argv. Las pruebas
contrastan texto con párrafos, espacios, Unicode, barras y sintaxis de shell.
La traza de procesos confirma una sola lectura de config y del walkthrough,
una pasada de campos y ninguna consulta/scanner separado del porqué.

La prueba del runner de CI se ajusta para elegir un grupo que contenga casos
divididos, en vez del primer grupo con varios archivos: agregar un archivo
nuevo había cambiado ese grupo a dos ejecuciones completas, donde el conteo
parcial no aplica. Se mantienen la inyección de fallos, la comprobación de
stdin y el rechazo de planes incompletos. No se cambian matrices ni presupuestos.

La integración completa de VS Code detectó una carrera: el borrador se borraba
en disco, pero un watcher podía invalidar la lectura principal de la mutación
y hacerla regresar antes de publicar la fila actualizada. Se coordina esa
publicación con los refrescos de fondo y sus reruns pendientes. La barrera
termina con el estado principal; Comments conserva su independencia. Una prueba
determinista reproduce el cruce y falla antes del arreglo; otra cubre el rerun
que ya estaba pendiente. No se agrega un timeout ni se debilita el assert del
panel de la prueba de integración.

No se implementan en este corte el caché de versión, las lecturas duplicadas
de arranque ni la reducción de forks restante. Requieren medir e invalidar
correctamente el contexto antes de cambiar su comportamiento.

Versiones locales: CLI 0.10.4, IntelliJ y VS Code 0.5.4, Visual Studio 0.4.4
y TUI 0.2.4. Las capacidades nuevas siguen siendo opcionales. El ZIP está en
`jetbrains-plugin/build/distributions/git-review-workflow-0.5.4.zip`; su descriptor
y las clases nuevas se comprobaron. El IDE abierto conserva 0.5.3: no se cerró,
no se reemplazó su plugin y no se instaló nada automáticamente. El corte queda
sin commit ni push, a la espera de la prueba manual del usuario.

### Medición del tercer corte

Se comparan cuatro muestras alternadas por variante en un walk temporal de
Windows. La baseline se extrae del snapshot local anterior a este corte,
0.5.3 / CLI 0.10.3; usar HEAD habría comparado otra vez contra 0.5.2. Ambas
variantes navegan con guard y respuesta porcelain. La anterior consulta después
`status --why`; la nueva obtiene la prosa de la respuesta. Se comprueban el
cursor, el diff sin cambios y la equivalencia con un status fresco.

| Mediana de llamadas | 0.5.3 | 0.5.4 |
|---|---:|---:|
| Estado principal | 2,61 s | 2,67 s |
| Consulta separada del porqué | 2,15 s | No se ejecuta |
| Estado y porqué disponibles | 4,77 s | 2,67 s |

La diferencia del estado principal es 0,06 s, dentro de la variación observada
(2,38–2,94 s antes; 2,48–2,81 s después). Son muestras bajo carga de suites y con
los IDE abiertos; no se mezclan con la medición de 1,55 s del segundo corte ni
se interpretan como un incremento del tiempo del clic. Los controles de 0.5.3
ya se liberaban antes del porqué: el ahorro aquí es su consulta y su aparición
tardía, no otros dos segundos de bloqueo de controles.

El inventario `comments status --porcelain --all`, medido aparte en el mismo
fixture, costó una mediana de 2,40 s en la baseline. Esa llamada se omite sólo
con buffers confirmados limpios. No se midió un clic real de Cancel con 0.5.4,
y el ahorro total de cierre depende también de las otras lecturas del panel.

El script y los datos crudos están en `navigation-why/benchmark.py` y
`navigation-why/windows-benchmark.json` de los artefactos del chat. Registran
los hashes de ambos binarios y del snapshot de baseline. No se utilizó ni
modificó el repositorio de prueba manual del usuario.

### Verificación del tercer corte

- CLI: 1.530 casos en Docker, con los skips previstos de plataforma; se
  contrasta el conteo físico contra el plan y todos los grupos terminan bien.
- Bash 3.2: 18 casos de navegación, prosa y snapshots. Windows nativo: los tres
  casos nuevos de prosa y traza. No equivalen a una corrida nativa de macOS.
- IntelliJ: 392 tests, dominio sin dependencias del IDE y compilación/estructura
  del ZIP 0.5.4. SHA-256:
  `D995A33F6C78ED8FB1618647C7318FF689AE3F58BF189EEAA0BB7B01F2D39D97`.
- VS Code: 546 tests unitarios, con un pendiente preexistente. Incluyen el
  guardado selectivo, el decodificador de prosa y ambos cruces de watchers.
  La integración final con el host real pasa los 123 casos. El primer intento
  terminó por una caída del renderer; las corridas posteriores usan 1 GiB de
  memoria compartida en el contenedor. El segundo intento expuso la carrera
  descrita arriba; el último ejecuta toda la suite con esa coordinación corregida.
- Visual Studio: 424 tests de dominio, 84 de host, build VSIX net472 y las
  30 fixtures WPF. El build conserva dos advertencias de threading en
  `GitReviewToolWindow.cs` ajenas a este corte; no aparecen errores nuevos.
  El paquete se reconstruyó con `Rebuild` y se comprobó su manifiesto interno
  0.4.4: el primer build incremental había conservado un manifiesto 0.4.0 en
  `obj`, aunque compilara las clases nuevas.
- TUI: formato, `go vet` y tests de todos los paquetes, incluidos los golden
  y una prueba de host que comprueba la publicación del porqué y la ausencia
  de otra invocación para consultarlo.
- ShellCheck, comprobación del producto, 62 tests de contratos/reparto y
  `git diff --check` correctos.

## Intento de prueba visual y perfil siguiente (7 de noviembre)

Con autorización de Ezequiel para probar mientras estaba fuera de la computadora,
se preparó una tercera instancia de IntelliJ 2026.1 con config, cachés, logs,
plugin 0.5.4 y un repositorio sintético propios. No se reemplazó el plugin de
las instancias abiertas ni se usó su sandbox de revisión.

La instancia llegó al diálogo de confianza del proyecto, que incluía la opción
de agregar exclusiones de Microsoft Defender. No se confirmó ese diálogo ni
se cambiaron ajustes de seguridad. Se cerró sólo el proceso nuevo, después de
comprobar su ruta de argumentos; las dos instancias originales siguieron
abiertas. Ese primer intento no llegó a ejecutar clics del plugin. La prueba
posterior, autorizada expresamente por Ezequiel, se registra en la sección
siguiente; no debe confundirse con este intento ni con la prueba de 0.5.3.

Se ejecutó un perfil adicional de CLI en Windows nativo sobre ese fixture:

| Operación | Tiempo observado | Procesos Git hijos |
|---|---:|---:|
| Next/Prev con guard y respuesta completa | Mediana 2,01 s, cuatro muestras | 10 por operación |
| Cancel con guard (`abort`) | 3,42 s, una muestra | 30 |

La navegación conservó cursor, prosa y equivalencia con status. Cancel restauró
main, eliminó la rama de review, devolvió los bytes originales y dejó un status
limpio. Son operaciones reales de la CLI; no incluyen el guardado ni el refresco
de un IDE. La traza agrega overhead y una muestra de Cancel no caracteriza
todos los modos o repositorios.

Trace2 registra una mediana de 0,33 s de ejecución acumulada de los diez Git
hijos de navegación. Ese tiempo no incluye toda la creación de procesos ni los
comandos ajenos a Git: la diferencia con los 2,01 s **no** es una medición
exclusiva de CPU o de fork. Sí justifica priorizar procesos y subshells antes
de agregar cachés de contenido o quitar guardas. La navegación resuelve el
gitdir dos veces, relativo y absoluto; su consolidación es un candidato acotado.

Para el siguiente cambio conviene perfilar y reunir las lecturas de metadata
de Cancel y los cierres que compartan ese patrón, dentro de cada invocación y
con validación anterior a sus efectos. En la muestra de Cancel, el gitdir
absoluto se consulta cuatro veces y cada una de las tres claves de custodia
de Comments, tres veces. Hay que distinguir los datos reutilizables de las
relecturas que protegen un cambio de custodia antes de eliminarlas.
Después, reducir las consultas duplicadas
de arranque y separar la validez de la versión de CLI de la generación del
estado del panel. Son propuestas: este intento no modifica comportamiento.

Los scripts, trazas, resultados y logs están en
`navigation-why/native-ide-054/` de los artefactos del chat. No se hizo commit,
push, publicación ni instalación sobre los IDE del usuario.

## Prueba real de IntelliJ 0.5.4, completada con autorización

Ezequiel autorizó continuar. Se confió únicamente en el repositorio sintético,
con la exclusión de Defender y la confianza de la carpeta entera desmarcadas.
Para editar el Local de ese fixture se habilitó sólo ese archivo hasta cerrar
el IDE. La instancia conserva config, system, plugin y logs separados. Hubo
que incluir Git Bash en el PATH del proceso nuevo, igual que en el flujo
documentado de `runIde`; el primer arranque desde PowerShell no encontraba `sh`.

Se probaron los controles de la interfaz, con el ZIP 0.5.4 y la CLI 0.10.4:

| Operación desde el panel | CLI principal | Hasta liberar el lock de acciones |
|---|---:|---:|
| Next | 1,945 s | 2,176 s |
| Prev | 2,196 s | 2,439 s |
| Cancel, editor limpio | 2,894 s | 4,773 s |
| Save for Later, Local sin guardar | 9,601 s | 13,519 s |

Next mostró `b.txt` en 2/3 con su prosa completa, incluido Unicode, y Prev
devolvió `a.txt` en 1/3 con su propia explicación. El log entre esas acciones
no contiene otro status ni `status --why`: Comments se consulta después del
estado principal, fuera del lock.

Cancel limpio no ejecutó `comments status --porcelain --all`. El panel pasó a
sin review; Git confirmó main, ausencia de la rama de review, archivos con sus
bytes originales y working tree limpio. Aun con ese ahorro, Cancel sigue
costando casi cinco segundos en este caso: 2,9 s son el verbo y unos 1,9 s,
la actualización del repositorio y las lecturas posteriores del panel.

Para el caso sucio se creó un comentario Local del fixture y se editó desde su
botón de archivo. Se observó el texto nuevo en el editor y se comprobó que
todavía no existía en disco inmediatamente antes de confirmar Save for Later.
La protección de archivos fuera del proyecto interceptó el primer pegado; se
deshizo y se repitió la edición antes de realizar esa comprobación. El flujo
sí consultó el inventario de custodia, que tardó 1,809 s. Al terminar, se
contrastaron los bytes: prosa original conservada y texto nuevo persistido.
La rama guardada conservó la sesión propietaria, main quedó activo y el
working tree limpio. El panel mostró la review guardada con Continue.

El guardado también expuso trabajo adicional: el cambio del documento disparó
una consulta de versión, status, porqué y Comments mientras el `save` de la
CLI seguía ejecutándose. La mutación ya realiza su refresco posterior. Conviene
coordinar/coalescer esas señales con el lock, conservando los cambios externos,
y perfilar el costo propio de custodia y metadata del verbo antes de atribuir
todo el tiempo al cliente. No se cambió ese comportamiento durante la prueba.

Son una muestra por acción, en un fixture de ruta profunda y con los dos IDE
del usuario abiertos. La duración del lock excluye el tiempo de decidir en el
modal y no instrumenta el pintado del EDT. No demuestra una regresión de Save
frente a otra versión: falta una comparación controlada para ese escenario.

Se cerró limpiamente sólo la instancia de prueba. Las dos originales siguieron
abiertas y conservaron su plugin. El fixture quedó pausado, con el Local de
prueba, para reproducir el caso. No hay cambios nuevos de código del producto,
commit ni push. `ui-summary.json`, `ui-plugin-calls.log`, `ui-cancel-log.txt`,
`ui-save-log.txt` y las aserciones de Git se guardan en
`navigation-why/native-ide-054/` de los artefactos del chat.

## Integración posterior

Ezequiel autorizó commitear los cambios locales después de revisar las
mediciones. La CLI y los clientes quedaron en `4a98ddd` y `8ba00fc` sobre main,
respectivamente, sin push ni publicación. El diagnóstico siguiente, con la
coordinación de watchers, el benchmark de cierres y los límites de la prueba
real de IntelliJ, está en
`specs/rendimiento/2026-11-07-watchers-y-cierres.md`.
