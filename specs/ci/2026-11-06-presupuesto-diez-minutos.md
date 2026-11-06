# Presupuesto de diez minutos por job

## Objetivo y alcance

Pedido de Ezequiel del 6 de noviembre de 2026: que cada job del CI habitual
tarde aproximadamente diez minutos como máximo. Se planifica para ocho, con
margen de dos minutos. El reporte espera que terminen las pruebas: exceder el
presupuesto falla el control, sin cancelar tests ni reducir cobertura.
La cola queda fuera de la ejecución y puede agregar tandas. No se publican
versiones ni se cambian los workflows de publicación en este trabajo.

## Referencia medida

[CI 42140635158](https://github.com/EzeVillo/git-review-workflow/actions/runs/42140635158),
commit `966ca74`, terminó con 34/34 jobs correctos. Bats tardó 14:45 en Linux,
59:11 en macOS y 20:48–32:45 en sus doce grupos Windows. VS Code tardó 3:16 en
Linux, 13:02 en macOS y 12:17–20:40 en sus tres grupos Windows.
Los otros jobs quedaron por debajo de siete minutos.

Se descargaron los logs y los pasos originales de los diecinueve jobs de Bats
e integración. Los casos Bats se contrastaron por nombre, ordinal y archivo
contra el reparto anterior; no se usó el nombre solo, porque puede repetirse
entre archivos. Los dos casos omitidos en Unix no publicaron duración. Para
VS Code se midieron los intervalos entre resultados dentro de cada suite,
incluida la preparación entre casos, y se contrastaron sus 121 resultados.
El costo restante del paso se distribuyó proporcionalmente entre los casos.
Es una estimación para repartir, no una promesa de duración nativa nueva.

El perfil versionado registra archivos para cada sistema y pesos por caso
sólo en los archivos auditados que requieren división. Bats conserva su
preparación por caso; sus setup_file sólo comprueban versión, cuando existen.
Los dos archivos Mocha auditados son `comments-panel.spec.ts` (beforeEach y
afterEach) y `comments-team.spec.ts` (preparación propia y finally por caso).

## Reparto planificado

| Suite | Sistema | Grupos | Mayor estimación por job |
|---|---|---:|---:|
| Bats | Linux | 3 | 5,84 min |
| Bats | macOS | 10 | 6,84 min |
| Bats | Windows | 64 | 6,80 min |
| VS Code | Linux | 1 | 4,57 min |
| VS Code | macOS | 3 | 6,61 min |
| VS Code | Windows | 10 | 6,32 min |

La preparación fija estimada es de un minuto en Bats y un minuto y medio en
VS Code. Los archivos nuevos reciben cinco minutos provisionales. Los casos
nuevos de un archivo dividido reciben el costo promedio medido de ese archivo.
La selección usa los nombres actuales de Bats y los tests que Mocha cargó,
no una lista cerrada que pudiera omitir un test agregado posteriormente.
En Windows se agregan quince segundos por cada archivo parcial distinto dentro
de un grupo; elegir otro caso del mismo archivo reutiliza esa preparación.

Los filtros Bats están anclados y escapados y se pasan como argumentos, nunca
como código shell. Conservan las barras de la declaración original: Bats
filtra antes de que su formatter quite las barras de las comillas escapadas.
Se contrasta el plan TAP de la ejecución con la cantidad esperada de cada
selección parcial; un desajuste falla visiblemente en lugar de perder un caso.
La salida sigue en vivo y se preserva el exit code del productor sin pipefail.
Cada archivo seleccionado se ejecuta por separado para
mantener pequeño el argv de Windows. Un fallo conserva el estado de error y
deja ejecutar los archivos restantes. Mocha conserva los tests y hooks en su
árbol original y selecciona mediante grep. El diagnóstico MOCHA_FILE/MOCHA_GREP
y la ejecución local completa siguen disponibles.

## Validación

Validación local en contenedor:

- Los 64 grupos Bats ejecutaron la selección exacta de Windows, incluidos los
  filtros y sus comprobaciones de cantidad. Se contrastaron los logs contra
  los nombres y archivos actuales: 1.507 casos físicos, sin faltantes ni
  duplicados, con las omisiones propias de ejecutar sobre Linux.
- Los diez grupos VS Code pasaron con 14, 16, 21, 6, 4, 6, 10, 21, 5 y 18 tests:
  121 en total, sin duplicados y con todos los casos cargados cubiertos.
  Compilación, TypeScript y 532 unitarias correctas; una omisión preexistente.
- Quince tests de selección/presupuesto y 52 del contrato correctos con
  Node 20. El control absoluto rechaza los dieciocho jobs de más de diez
  minutos de la corrida original, aunque aquella hubiera terminado en verde.
- Actionlint, ShellCheck del runner y del wrapper de lint, contrato de
  producto, logos y `git diff --check` correctos. Las seis planificaciones
  quedan por debajo de ocho minutos.

La comprobación física detectó que el primer filtro de comillas escapadas
omitía un caso: se corrigió la distinción entre nombre mostrado y declaración
original y se repitieron todos los grupos con el guard de cantidad real.
La integración detectó una carrera en el test de copiar Local: abrir y editar
el documento podía iniciar un refresco, y el clic usaba una fila anterior a su
fase de comentarios. El test espera ahora el estado completo y busca la fila
actual por ruta; conserva las aserciones del editor sin guardar, los bytes y
Git. El grupo afectado pasó dos veces con el ajuste.

Una repetición local concurrente de dos editores agotó la memoria compartida
del contenedor. Se descartó esa corrida del conteo y se validó en serie con
`--shm-size=1g`; cada job nativo inicia un solo editor en su propio runner.

## Calibración nativa

La [primera corrida de calibración](https://github.com/EzeVillo/git-review-workflow/actions/runs/42247141447),
commit `3201d6d`, mostró grupos Windows de 10:02 (VS Code), 10:33 y 11:51
(Bats), además de un fallo de selección de texto del editor. Los logs de Bats
separan el tiempo de cada caso del intervalo hasta el siguiente archivo:
`--count` repetía el procesamiento del archivo completo, incluso cuando sólo
se elegía un caso. Era costo del runner de tests, no trabajo útil del caso.

Se conservó el guard de cobertura contrastando el plan TAP de la misma
ejecución, con salida en vivo mediante tee y propagación explícita del código
de salida. El lector acepta LF/CRLF; los tests negativos comprueban tanto un
productor fallido detrás de tee como una cantidad equivocada con exit 0.
El plan incorpora quince segundos por archivo parcial distinto, reutiliza
ese costo cuando el grupo ya lo cargó y deja 64 grupos Bats y diez de VS Code.

El test de selección del diff enfoca explícitamente el lado original o
modificado antes de asignar y esperar la selección, para que el foco inicial
del host no la reemplace por una selección vacía al abrir el panel.
Los 64 y diez grupos de la versión calibrada se ejecutaron de nuevo en
contenedor; sus logs vuelven a cubrir exactamente 1.507 y 121 casos.

## Auditoría física nativa y stdin

La auditoría de los logs de Linux en la
[corrida calibrada](https://github.com/EzeVillo/git-review-workflow/actions/runs/42252306481)
encontró 1.392 de los 1.507 casos esperados, aunque los tres jobs habían pasado.
El segundo grupo procesó 40 de sus 44 archivos: una prueba que leía stdin
podía consumir las líneas pendientes del manifest del bucle. Faltaron los
archivos walkthrough-draft-progress, walkthrough-draft-read, walkthrough-guide
y walkthrough-update: 115 casos en total.

Se reprodujo primero con un Bats simulado que consume stdin: el test falló al
encontrar sólo el primer archivo procesado. El runner ahora entrega EOF al
proceso Bats y comprueba además la cantidad total de archivos procesados contra
el manifest. La regresión conserva la lectura de stdin y pasa con el arreglo,
tanto para errores del productor como para cantidades TAP equivocadas.

Se ejecutaron en contenedor las selecciones exactas de los tres sistemas:
3 grupos Linux, 10 macOS y 64 Windows. Cada reparto volvió a cubrir los 1.507
casos físicos una sola vez, sin faltantes ni duplicados. Los quince tests del
reparto y presupuesto, ShellCheck y diff check también pasaron con la
corrección. El cambio no modifica los parámetros ni el límite de duración.

Falta registrar la corrida nativa del runner con stdin aislado.
