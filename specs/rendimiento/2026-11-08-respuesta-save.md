# Save devuelve estado sólo por opción explícita

## Decisión y alcance

Ezequiel autorizó continuar las mejoras manteniendo POSIX. Una migración de
lenguaje no tiene una mejora demostrada que justifique su riesgo. Este corte
agrupa la lectura final de Save y la reutiliza en los cuatro clientes.
No cambia el algoritmo de guardado, las escrituras de custodia ni Continue.

`git review save` conserva salida humana y no calcula el informe del panel.
`save --porcelain` devuelve un sobre con el resultado de status fuera de review,
inventario y configuración. Status activo anuncia `capability save-state`;
los clientes comprueban la capacidad y un guard antes de pedir la opción.

## Implementación

List y config comparten sus emisores con Save. Cada llamada se aísla en un
subshell; sus variables no contaminan la mutación. Los emisores conservan
`set -e` también cuando se ejecutan desde una sustitución de comandos.
La lectura final carga metadata nueva después de borrar la rama activa,
comparte rama/config/gitdir entre informes y libera antes el lock de Comments.
No invoca otros verbos ni construye otra implementación de los informes.

El sobre termina con `save-state complete`. Los clientes comprueban su forma,
reutilizan los parsers actuales y publican el estado con sus guardas de
generación. Comments completa aparte. Un sobre ausente o inválido provoca una
lectura normal sin repetir Save. Un fallo posterior de informe conserva el
éxito del guardado y omite el final; los errores de la mutación conservan sus
códigos. Las CLI anteriores mantienen el flujo anterior por falta de capacidad.

Contrato: `contracts/review-state-guard.md`, «Respuesta opcional de Save».
La referencia CLI y los changelogs se actualizan. Versiones locales:
CLI 0.10.7, IntelliJ/VS Code 0.5.6, Visual Studio 0.4.6 y TUI 0.2.5.

## Verificación

- Pruebas dirigidas en whole, step, walk y compare: igualdad byte por byte de
  list/config, conservación de ediciones y preparaciones Local/Shared, mismo
  archivo de sesión al retomar, salida humana y rechazo de identidad obsoleta.
- Fallo de informe posterior al guardado: rama guardada recuperable, main limpio,
  código 0 y sobre incompleto. También comprobado nativamente en Windows.
- 34 casos dirigidos con Bash 3.2 y comprobación de sintaxis de bin.
- 397 pruebas IntelliJ, buildPlugin y verifyPluginStructure. ZIP local 0.5.6.
- 552 unitarios VS Code, un pendiente previo, TypeScript y 123 integraciones
  con el extension host real. La primera integración perdió su renderer con
  código 133; la repetición con memoria compartida de 1 GiB terminó con código 0.
- Visual Studio: 424 Domain, 90 Host y build VSIX nativo con MSBuild/net472.
- Go: formato, vet, todas las pruebas y golden. Contrato de producto y las 62
  comprobaciones de contratos/reparto (un skip habitual fuera del runner de CI).
- ShellCheck de todos los scripts que valida CI y diff sin errores.

La primera suite Bats completa encontró una expectativa exacta de status que
no incluía la capacidad nueva. Se actualizó la expectativa y pasó en Bash 3.2.
La repetición completa de 1547 casos terminó con código 0, con los skips
habituales (incluidos los instaladores PowerShell que requieren pwsh).

Logs, snapshots y paquetes de esta validación:
`C:/Users/ezevi_30ey2ks/AppData/Local/Temp/git-review-save-state/`.

## Comparación en Windows nativo

Se comparó el recorrido anterior de IntelliJ (Save con guard más
version/status/list/config) con Save con guard y `--porcelain`. Dos operaciones
de calentamiento y cuatro muestras alternadas por variante, Trace2 en ambas,
mismo fixture y suites detenidas. Guard, preparación, Continue, aserciones e
inventario de buffers quedaron fuera del intervalo. Se comprobaron los informes
finales byte por byte, prosa, sesión, diff y cursor.

Se repitió la comparación después de renombrar una variable interna del
emisor que activaba un aviso de ShellCheck en Compare. La primera dio
8,41 → 7,18 s; la tabla corresponde al código final, con sus 34 casos
dirigidos repetidos y el lint completo aprobado.

| Recorrido | Mediana | Procesos Git |
| --- | ---: | ---: |
| Save 0.10.6 + version/status/list/config | 8.32 s | 67 |
| Save 0.10.7 --porcelain | 7.15 s | 55 |

La reducción es 1.17 s (14.1 %). El tiempo del verbo nuevo incluye calcular los
informes que antes corrían después; comparar sólo la duración de ambos verbos
no compara el mismo trabajo. El emisor compartido conserva los bytes de ambos
informes y el fixture terminó pausado, recuperable y con su prosa completa.
No se midió un nuevo tiempo total dentro de IntelliJ; el inventario previo de
buffers y el trabajo del host permanecen fuera. Tampoco se da por resuelto el
costo de Save ni se atribuye este porcentaje a otros repositorios o clientes.

El siguiente corte puede acotar el inventario previo de documentos a custodia
y rutas y agrupar los campos de manifest dentro de cada preflight fresco.
Eso queda pendiente; no se cambió en este commit.

Datos, baseline, script y Trace2:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/save-state/`.
`summary.json` registra el fixture, método, muestras, commit anterior y SHA-256
del candidato. Sin push, tags ni publicación. Las ventanas originales y sus
plugins permanecen intactos. ZIP de IntelliJ 0.5.6 disponible en
`jetbrains-plugin/build/distributions/git-review-workflow-0.5.6.zip`.
