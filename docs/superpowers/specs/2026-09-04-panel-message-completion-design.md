# Finalización esperable de mensajes del panel

## Problema

La API de integración `sendPanelMessage` devuelve `void` y el despachador del
host descarta con `void` todas las promesas de las acciones que inicia. Los
tests que ejercitan controles exclusivos del cuerpo del panel no pueden esperar
la finalización real: sondean un efecto intermedio y pueden pasar al siguiente
escenario mientras el comando o su refresco final siguen en vuelo. Como todas
las specs usan el mismo repositorio temporal, ese trabajo residual puede cruzar
la limpieza y la preparación del test siguiente.

El síntoma observado en Windows fue que un fixture terminó correctamente
`git review start --step`, pero el `git review next` inmediato encontró `HEAD`
otra vez en `main`. El mismo commit pasó en Linux, macOS, otras ejecuciones de
Windows y al reintentar, por lo que el arreglo no debe ser un retry sino cerrar
la frontera asíncrona del harness.

## Diseño

`handlePanelMessage` será asíncrono y devolverá `Promise<void>`. Cada rama del
conjunto cerrado de `PanelMessage` esperará la operación que despacha, tanto si
llama una función directa como si delega en `vscode.commands.executeCommand`.
Las ramas inválidas seguirán resolviendo sin hacer nada.

`WalkthroughViewProvider` aceptará un callback que pueda devolver una promesa.
El listener real del webview seguirá siendo no bloqueante y consumirá esa
promesa explícitamente: una acción del usuario no necesita que el webview espere
una respuesta. La API expuesta sólo para integración, en cambio, devolverá la
misma promesa para que una spec pueda esperar exactamente el trabajo que inició.

Todos los tests que llaman `sendPanelMessage` usarán `await`. Los sondeos que
esperaban la finalización de la mutación o del refresco se reemplazarán por
aserciones directas después de esa espera. Se conservarán únicamente los sondeos
que prueban deliberadamente un estado intermedio o una ausencia durante una
operación todavía abierta.

## Cobertura

Una prueba de integración comprobará primero que el despacho devuelve una
promesa real. Antes del cambio fallará de forma determinística porque recibe
`undefined`; después esperará la promesa y afirmará el efecto final. El caso se
ejercerá mediante un control mutante de fila, que atraviesa resolución de índice,
confirmación, lock, proceso de CLI y refresco.

La verificación incluirá typecheck, unit tests, las specs de integración que
usan mensajes del panel (`fixes-panel`, `guide-panel` y `draft-panel`), la spec
original `finish-review` ejecutada detrás de sus vecinas en el orden normal y la
suite de integración completa en Windows. No se agregan retries ni sleeps al
producto o a CI.

## Alcance entre pipelines

La carrera pertenece al harness de integración de VS Code. Ese mismo código se
ejecuta en los jobs de Ubuntu, macOS y Windows, por lo que un único arreglo cubre
los tres. Las suites Bats, JetBrains, Visual Studio y TUI no usan
`sendPanelMessage`, `WalkthroughViewProvider` ni el repositorio temporal de este
harness; no corresponde alterarlas sin una falla equivalente.
