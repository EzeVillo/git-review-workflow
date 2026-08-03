# Walkthrough

## Heads-up

Todo el peso de este PR descansa en una sola invariante: FR-001/FR-002/SC-005
— la extensión no puede derivar estado de review por fuera de invocar la CLI,
ni mutar refs, config o el índice directamente. Es una propiedad estructural,
no algo que se pueda probar corriendo la extensión (quickstart.md lo dice
explícito: SC-005 se verifica leyendo el código, no ejecutando), así que vale
la pena chequearla a mano: cualquier lectura de `branch.review/*`, cualquier
ref bajo `refs/review-edits/`, cualquier parseo de `.review/walkthrough.md` o
de la salida humana de un verbo, es una violación. Los dos lugares donde
colarse sería más fácil son `src/review/repository.ts` (el único punto que
toca la API de `vscode.git`, y solo para dos cosas: la raíz del repo y la
señal de cambio) y `src/extension.ts` (donde se ensamblan todas las
invocaciones).

Dos cosas más, más puntuales:

- El des-citado de paths (`unquote.ts`) es unidireccional a propósito: `raw`
  es lo único que vuelve a la CLI, `display` es lo único que ve el usuario, y
  nunca se re-cita. Confundir los dos rompería el round-trip con
  `status --why` en silencio, no con un error visible.
- Hay dos políticas de concurrencia distintas y no intercambiables (Decisión 9
  de research.md): las mutaciones (`next`/`prev`) descartan una segunda
  llamada concurrente; las lecturas (`status --porcelain`) la coalescen. Si en
  algún momento alguien "simplifica" esto a una sola política, es un bug, no
  una limpieza.

Nada de este PR está commiteado todavía en el repo. Antes de correr
`git review walkthrough build` sobre este mismo archivo hace falta commitear
los cambios primero — el propio skeleton de `walkthrough init` lo advierte, y
no lo hice por vos para no tomar esa decisión en tu lugar.

## 1. specs/002-extension-vscode/spec.md
Arrancá por acá. Define qué es esta feature y, más importante, qué NO es:
nada de estado derivado fuera de la CLI, nada de verbos consecuentes
(finish/abort/save) a un clic, nada de webview propio. Esas exclusiones son
la razón de ser de casi todas las restricciones que vas a ver repetidas en
research.md y en los contratos — si algo en el código las viola, es el spec
el que lo dice primero.

## 2. specs/002-extension-vscode/plan.md
El resumen técnico y la estructura de directorios que el resto del PR sigue
al pie. Fijate en "Constitution Check": no hay principios ratificados en este
repo todavía, así que el gate real es `CLAUDE.md`, y acá se documenta por qué
casi ninguna de sus reglas (pensadas para la CLI en `sh`) aplica a este
subproyecto en TypeScript salvo la de espejar los idioms del host.

## 3. specs/002-extension-vscode/research.md
Trece decisiones de diseño, cada una con alternativas descartadas y su
rationale. Es el documento más denso del PR y el que explica el porqué detrás
de casi todo el código: TreeView nativo en vez de webview (Decisión 4), las
dos políticas de concurrencia (Decisión 9), el des-citado unidireccional de
paths (Decisión 8). Vale la lectura completa antes de entrar al código.

## 4. specs/002-extension-vscode/data-model.md
Las entidades derivadas del porcelain, con sus reglas de validación
explícitas — en particular la aridad variable del registro `state` según
`mode`, y la razón de que `PathRef` tenga dos campos (`raw`/`display`) en vez
de uno. Tenelo a mano para leer `porcelain.ts` y `unquote.ts` más adelante.

## 5. specs/002-extension-vscode/contracts/cli-invocation.md
> key
La lista cerrada de todo lo que la extensión tiene permitido invocar, y la
tabla de prohibiciones explícitas al final. Es el artefacto contra el que se
verifica SC-005: cualquier invocación en el código que no esté acá, o
cualquier lectura de config/refs/ramas para derivar estado, es un bug.
Guardalo en mente para cuando llegues a `extension.ts` y `repository.ts` — son
los dos lugares donde una violación se colaría.

## 6. specs/002-extension-vscode/contracts/extension-surface.md
El lado "contrato" del manifiesto: ids de comando, context keys y el mapeo
`situation` → `viewsWelcome`. Como es interfaz pública (cambiar un id rompe
keybindings o `settings.json` de usuarios), es la referencia normativa contra
la que vale contrastar `package.json` más adelante.

## 7. specs/002-extension-vscode/quickstart.md
Los pasos para correr la extensión y los siete escenarios de validación
manual — incluida la advertencia de que SC-005 no se puede ejecutar, solo
revisar. Es la guía que vas a usar vos para probar esto antes de aprobar el
PR.

## 8. specs/002-extension-vscode/checklists/requirements.md
Checklist de calidad del spec, ya tildado. Léelo rápido para confirmar que las
dos ambigüedades reales (alcance del modo step, verbos consecuentes a un
clic) se resolvieron acotando el scope y no quedaron como deuda escondida.

## 9. specs/002-extension-vscode/tasks.md
El desglose en ~50 tareas, todas tildadas. No hace falta leerlo tarea por
tarea; sirve como índice de qué historia de usuario toca qué archivo si te
perdés más adelante.

## 10. .specify/feature.json
Housekeeping de Spec Kit: mueve el feature activo de `001-contrato-porcelain`
a `002-extension-vscode`. Sin lógica; solo constata que estás leyendo esta
feature con el contexto correcto.

## 11. vscode-extension/package.json
El manifiesto de la extensión: activación perezosa
(`onView:gitReview.walkthrough`, Decisión 12 de research.md), los siete
comandos con sus cláusulas `when`, los cinco `viewsWelcome` (uno por
`Situation` salvo `review`) y la única configuración (`gitReview.path`).
Contrastalo campo a campo con `contracts/extension-surface.md` — es la
implementación literal de ese contrato.

## 12. vscode-extension/tsconfig.json
Strict al máximo (`noUnusedLocals`, `noUnusedParameters`, `noImplicitReturns`,
`noFallthroughCasesInSwitch`), target ES2022/Node ≥18 — coherente con el
motor mínimo del extension host. Nada específico de VS Code acá; eso lo trae
`@types/vscode` como devDependency.

## 13. vscode-extension/esbuild.js
Bundle de un solo entry point (`extension.ts`) a `dist/extension.js`, con
`vscode` como `external` — es lo único que `package.json` declara como
`main`. Nada fuera de lo estándar de un `esbuild.js` de extensión de VS Code.

## 14. vscode-extension/.gitignore
Excluye `node_modules/`, `dist/`, `out/`, `.vscode-test/` y `*.vsix`. Sin
sorpresas — solo confirmá que no falta nada: correr los tests de integración
deja una carpeta `.vscode-test/` pesada (perfil de VS Code más caché de
Chromium) que sí tiene que quedar afuera del repo.

## 15. vscode-extension/.vscodeignore
Excluye del `.vsix` empaquetado todo lo que no es runtime: `src/`, `test/`,
mapas de sourcemap, configs de dev. Lo único que viaja es `dist/extension.js`,
el bundle de esbuild.

## 16. vscode-extension/.vscode/launch.json
Configuración de F5 para levantar el Extension Development Host ("Run
Extension") y para correr la suite de integración con el debugger adjunto
("Extension Tests"). No existía en el repo — la agregué para que abrir
`vscode-extension/` como carpeta y apretar F5 alcance, sin pasos manuales
adicionales.

## 17. vscode-extension/.vscode/tasks.json
El build task por defecto (`npm run compile` vía esbuild) que `launch.json`
referencia como `preLaunchTask`. Sin `problemMatcher` propio a propósito:
esbuild no es `tsc`, y el chequeo de tipos real ya lo hace `pretest`
(`tsc --noEmit`) por separado.

## 18. vscode-extension/package-lock.json
Mecánico, generado por `npm install`. No hace falta leerlo línea por línea —
alcanza con confirmar que las versiones de `@vscode/test-electron`, `esbuild`
y `vsce` que trae coinciden con lo que `package.json` declara.

## 19. vscode-extension/README.md
En inglés, a diferencia de los documentos de `specs/` — esto es producto, no
un documento de trabajo, y cae bajo la misma regla que `README.md`/
`README.es.md` de la raíz. Cubre instalación, F5, testing y empaquetado;
contrastalo con `quickstart.md`, que es la versión más detallada de lo mismo.

## 20. vscode-extension/src/cli/unquote.ts
> key
Deshace el citado estilo C que aplica git — backslashes, comillas, escapes de
control y octales consecutivos reensamblados como bytes UTF-8. Es
unidireccional a propósito (nunca se re-cita `display` para devolverlo a la
CLI; siempre se usa `raw`): un bug acá rompería el round-trip con
`status --why` en silencio, no solo la presentación en pantalla.

## 21. vscode-extension/src/cli/invoke.ts
La única puerta de salida hacia la CLI: `execFile` sin shell, con el fallback
de `gitReview.path` y el caso especial de Windows (invocar `sh` de forma
explícita para el dispatcher POSIX sin extensión, ver el comentario sobre
CVE-2024-27980). research.md marca este camino como un riesgo a verificar en
el primer entregable ejecutable — vale confirmar que el fallback se ejercita
de verdad en el job de CI de Windows.

## 22. vscode-extension/src/cli/porcelain.ts
> key
El tokenizador de unas 30 líneas que reemplaza cualquier dependencia de
parseo. La invariante que no se puede romper: `mode` se lee primero y recién
después se decide cuántos campos esperar (6/10/11 según whole/step/walk) —
invertir ese orden produce corrimientos de campo silenciosos, no un error
visible. Cotejalo con la tabla de aridad de la Decisión 2 de research.md.

## 23. vscode-extension/src/cli/version.ts
Comparación de versiones `X.Y.Z` pura, sin dependencias — cualquier formato
que no sean tres enteros cuenta como "vieja" en vez de reventar.
`MIN_CLI_VERSION = 0.3.0` es el commit donde entró el contrato porcelain
(Decisión 1 de research.md).

## 24. vscode-extension/src/review/situation.ts
El mapeo de exit code a `Situation`, en 15 líneas. La regla que vale la pena
confirmar: cualquier código desconocido (no solo mayor a 3) cae en `error`,
nunca en `review` — un exit code inesperado no puede interpretarse como
éxito.

## 25. vscode-extension/src/review/repository.ts
> key
El único punto del código que toca la API de `vscode.git`, y por diseño solo
para dos cosas: dónde está el repositorio y cuándo algo cambió (Decisión 7 de
research.md). Ningún campo de `ReviewState` puede alimentarse de acá — es la
frontera concreta que SC-005 exige poder verificar leyendo el código, y por
eso el archivo donde una violación sería más fácil de colar sin que los tests
la agarren.

## 26. vscode-extension/src/review/state.ts
> key
El dueño del `ReviewState`: nunca deriva nada por su cuenta, siempre
reinvoca la CLI y descarta lo anterior. Dos cosas sutiles para mirar con
cuidado: la coalescencia de refrescos (un pedido que llega con uno en vuelo
se marca sucio y se re-corre una sola vez al terminar, nunca se encola sin
límite) y el chequeo de versión por "generación" — evita que un
`checkCliVersion` viejo que sigue en vuelo marque como verificada una
generación nueva si `gitReview.path` se editó dos veces seguidas.

## 27. vscode-extension/src/review/mutationLock.ts
Cola de profundidad 1: una segunda mutación mientras la primera está en
vuelo se descarta, no se encola (Decisión 9 de research.md) — encolarla
ejecutaría una intención basada en una posición que ya dejó de ser vigente.
Sin dependencia de `vscode`, testeable como función pura.

## 28. vscode-extension/src/views/walkthroughTreeProvider.ts
El `TreeDataProvider`: entradas en el orden del registro (nunca reordenadas),
la actual marcada por `position` — no por `id`, porque dos entradas podrían
compartir path en un walkthrough mal escrito — y el *why* servido de forma
perezosa, solo cuando VS Code llama a `resolveTreeItem`.

## 29. vscode-extension/src/views/whyContentProvider.ts
Dos superficies para el mismo dato (hover vía `resolveTreeItem`, lectura
completa vía este content provider), ambas bajo demanda y sin caché — nunca
al construir el árbol, que es justo lo que el contrato 001 separó al sacar el
*why* de la secuencia.

## 30. vscode-extension/src/commands/openEntry.ts
> key
La Decisión 10 hecha código: el clic abre el archivo del working tree (ya es
el PR aplicado, y por lo tanto editable), y el diff queda como acción aparte
delegada en `git.openChange`. Lo que más vale la pena revisar es el fallback
cuando el archivo no existe (eliminado en el rango) y la rama de modo step,
que nunca abre un archivo de texto plano sino los cambios del commit.

## 31. vscode-extension/src/commands/navigate.ts
`next`/`prev` a través del `MutationLock`: invoca el verbo, refresca con
`status --porcelain` inmediatamente después, y recién ahí abre los cambios de
la entrada resultante (lo mismo que "Ver cambios", no el archivo pelado) —
nunca lee la salida humana del verbo para saber dónde quedó el cursor (FR-015). Los límites de la secuencia se propagan tal cual
desde la CLI, sin lógica propia.

## 32. vscode-extension/src/commands/installOrUpdateCli.ts
El botón de los estados `cli-missing`/`cli-outdated`: abre la URL de
instalación. Es deliberadamente el comando más simple del PR — instalar la
CLI de verdad sigue siendo trabajo del usuario, no de la extensión.

## 33. vscode-extension/src/extension.ts
> key
`activate()`: ata todas las piezas — repositorio, estado, árbol, comandos,
context keys. Es el lugar donde una invocación prohibida por
`contracts/cli-invocation.md` se colaría más fácil, así que es el punto
natural para hacer la revisión manual de SC-005 que pide quickstart.md.
Fijate también en `resolveTargets()`: el fallback multi-root para cuando la
API de git todavía no terminó de escanear los repos del workspace.

## 34. vscode-extension/test/unit/.mocharc.json
Corre los `.spec.ts` bajo `test/unit/` con `ts-node/register/transpile-only`
— sin type-check en el runner, porque `pretest` ya corrió `tsc --noEmit`
antes. Ningún host de VS Code de por medio: esto es lo que hace baratos estos
tests en los tres SO.

## 35. vscode-extension/test/unit/unquote.spec.ts
Casos de `unquotePath` uno por uno: sin citar, con acentos sin citar
(`core.quotePath=false`), backslash escapado, comilla escapada, escapes de
control, y el caso más delicado — octales consecutivos reensamblados como un
único carácter UTF-8 multibyte ("café").

## 36. vscode-extension/test/unit/porcelain.spec.ts
Un caso por combinación de aridad (whole/step/walk), más el descarte de
etiquetas desconocidas y de campos extra — es la prueba directa de
FR-003/SC-006 (que una CLI más nueva no rompa el panel).

## 37. vscode-extension/test/unit/state.spec.ts
Pese al nombre del archivo, son los unitarios de `situationForExitCode` (que
vive en `review/situation.ts`), no de `ReviewStateManager`. Confirmá el caso
que más importa: un exit code mayor a 3 cae en `error`, no en `review`.

## 38. vscode-extension/test/unit/mutationLock.spec.ts
Confirma la regla que más importa de `MutationLock`: la segunda llamada
concurrente devuelve `undefined` y nunca corre su `fn`, no se encola — es la
prueba directa de FR-020.

## 39. vscode-extension/test/unit/version.spec.ts
`compareVersions`/`isOutdated` en los bordes: igual, menor en cada posición,
mayor, y formato inválido tratado como "vieja" en vez de reventar.

## 40. vscode-extension/test/integration/helpers/fixture.ts
Construye los repos de fixture invocando el `bin/git-review` real del
checkout, no un mock (Decisión 11 de research.md, "deuda anotada": un fixture
de porcelain escrito a mano probaría el parser contra sí mismo).
`envWithBinOnPath` es lo que hace que esto funcione en Windows sin invocar el
script POSIX directo — antepone `bin/` al PATH y deja que `git review` lo
descubra, igual que en producción.

## 41. vscode-extension/test/integration/helpers/extensionApi.ts
Activa la extensión a la fuerza (activación perezosa por `onView:...`) y
expone la `GitReviewTestApi` de `extension.ts` — es el único gancho que
tienen las specs para inspeccionar el `TreeDataProvider` sin una API pública
de lectura de `TreeView`.

## 42. vscode-extension/test/integration/index.ts
El runner de mocha para la suite de integración: junta todos los
`*.spec.js` compilados bajo `test/integration/`. Boilerplate estándar de
`@vscode/test-electron`, sin sorpresas.

## 43. vscode-extension/test/integration/runTests.ts
El bootstrap que crea el repo temporal antes de levantar el VS Code de
pruebas y lo limpia al terminar (`try/finally` alrededor de `runTests`). Si
esto falla temprano, ninguna spec llega a correr — es el primer sospechoso
ante un fallo de CI sin mensaje claro.

## 44. vscode-extension/test/integration/walkthrough-panel.spec.ts
US1 de punta a punta — el escenario central del PR (quickstart §1): 7
entradas, una esencial, cursor en la 2ª, y archivos que llegan después de
construir el walkthrough (por eso "sin cobertura", no simplemente omitidos).
Incluye también whole-sin-walkthrough y walkthrough-degradado, los dos casos
límite de la Historia 1.

## 45. vscode-extension/test/integration/open-entry.spec.ts
US2 de punta a punta, con el caso de paths raros (espacios más caracteres no
ASCII) como prueba end-to-end de `PathRef`, y el caso del archivo eliminado
verificando explícitamente que NO se abrió un editor de texto plano sobre un
path que ya no existe.

## 46. vscode-extension/test/integration/why.spec.ts
US3: el hover devuelve un `MarkdownString` y la lectura completa preserva
saltos de línea — fijate que el test recorta solo el salto de línea final
(`replace(/\n+$/, "")`), que es ruido de cómo el archivo del walkthrough
guarda el texto, no algo que la extensión deba tocar.

## 47. vscode-extension/test/integration/navigate.spec.ts
US4 de punta a punta: avanzar/retroceder desde el panel y contrastar la
posición contra un `status --porcelain` corrido aparte, más el caso inverso —
correr `next` en la terminal y verificar que el panel se entera solo, sin
reabrirse (FR-019).

## 48. vscode-extension/test/integration/step-mode.spec.ts
US6, la historia P3 recortable: confirma que el orden de los commits es el
de `rev-list` de la CLI (no alfabético por SHA) y que editar el commit actual
antes de avanzar lo deja marcado `banked` — el único campo de `EntryRecord`
exclusivo del modo step.

## 49. vscode-extension/test/integration/empty-states.spec.ts
Las cinco pantallas de la Historia 5, incluida la más laboriosa de fabricar:
CLI vieja, con un script `.sh` fake que responde `--version` con `0.1.0`.
Fijate en `waitForSituation` — el cambio de `gitReview.path` dispara un
refresh asíncrono vía `onDidChangeConfiguration`, así que el test sondea en
vez de asumir que un solo refresh ya lo vio.

## 50. .github/workflows/ci.yml
Job nuevo en la matriz de los tres SO: instala la CLI de este mismo checkout
(no una versión publicada) y corre `pretest` → `test:unit` → `test:integration`,
con `xvfb-run` en Linux. Es el único archivo fuera de `vscode-extension/` que
toca esta feature (plan.md § Structure Decision) — confirmá que no se coló
nada más en la raíz del monorepo.

