# Auditoría de flujos de comentarios — 19 de octubre de 2026

Se probaron los cambios del working tree, incluidos los archivos nuevos, contra
la superficie de las últimas versiones publicadas. La auditoría encontró y
corrigió dos problemas de identidad de sesión y un diagnóstico de conflicto que
persistía después de resolverlo. Hay evidencia ejecutada de la CLI, los cuatro
adaptadores, VS Code en Electron y la TUI en un terminal real con pseudoterminal.
La aceptación interactiva completa de IntelliJ y Visual Studio sigue pendiente.

## Punto de comparación

`gh release list` y `git ls-remote --tags` confirmaron estos releases. No se
confundieron las versiones candidatas locales con versiones publicadas.

| Pieza | Último release | Candidato probado |
|---|---|---|
| CLI | `v0.9.0` | 0.10.0 |
| VS Code | `vscode-v0.4.0` | 0.5.0 |
| JetBrains | `jetbrains-v0.4.0` | 0.5.0 |
| Visual Studio | `visualstudio-v0.3.0` | 0.4.0 |
| TUI | `tui-v0.1.0` | 0.2.0 |

Se ejecutó el código candidato, no las instalaciones personales de esos clientes.
El checkout ya tenía cambios extensos antes de esta auditoría; se conservaron.
No se crearon commits ni tags ni se publicó o instaló ningún cliente. Todos los
push de las historias de prueba fueron a remotos bare locales descartables.

## Historias nuevas reproducibles

`tests/comments-team-flow.bats` aporta catorce casos. Nueve combinan
whole/step/walk con fast-forward/merge commit/squash y usan cuatro clones con
identidades distintas:

1. El autor crea el PR y otra rama desde la base antes del merge.
2. Alice captura Local y Shared, pausa, continúa, modifica código y termina en
   `review-fixes/`. Se comprueba que sólo el código queda staged y que Shared
   todavía requiere un commit explícito.
3. El autor integra la rama de feedback y responde editando el Markdown en otro
   commit. Bob continúa desde su clon sin recibir el Local de Alice, abre el
   histórico original y añade seguimiento.
4. El autor integra el seguimiento, hace merge a la base y crea otra rama desde
   la base actualizada. Carol revisa las ramas nacidas antes y después: ninguna
   adopta el contexto del PR anterior.

Los otros cinco casos cubren aceptar la respuesta del autor y terminar, una base
local atrasada, dos revisores concurrentes con un conflicto Git real de tipo
add/add, un rebase con force-push y el avance de la base durante una sesión ya
materializada. Se verifican contenido, ramas, referencias, índice, revisiones,
guards y ausencia de prosa privada en los commits; no sólo mensajes de éxito.

El conflicto entre entregas concurrentes se resuelve conservando ambos bloques
y eligiendo explícitamente un contexto de documento. Después, otro clon lee las
dos preguntas y las renumera. Ante el rebase, una captura sin elección explícita
falla y la instantánea completa de Git y comentarios permanece idéntica.

Los clientes comparten `tests/helpers/comments-team-history.sh`, que prepara
historia usando únicamente Git. Las operaciones del producto pasan por cada
invocador real: tres estrategias de merge por adaptador. C# ejercita además
`CommentsActions` con guards y stdin. Kotlin ejercita `CliInvoker` y los argv del
dominio; no afirma haber ejecutado `CommentsActions` dentro de un IDE.

VS Code añade tres recorridos en el extension host: captura con selección,
Local/Shared, Finish desde el comando real del cliente, respuesta desde otro
clon, lectura del diff histórico, aceptación de la respuesta y nueva revisión
después del merge. Sólo se guiona la elección de destino del QuickPick.

La TUI se ejecutó también como binario en un PTY de 120×40 con vigilancia real:
captura Local → Shared → Local mediante teclado, comprobación de counts 2/1,
Finish, integración de la respuesta por otro clon, merge, arranque de otro
proceso sobre una rama nueva con base local atrasada, captura Shared y Finish.
La entrega nueva no contiene la conversación heredada. El script y las salidas
ANSI están en los artefactos locales de la auditoría.

## Defectos encontrados y corregidos

### Una base local atrasada podía reutilizar el contexto del PR anterior

Start resolvía correctamente la base remota, pero comments volvía a calcular su
merge-base prefiriendo la rama local. Después de un merge ajeno, un revisor que
no había hecho pull podía abrir una rama nueva y adoptar el marcador heredado.
Start ahora entrega a la inicialización de comentarios la referencia que
realmente resolvió. La regresión falla antes de la corrección y pasa después.

### El avance de la base invalidaba el guard de una sesión materializada

Las sesiones provisionales conservaban el merge-base de su manifest; las ya
materializadas volvían a derivarlo desde referencias móviles. Integrar la base
podía cambiar el guard aunque la sesión y sus documentos no hubieran cambiado.
Ambas clases de sesión conservan ahora su base completa original. Se verificó
en rojo y verde que una captura con el guard anterior sigue siendo válida.

### Aceptar la respuesta entrante dejaba un conflicto ya resuelto

Si el revisor copiaba deliberadamente la versión entrante a Shared y terminaba,
el cierre sin una entrega nueva no eliminaba `source-conflict`. Se publicaba el
documento correcto junto a un diagnóstico obsoleto. Ese camino ahora elimina el
marcador resuelto. El caso se comprobó en rojo y verde y se repitió a través de
los adaptadores.

También se corrigió el runner de unitarias de VS Code: el strip de TypeScript
de Node 22 interfería con ts-node y rechazaba una parameter property del fixture.
Mocha desactiva ese strip y conserva su cargador existente. ShellCheck detectó
SC2094 en una lectura doble del snapshot: se documentó y suprimió únicamente ese
falso positivo; la salida sigue yendo a un candidato separado.

## Evidencia ejecutada

Los logs están en `dist/audit-20261019/`, ignorado por Git. Las ejecuciones de
Linux se hicieron en copias sobre filesystem Linux; las compilaciones WPF/VSIX,
en Windows. No se reutilizó una instalación global de la CLI para los clientes.

| Comprobación | Resultado y alcance |
|---|---|
| CLI completa corregida | 1.385 casos en cuatro tandas, exit 0: 1.380 ejecutados y cinco omitidos |
| Historia de equipo final | 14 casos, incluyendo los tres añadidos después de esa tanda completa |
| Omisiones reproducibles en Linux | npm pack/install, archivo ilegible y stdin con PTY pasan en otro contenedor como usuario sin privilegios |
| Total CLI cubierto | 1.388 casos únicos; quedan dos omisiones de User PATH de Windows |
| VS Code unitarias | 505 aprobadas, un pending preexistente; compilación y tipos aprobados |
| VS Code Electron completo final | 108 aprobadas, exit 0; incluye los tres recorridos nuevos |
| JetBrains completo | 366 tests, sin errores ni omisiones; dominio, configuración y estructura aprobados |
| JetBrains recorrido reforzado | Repetición focalizada aprobada con las tres estrategias y cierre tras aceptar la respuesta |
| Plugin Verifier | exit 0, compatible con IU-261.22158.277 |
| Visual Studio dominio/host | 409 / 68 aprobados, sin omisiones; repetición de los tres recorridos reforzados aprobada |
| VSIX y WPF | build con MSBuild y net472 aprobado; verificador WPF: 30 fixtures aprobados |
| TUI | gofmt sin salida, go vet y cinco paquetes de tests aprobados; detector de carreras aprobado |
| TUI en PTY | Dos procesos interactivos, vigilancia activa, cuatro capturas y dos Finish; exit 0 |
| Canónico y assets | 41 tests del gate y ambos checkers aprobados |
| ShellCheck y diff | Lista de CI más el helper nuevo sin diagnósticos; `git diff --check` aprobado |

La primera tanda completa de Electron sufrió una caída del renderer. La
repetición usó mayor memoria compartida del contenedor y llegó a las aserciones:
detectó que el test nuevo dejaba un Finish pendiente para la siguiente spec.
Se corrigió la limpieza del fixture y la siguiente suite completa aprobó los
108 casos. Los logs fallidos se conservaron: no cuentan como verificaciones
aprobadas. Un intento paralelo de Gradle falló por un lock de caché entre
contenedores; después se ejecutó sin compartir la caché con otro Gradle activo.

## Límites y fricción que se conserva

Si el mismo revisor conserva Shared modificado y recibe por Git una respuesta
distinta, la regla vigente conserva ambas versiones y exige reconciliación
manual. El recorrido lo prueba y acepta explícitamente el documento entrante.
No se convirtió esa situación en un merge automático de prosa.

Esto acredita comportamiento compartido de la CLI y sus adaptadores, un host
real de VS Code y la TUI real. No acredita todavía una sesión interactiva
completa en IntelliJ o Visual Studio, sus APIs de selección/diff, buffers
abiertos, VFS/RDT ni la matriz nativa macOS/Windows. Las dos pruebas que cambian
User PATH no se ejecutaron. El build del VSIX, los fixtures WPF y Plugin Verifier
no sustituyen esas verificaciones. No se marcan T154/T155 como completadas.
