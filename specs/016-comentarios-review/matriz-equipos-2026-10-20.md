# Matriz de flujos de equipo y comentarios

Fecha: 2026-10-20. Alcance: CLI actual del workspace, con Shared del repositorio
como fuente para la próxima review y Local privado e independiente.

## Qué demuestra cada nivel

- **Integración CLI:** procesos reales, repositorios independientes y remoto
  bare. Sólo cruzan commits; nunca se copia el gitdir privado de otra persona.
  Los conflictos se producen con Git y se resuelven explícitamente.
- **Contrato/host:** modelo e invocación de los clientes. No demuestra interacción
  con un editor nativo ni conflictos de buffers sin guardar.
- **Interfaz:** las pruebas Electron existentes recorren comandos y paneles de
  VS Code. Eso no acredita el mismo recorrido visual en los otros tres clientes.

Los nuevos casos no prueban todas las combinaciones posibles. Whole, step y walk
se cruzan con concurrencia, Save/Continue y rebase; las variantes de transferencia
e historia usan whole. El flujo secuencial existente cruza los tres modos con
fast-forward, merge y squash.

## Casos comprobados

Todos los archivos de la tabla viven en `tests/`, salvo las rutas explícitas de
clientes. Las expectativas incluyen estado real de Git y documentos, además del
exit code y el diagnóstico en los rechazos.

| Flujo | Invariante comprobada | Evidencia automatizada |
|---|---|---|
| Autor → Alice → autor responde → Bob → integración → Carol | Shared pasa por el remoto; Local no llega a commits; conserva referencias históricas; PRs posteriores no heredan la discusión integrada. | `comments-team-flow.bats`, nueve combinaciones de modo e integración. |
| Dos revisores empiezan sin Shared | Conflicto add/add real; resolución explícita conserva ambos bloques y una identidad elegida. | `comments-team-flow.bats`, `concurrent reviewers`. |
| Tres revisores empiezan con el mismo Shared existente | Cada entrega conserva discusión original, su observación y su corrección. Integrar ABC, CBA o BAC conserva el orden elegido y el contenido de todos. | **Nuevo:** `comments-team-collaboration.bats`, cinco casos en los tres modos. |
| Los tres agregan el mismo número visible | Las entradas siguen siendo distinguibles por ordinal físico; diff usa sus OID originales; renumber sólo reasigna números. | Los mismos cinco casos, con números 3 repetidos y comparación de recetas antes/después de integrar. |
| Un push queda desactualizado | El rechazo conserva HEAD, índice y Local; fetch + merge explícito + push permite que otro clon vea ambos aportes. | **Nuevo:** `comments-team-collaboration.bats`, `rejected stale push`. |
| Bob guarda la review y Alice publica mientras tanto | Continue recupera exactamente la preparación y el tip original. `--onto-source` rechaza la rama avanzada; Undo recupera el intento y Finish entrega en fixes sobre el tip revisado. | **Nuevo:** `comments-team-collaboration.bats`, tres modos. |
| Alice borra una entrada mientras Bob responde sobre la vieja | Git pide resolución; se prueban ambos resultados elegidos. La siguiente review respeta la eliminación o la respuesta sin resucitar la alternativa. | **Nuevo:** `comments-team-collaboration.bats`, `explicit deletion` y `explicit reply`. |
| Shared está en conflicto sin resolver | Status conserva presencia y marca revisión ilegible, sin conteo. Entries rechaza sin mutar. Después de resolver y stagear, el siguiente lector puede usar los diffs. | **Nuevo y corregido:** `comments-team-collaboration.bats`, `unresolved shared merge`. |
| Cherry-pick sólo de comentarios, sólo de código o de ambos | Se transfiere exactamente lo elegido; los comentarios históricos conservan sus objetos originales; Local no viaja. | **Nuevo:** `comments-team-history-transfer.bats`, tres casos. |
| El autor renombra, borra o reescribe el archivo comentado | El diff de la observación sigue mostrando el blob y el path capturados, sin sustituirlos por el código actual ni escribir estado. | **Nuevo:** `comments-team-history-transfer.bats`, tres casos. |
| Un clon shallow recibe el Shared público | Lee la prosa sin estado privado; el diff histórico faltante devuelve 5, sin fetch, salida parcial ni sustitución por HEAD. | **Nuevo:** `comments-team-history-transfer.bats`, `shallow checkout`; complementa `comments-history-missing.bats`. |
| El autor rebasa y hace force-push durante una review activa | La sesión conserva tip, contexto, guard y prosa. Finish entrega sobre el tip revisado; no cambia silenciosamente la nueva rama del autor. | **Nuevo:** `comments-team-history-transfer.bats`, tres modos. |
| El revisor vuelve después de un rebase | La continuación incompatible exige elegir contexto; no descarta ninguna versión. | `comments-team-flow.bats`, `rebased author replies`. |
| Se borra y recrea el mismo nombre de rama | Tras ff/merge empieza un contexto nuevo. Tras squash, la falta de prueba de ascendencia exige elección; `--new-context` no incorpora el Local anterior. El resultado viejo se conserva. | **Nuevo:** `comments-team-branch-reuse.bats`, tres estrategias y remoto real. |
| Dos worktrees enlazados trabajan a la vez | Gitdir y preparación distintos. Guardar uno y cancelar el otro no borra ni altera la prosa ajena. Continue/Finish/Undo/Cancel preservan custodia. | **Nuevo:** `comments-team-history-transfer.bats`, `two real linked worktrees`; complementa guards de `comments-custody*.bats`. |
| Un clon entrega Shared con configuración CRLF o input | Una conversión de checkout válida no es prosa concurrente. El índice recibe el blob exacto de la preparación; Undo la recupera; Cancel deja limpio el repo. | **Nuevo y corregido:** `comments-team-history-transfer.bats`, dos casos. |
| Atributos o filtros cambian la comparación | `-text` y ausencia de conversión mantienen comparación estricta; no se ignoran espacios, CR dentro de la prosa, sufijos con NUL ni cambios de salto final. No se ejecuta clean. Una escritura después de comparar no se adopta como baseline ni se sobrescribe. | **Nuevo:** diez casos de `comments-delivery-eol.bats`. |
| Se mata el proceso después de stagear y antes de publicar | Código y ambas prosas sobreviven. No se roba el lock. Tras retirar explícitamente el lock del proceso muerto, Undo/Finish recupera una sola entrega y otro clon la lee. | **Nuevo:** `comments-team-restart.bats`, SIGKILL real y barrera FIFO. |
| Falla crear/copiar/renombrar/publicar | Queda preparación recuperable y el reintento entrega sólo prosa; no vuelve a extraer código. | `comments-delivery-io.bats`, `comments-finish-partial.bats`, `comments-finish-resume.bats`. |
| Un editor antiguo cambia preparación, destino o índice durante Finish | La entrega usa un blob inmutable; la divergencia conserva prosa pendiente y Undo rechaza sobrescritura de una preparación editada. | `comments-delivery-race.bats`, `comments-concurrency.bats`, `comments-finish-undo.bats`. |
| Shared del repo y Local guardado comparten contexto | El panel consulta Shared del repo y Local de la sesión guardada, conserva permisos y no recupera un Local anterior. | `comments-saved-repository.bats`, `comments-repository-shared.bats`. |
| Se copia un contexto conocido a una historia distinta | Exige el selector existente. Start a new review conserva Shared y separa Local; continuar recupera Local. Renombrar con ascendencia compatible y clonar sin antecedentes privados no inventa una ambigüedad. | **Nuevo y corregido:** seis casos de `comments-team-context-choice.bats`, incluidos BOM, CRLF, ejemplos y EOF sin salto final. |
| Se quiere reproducir el selector y un merge a mano | Cuatro carpetas independientes dejan dos elecciones, un renombre compatible y a Bob desactualizado frente a Alice; las instrucciones llevan al conflicto real sin publicar Local. | **Nuevo:** `comments-sandbox-team.bats` verifica el generador real de `tests/sandbox.sh`. |
| Documento ausente, vacío, roto o sin historia | No se intercambian ausencia y vacío; un fallo de lectura no habilita escritura; prosa y código histórico tienen diagnósticos independientes. | `comments-status.bats`, `comments-zero-entries.bats`, `comments-malformed-lifecycle.bats`, `comments-history-*.bats`. |

## Límites y criterio elegido

1. **Identificador copiado a otro PR.** El usuario eligió pedir una elección
   cuando ya se conoce el contexto y la historia resulta incompatible. Se
   reutiliza el selector existente de los cuatro clientes al agregar comentarios,
   sin controles nuevos. Start a new review conserva Shared entrante con otra identidad
   y separa Local; continuar recupera Local anterior. Un renombre compatible no
   pide elección. En un clon nuevo no hay antecedentes privados para reconocer
   una copia accidental: se importa Shared sin inventar una incompatibilidad.
2. **Conflicto de significado.** La suite acredita las dos resoluciones de
   borrar frente a responder; no elige por el equipo ni fusiona semánticamente
   Markdown. Tres revisores también pueden producir un merge textual limpio
   que requiera revisión humana por su significado.
3. **Caída completa.** SIGKILL se prueba en una frontera real de publicación;
   otras fronteras tienen fallos de I/O y carreras controladas. No hay una
   campaña de apagado de sistema/fsync ni recuperación automática de locks.
4. **Buffers sin guardar y editores nativos.** La CLI sólo observa disco. Existen
   pruebas de custodia y composición de clientes, pero falta una campaña nativa
   conjunta en JetBrains, Visual Studio y la TUI con buffers antiguos abiertos.
5. **Historia eliminada por el remoto.** El shallow y los objetos ausentes están
   cubiertos. No se promete poder abrir código que ningún clon conserva: la
   prosa sigue siendo legible y el diff informa la ausencia.

Los flujos seriales de clientes ya tienen pruebas en
`vscode-extension/test/integration/comments-team.spec.ts`,
`jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/host/CommentsTeamIT.kt`,
`visualstudio-extension/tests/GitReview.Host.Tests/CommentsTeamIT.cs` y
`tui/internal/host/comments_team_test.go`. No se volvieron a ejecutar en esta
pasada: las correcciones son de CLI y no cambiaron el protocolo ni la UI.

## Ejecución y resultado

Se agregaron **46 pruebas**: 12 de colaboración, 13 de transferencia/historia,
3 de reutilización de rama, 1 de interrupción real, 10 de comparación de EOL,
6 de elección de contexto y 1 del generador de sandbox.
`tests/helpers/comments-team.bash` centraliza únicamente preparación y oráculos
de integración; no reemplaza reconciliación ni invocaciones del producto.

La suite de comentarios completa ejecutó **421 casos, todos correctos, sin
omisiones**, en Linux dentro de Docker, con Git 2.43.0 y Bats 1.13.0. El SHA-256
de `bin/git-review-lib.sh` probado es
`e00e5f8ed0c1115329196e00f66aa34939e111886ca65d5dda37da000b22fd8f`.
ShellCheck 0.10.0 pasa para la biblioteca y todos los archivos nuevos; pasan
también el contrato de clientes, sus 46 pruebas y los dos gates de nombres ASCII.
Las diez pruebas de EOL y las seis del selector pasan además con `original-awk`,
cuya lectura de NUL requiere el guard binario. Una pasada anterior pasó los otros
28 casos nuevos más nueve de EOL sobre la revisión anterior a la última carrera.
Los 144 casos generales de Start, Finish/Undo, Save y Clean también pasaron en
esta auditoría; el último cambio del guard del destino se verificó después con
la familia completa de comentarios.
El generador de sandbox también se repitió con `core.autocrlf=true` global: el
clon fija su conversión durante el checkout, antes de guardar config local. Se
crearon además los casos nativos de Windows en
`C:/Users/ezevi_30ey2ks/.cache/git-review-sandbox-comments-20261020/comments-team-ready/`,
con `LEEME.md` y cuatro carpetas para abrir individualmente en el cliente.

Desde la raíz se pueden repetir los casos agregados:

```sh
./tests/run-docker.sh --print-output-on-failure \
  tests/comments-team-collaboration.bats \
  tests/comments-team-history-transfer.bats \
  tests/comments-team-branch-reuse.bats \
  tests/comments-team-restart.bats \
  tests/comments-delivery-eol.bats \
  tests/comments-team-context-choice.bats \
  tests/comments-sandbox-team.bats
```

Y la familia completa:

```sh
./tests/run-docker.sh --print-output-on-failure tests/comments*.bats
```

La pasada general previa y sus dos fallos ajenos por encabezados `[Unreleased]`
se registran en `auditoria-flujo-2026-10-20.md`. No se presenta esa pasada como una
ejecución general nueva sobre estos cambios.
