# Research: El ciclo de una review, completo desde el panel

Decisiones técnicas previas al diseño. Rige el mismo principio que ordenó
`002` —**espejar los idioms del host**, trasladado de git a VS Code— más la
restricción transversal que esta feature tensa y no rompe: ningún camino deriva
estado de review, ni estado del repositorio, por fuera de la CLI.

Los datos del lado de la CLI se verificaron **contra el código**, no contra los
contratos: `bin/git-review-verbs/{start,finish,save,abort,status,list}`,
`bin/git-review-lib.sh` y `bin/git-review` en el árbol actual (VERSION `0.3.0`).

---

## Decisión 1 — La configuración se lee por un verbo nuevo, no ampliando `status`

**Decisión**: agregar `git review config` con su `--porcelain`, en vez de hacer
que `status --porcelain` reporte algo cuando no hay review.

**Rationale**: no es una preferencia, es una **prohibición vigente**. El contrato
de `001` lo fija en su primera sección de invocación:

> Válido únicamente dentro de una review activa (HEAD en `review/*`) — no hay
> modo "vista previa" fuera de una review (spec, Q1 = A).

Esa decisión se tomó a propósito y con una pregunta cerrada. Reabrirla para que
`status` hable en `no-review` invertiría el significado del exit `2`, que hoy es
"acá no hay nada que mostrar, y eso es normal", y que la extensión usa para
elegir el estado vacío entero. Un verbo aparte no toca nada de eso.

Y hay un argumento de forma: lo que el panel necesita antes de iniciar no es el
estado de una review —no hay ninguna— sino **cómo se armaría** una. Son dos
preguntas distintas y el proyecto ya tiene la costumbre de darle un verbo a cada
pregunta (`status` la de acá, `list` la del repositorio entero).

**Alternativas consideradas**:

- *Extender `list --porcelain`*, que sí corre sin review. Se descartó: `list`
  responde "qué reviews existen", que es inventario, no configuración. Mezclarlas
  obligaría a que un consumidor que sólo quiere el inventario pague el costo de
  enumerar ramas candidatas en cada refresco del estado vacío.
- *Que la extensión lea `git config reviewworkflow.base` directamente*. Se
  descartó por FR-004, y por el argumento que originó la feature: convertiría el
  lugar de almacenamiento en contrato de facto.

---

## Decisión 2 — `git review config <clave> [<valor>]`: leer sin valor, escribir con valor

**Decisión**: la forma del verbo espeja `git config` byte por byte en su gramática:

```sh
git review config                 # imprime toda la configuración efectiva (humano)
git review config --porcelain     # lo mismo, legible por máquina
git review config base            # imprime el valor efectivo de una clave
git review config base main       # lo fija
git review config --unset base    # lo borra
```

Las claves expuestas son las dos que el producto ya define —`base` y `remote`—,
no las claves crudas de git: el verbo traduce `base` ↔ `reviewworkflow.base`, y
ése es exactamente el punto (FR-008: el consumidor nunca ve dónde se guarda).

**Rationale**: el gate rector del proyecto es espejar git. `git config` es *el*
comando de configuración que todo usuario de git ya sabe usar, y su gramática
—clave sola para leer, clave + valor para escribir, `--unset` para borrar— es
conocida sin documentación. Inventar `git review set-base` o
`git review base --set` sería superficie nueva que hay que aprender para
resolver un problema que git ya resolvió.

Que el mismo verbo lea y escriba también resuelve la asimetría que FR-010b pide
evitar: no hay forma de que el reporte crezca y la escritura se quede atrás,
porque son el mismo código.

**Alternativas consideradas**:

- *Sólo lectura, y que la escritura la haga el usuario con `git config`*. Es lo
  que la spec traía antes de la clarificación; el usuario decidió que configurar
  la base desde el panel entra, y sin escritura el estado "sin base" es un
  callejón dentro del editor.
- *Un flag en `start` (`--set-base`)*. Se descartó: mezcla configurar con actuar,
  y deja la configuración inalcanzable salvo iniciando una review.

---

## Decisión 3 — Las ramas candidatas viajan en el mismo reporte, en procesos constantes

**Decisión**: `git review config --porcelain` emite, además de la configuración,
un registro por rama candidata, con su origen (`remote` o `local`). Se derivan
con **una** invocación de `git for-each-ref` sobre los dos namespaces, filtrando
en shell.

**Rationale**: el consumidor necesita las mismas ramas para dos preguntas
distintas (cuál revisar, cuál fijar como base) y en el mismo momento (antes de
iniciar). Partirlas en dos invocaciones duplicaría el costo sin ganar nada.

Lo de "procesos constantes" no es microoptimización: es la lección medida de
`002` (Decisión 2) y de `003`. Bajo Git Bash en Windows, donde `fork()` está
emulado, un proceso por ítem fue lo que convirtió un `status` de 50 commits en
~9 segundos. Un repositorio con cientos de ramas es un caso mucho más común que
un PR de 50 commits, así que la regla se aplica desde el principio: un
`for-each-ref` con `--format`, un pase de shell, cero `rev-parse` por rama.

El filtrado excluye los tres namespaces propios del producto (`review/*`,
`review-saved/*`, `review-fixes/*`), que es exactamente lo que `start` ya se
niega a revisar (`bin/git-review-verbs/start:151-153`) — la lista no ofrece lo
que el verbo va a rechazar, que es la regla de FR-015 y de `002/FR-033`.

**Sobre el remoto**: las ramas remotas se enumeran bajo el remoto **efectivo**
(el que reporta la misma salida), no bajo `origin` hardcodeado. Es el mismo
valor que `start` usa (`bin/git-review-verbs/start:158`), y tenerlo en la misma
salida evita que el consumidor lo combine mal.

**Alternativas consideradas**:

- *Un verbo `git review branches`*. Se descartó: sería un tercer lugar al que
  preguntarle al repositorio, y las ramas sin el remoto efectivo y sin la base
  actual no alcanzan para dibujar el diálogo.
- *Emitir sólo las remotas*. Se descartó: con el origen en `--local`/`--offline`
  la rama relevante es la local, y el panel tiene que poder ofrecer la que
  corresponde al origen elegido (FR-009b).

---

## Decisión 4 — El estado de cierre se reporta en `list` (pendiente) y en `status` (trabado)

**Decisión**: un registro nuevo, etiqueta `finish`, en **los dos** verbos, porque
los dos estados se observan desde lugares distintos:

| Estado | Dónde queda `HEAD` | Qué ve el panel hoy | Dónde se reporta |
|--------|--------------------|----------------------|-------------------|
| Cierre completo pendiente | `review-fixes/<src>`, o la rama del PR con `--onto-source` | exit `2` → "no hay ninguna review" | `list --porcelain` |
| Cierre trabado por conflicto | `review/<src>` | exit `0` → una review normal y navegable | `status --porcelain` |

**Rationale**: es la forma del problema, no una elección estética.

- Tras un cierre **completo**, `HEAD` ya no está en `review/*`, así que `status`
  sale con `2` por diseño (`bin/git-review-verbs/status:69`) y no hay dónde
  colgar el dato. Pero la rama `review/<src>` **sigue existiendo** —`finish` no
  la borra— y con ella su registro de undo en la config
  (`branch.review/<src>.reviewundohead`). O sea: la review sigue apareciendo en
  `list`, que ya la enumera hoy. Sólo falta decir en qué estado está. Encaja sin
  cambiar *cuándo* se invoca nada: el panel en `no-review` **ya llama a
  `list --porcelain`** para dibujar el inventario (`002`,
  `contracts/cli-invocation.md`).
- Con un cierre **trabado**, `HEAD` sigue en `review/<src>` y `status` responde
  `0` con una review de aspecto normal. Ése es el caso peligroso: el panel
  ofrecería `next`/`prev` sobre un working tree con marcadores de conflicto y un
  cierre a medio hacer. Por eso el dato tiene que llegar por `status`, que es lo
  que el panel consulta cuando hay review, y por eso existe FR-027.

**Por qué un registro propio y no un campo más en `state`**: el registro `state`
tiene aridad variable por modo (5, 9 o 10 campos después de la etiqueta) y sus
campos son posicionales. Agregar un campo al final sería ambiguo justamente en
los modos que omiten grupos. El contrato ya previó esta situación y la resolvió
con la misma regla en `001` ("lo que haya que agregar en el futuro va en un
registro propio"). Un consumidor viejo ignora la etiqueta desconocida, que es
FR-003 de `002` y SC-006 de aquella feature: la compatibilidad sale gratis.

**Sobre `--onto-source`**: es el caso que hace inviable cualquier heurística por
nombre de rama —ahí `HEAD` queda en la rama del PR, que no tiene prefijo
reconocible—. Reportar desde `list`, que parte de las ramas `review/*` y su
config, lo cubre sin mirar dónde está parado el usuario.

---

## Decisión 5 — Invocación: se mantiene la captura, con entorno no interactivo y escape a terminal

**Decisión**: los verbos nuevos se invocan por el mismo camino que los actuales
(`invokeGitReview`, `cross-spawn`, sin shell, `cwd` en la raíz del repo), con dos
agregados:

1. **Entorno no interactivo** para la única invocación que toca la red
   (`start`): `GIT_TERMINAL_PROMPT=0`, y `GIT_ASKPASS`/`SSH_ASKPASS` apuntados a
   un no-op. git falla entonces de inmediato con su propio diagnóstico de
   autenticación en lugar de quedarse esperando a un TTY que no existe.
2. **Escape a terminal**: cuando `start` falla y su `stderr` corresponde a ese
   caso, el error del editor ofrece *Run in Terminal*, que envía el comando
   **exacto** que se intentó a una terminal integrada. Ahí sí hay quién conteste
   el pedido de credenciales, y el helper de credenciales del usuario funciona
   como funciona en su terminal.

**Rationale**: fue la decisión abierta que el usuario delegó ("tomá la mejor
decisión, controlá los errores de la mejor manera"). Las dos opciones puras
fallan en un extremo cada una:

- *Sólo captura*, sin tocar el entorno: es el bug latente. `cross-spawn` sin TTY
  contra un remoto que pide credenciales **se cuelga hasta el timeout** y después
  reporta un timeout, que no menciona la causa real. Es exactamente lo que SC-007
  prohíbe.
- *Sólo terminal*: preserva la salida humana verbatim y resuelve la
  autenticación, pero pierde el exit code y el momento exacto en que terminó, así
  que el panel no sabe si refrescar ni si hubo error; y deja al usuario leyendo
  salida en una ventana, que es el problema que la feature ataca.

El híbrido queda del lado correcto de las dos reglas del proyecto: el camino
normal es capturado (el panel sabe qué pasó, muestra el `stderr` de la CLI tal
cual, FR-031) y el camino excepcional delega en el host en lugar de inventar una
UI de credenciales, que es lo que la Decisión 10 de `002` ya hizo con el diff.

**Clasificar no es parsear, y la frontera se escribe.** Decidir si ofrecer *Run
in Terminal* implica mirar el `stderr`, y el proyecto prohíbe parsear la salida
humana. No es la misma cosa, y la distinción queda fijada en el contrato para que
no haya que re-deducirla: lo prohibido es leer la salida de **un verbo de
`git review`** para derivar estado de la review — que es lo que el contrato
porcelain existe para reemplazar. Lo que `start` propaga cuando falla un `fetch`
es el `stderr` de **git**, sobre el cual no hay contrato ni lo va a haber, y del
que no se deriva ningún estado: sólo se elige qué botón mostrar junto al mensaje,
que se sigue mostrando verbatim pase lo que pase. Si la clasificación falla, el
usuario ve el mismo texto con un botón de más o de menos; ningún campo del
view-model cambia.

**Riesgo registrado**: que el `stderr` de un fallo de autenticación sea
distinguible de otros fallos de red es un supuesto a **verificar en el primer
entregable ejecutable**, no al final. Si la distinción no es fiable, la salida es
ofrecer *Run in Terminal* ante **cualquier** fallo de `start` que toque la red —
más ruidoso, pero nunca engañoso— y ajustar SC-007 a dos categorías en vez de
tres, en lugar de dejarlo afirmando una diferenciación que no ocurre.

---

## Decisión 6 — Tres clases de timeout, no uno solo

**Decisión**: el timeout deja de ser un valor único (`15 s`) y pasa a depender de
la clase de invocación:

| Clase | Ejemplos | Timeout |
|-------|----------|---------|
| Lectura | `status`, `list`, `config`, `--why`, `--version` | 15 s (el actual) |
| Mutación local | `finish`, `save`, `abort`, `continue`, `next`/`prev` | 120 s |
| Mutación con red | `start` | 300 s |

**Rationale**: el valor actual se calibró para un `status`. Aplicárselo a un
`finish` que replica ediciones commit por commit sobre un PR grande, o a un
`start` que hace `fetch` de un repositorio recién clonado, produciría el peor
error posible: matar la operación **a mitad**, que es justo lo que FR-037 quiere
impedir. Un timeout generoso en una operación no cancelable no cuesta nada —el
progreso del editor ya comunica que sigue trabajando— y un timeout corto puede
corromper el estado.

**Consecuencia**: un timeout que igual se alcanza es un fallo que el panel no
puede describir por sí solo, y ahí el estado que se muestra es el que reporte el
refresco posterior. Es la regla general (nunca parsear la salida humana, siempre
volver a preguntar) aplicada al peor caso.

---

## Decisión 7 — Concurrencia: se mantiene el descarte, pero deja de ser silencioso

**Decisión**: `MutationLock` sigue siendo una cola de profundidad 1 que descarta
—no encola— la segunda invocación, pero ahora **avisa** cuando descarta.

**Rationale**: la Decisión 9 de `002` eligió descartar porque un segundo `next`
se decidió mirando una posición que ya no es la vigente. El argumento vale igual
acá y con más fuerza: un segundo `finish` disparado sobre el estado previo sería,
en el mejor caso, un no-op ruidoso. Pero el silencio que era correcto para un
avance de cursor —donde el resultado se ve solo— es incorrecto para una
operación que el usuario espera que cambie ramas: FR-036 pide explícitamente que
un pedido duplicado ni se ejecute dos veces **ni desaparezca sin señal**.

La primera línea de defensa sigue siendo la context key `gitReview.busy`, que ya
apaga los controles del panel mientras algo corre; el aviso cubre el camino que
esa key no alcanza (la paleta de comandos, un atajo de teclado).

---

## Decisión 8 — Premisa caduca: se revalida entre confirmar y ejecutar

**Decisión**: las acciones con confirmación capturan un testigo del estado en el
momento en que se arma el diálogo —rama de review, `tip`, y la situación— y lo
revalidan **después** de que el usuario confirma, antes de invocar. Si cambió, no
se ejecuta y se informa por qué.

**Rationale**: es un edge case real que `002` no tenía porque `continue` es su
única mutante con confirmación y el inventario del que sale se re-lee igual. Acá
la ventana es más grande y más peligrosa: un modal puede quedar abierto minutos
mientras el usuario corre `git review finish` en la terminal, y confirmar
entonces ejecutaría una decisión tomada sobre un repositorio que ya no existe.
Es FR-038, y el costo es una lectura barata que ya se hace en cada refresco.

**Dónde no aplica**: en `next`/`prev`, que no tienen confirmación y cuya ventana
es la duración de un clic. No se les agrega.

---

## Decisión 9 — Iniciar es un asistente por pasos del host, no un formulario

**Decisión**: `start` se dispara con un `QuickPick` multi-paso —el patrón que el
propio VS Code documenta como *multi-step input*—, con este recorrido:

1. **Rama a revisar** — lista filtrable de candidatas, la actual primera.
2. **Cómo leerla** — tres ítems con descripción: *Automático* (nada), *Commit por
   commit* (`--step`), *Ignorar el walkthrough* (`--no-walk`).
3. **Opciones** (opcional, detrás de un ítem *Más opciones…*) — origen y rango.
4. **Confirmación** — una frase con la review resultante (FR-017).

**Rationale**: el `QuickPick` es la superficie nativa para elegir de una lista y
la que `002` ya eligió para la secuencia de entradas (su Decisión 4): trae
búsqueda incremental gratis, que es lo que FR-011 pide para un repositorio con
cientos de ramas, y no ocupa nada mientras no se usa. Un formulario en el webview
sería superficie propia que hay que dibujar, tematizar y hacer navegable por
teclado a mano, para replicar algo que el host ya hace mejor.

La jerarquía de pasos —lo que casi siempre se acepta primero, lo raro detrás de
una puerta— es lo que impide que la interfaz se convierta en la traducción campo
por campo de la línea de comandos que la spec prohíbe.

**Sobre el paso 2 y lo que NO se ofrece**: no hay ítem "walkthrough". La CLI no
tiene `--walk`: entra en walk sola si el tip trae el sidecar
(`bin/git-review-verbs/start:339`). Ofrecerlo sería prometer un comportamiento
que no existe, y el revisor que eligiera "walkthrough" en un PR sin walkthrough
recibiría una review whole sin entender por qué.

---

## Decisión 10 — Cerrar, pausar y cancelar: botones del panel y el molde de `continue`

**Decisión**: los cuatro verbos restantes son botones en el panel (más su comando
espejo en la paleta), y cada uno reusa exactamente el molde de
`commands/continueReview.ts`: confirmación modal **fuera** del lock, `withProgress`
en la notificación, no cancelable, refresco pase lo que pase, `stderr` de la CLI
en el toast.

Dos particularidades:

- **Dónde quedan las ediciones** (`--onto-source`) se pregunta con un `QuickPick`
  de dos ítems **con descripción**, no con una casilla: la diferencia entre "una
  rama aparte" y "la rama del PR" es justamente lo que hay que explicar antes
  (FR-018), y una casilla rotulada con el nombre del flag no explica nada.
- **`--force`** nunca es una opción ofrecida. Aparece sólo como segunda
  confirmación, después de que la CLI rechazó el deshacer porque hay trabajo
  nuevo, y con el texto de ese rechazo a la vista. Es la traducción exacta del
  riesgo asimétrico: la CLI ya trata a `--force` como un escape que hay que pedir
  a propósito (`bin/git-review-verbs/finish:159-181`), y el panel no lo convierte
  en un clic más.

**Rationale**: el molde existe, está probado y es el precedente que la spec
invoca (`002/FR-033`). Reusarlo mantiene una sola forma de hacer las cosas
peligrosas en todo el panel, que es lo que hace que el usuario aprenda la forma
una vez.

---

## Decisión 11 — La preferencia de origen es un ajuste del host, no estado del producto

**Decisión**: un ajuste `gitReview.defaultSource` con tres valores (`remote` |
`local` | `offline`), declarado en el manifiesto de la extensión.

**Rationale**: VS Code ya resuelve exactamente lo que FR-016a pide —el mismo
ajuste a nivel usuario y sobrescribible por workspace, con la del workspace
ganando— y lo resuelve con una UI de ajustes que el usuario ya sabe usar. Meter
esa preferencia en la config del repositorio la volvería estado del producto:
tendría que reportarse por el contrato, escribirse por el verbo `config` y
sincronizarse, todo para un dato que no cambia el comportamiento de la CLI y sólo
decide qué viene preseleccionado en un diálogo.

La frontera queda nítida y es la que FR-016a exige: **la CLI no sabe que este
ajuste existe**. El ajuste elige qué ítem viene marcado en el paso 3; el
argumento que llega a la CLI sale de lo que el usuario confirmó, siempre.

---

## Decisión 12 — Requisito mínimo de CLI: `0.4.0`

**Decisión**: la extensión pasa a exigir `git review` ≥ `0.4.0` y trata cualquier
versión anterior como el caso "CLI vieja" que ya existe (`002/FR-022`).

**Rationale**: el verbo `config` y los dos registros `finish` son la condición de
posibilidad de todas las acciones nuevas; contra una CLI sin ellos, el panel no
podría describir el estado que sus propios botones producen, que es precisamente
lo que SC-009 prohíbe. El sondeo ya existe y no cambia (`git review --version`,
una línea, versión pelada).

**Consecuencia operativa, ya conocida**: `0.4.0` tiene que estar **publicada**
para que la extensión sea instalable por alguien que no compile la CLI. Es el
mismo bloqueante externo que `002` registró para `0.3.0`.

**Degradación: no hay degradación parcial, y conviene decirlo sin adornos.**
Subir el mínimo significa que contra `0.3.x` la sesión entera entra en
`cli-outdated` — el panel no lee, no navega y no retoma, igual que le pasó a
`0.2.x` cuando `002` subió el mínimo a `0.3.0`
(`src/review/state.ts:163-174`: el chequeo de versión corta antes de invocar
`status`). No es una pérdida silenciosa: es el mismo trato que el producto ya
le da a una CLI vieja, y el aviso dice qué hacer.

Se registra explícitamente porque la tentación es prometer una degradación por
capacidad —que el panel siga leyendo y sólo esconda las acciones nuevas— y eso
sería una segunda forma de decidir qué ofrecer, alimentada por la versión en vez
de por el contrato. SC-009 se cumple igual con el corte duro: el panel no ofrece
nada cuyo resultado no sabría leer, porque no ofrece nada.

**Alternativa considerada**: sondear capacidad en vez de versión (invocar
`config --porcelain` y ver si el verbo existe). Se descartó por lo mismo que la
Decisión 1 de `002`: convierte cada superficie nueva en una rama de código
condicional, y multiplica los estados que hay que dibujar y testear por la
cantidad de versiones de CLI en circulación.

---

## Decisión 13 — Tests: los estados nuevos se construyen con la CLI real, incluido el conflicto

**Decisión**: tres suites, cada una donde corresponde.

- **bats** para todo lo de la CLI: el verbo `config` (lectura, escritura,
  `--unset`, clave desconocida, repositorio sin configurar, paths y nombres de
  rama con bytes hostiles) y los dos registros `finish` (presencia, ausencia,
  compatibilidad hacia atrás de la etiqueta).
- **Unitarios** de la extensión para lo que es función pura: el parser del
  reporte de configuración, el mapeo de los estados nuevos a situación, y la
  derivación de qué acciones ofrece el panel en cada estado.
- **Integración** (`@vscode/test-electron`) para los flujos completos, con
  fixtures construidos **con la CLI del propio checkout** — un fixture de salida
  porcelain escrita a mano probaría el parser contra sí mismo, que es la regla
  que `002` ya fijó (su Decisión 11).

**El caso que hay que saber construir**: el cierre **trabado** exige un conflicto
real entre una edición bancada en modo `--step` y el tip del PR
(`bin/git-review-verbs/finish:406-426`). Es la fixture más cara de esta feature y
la única que no se arma con dos comandos, así que se construye una vez en
`tests/sandbox.sh` —que ya arma una rama por cada estado que el PR de juguete no
puede mostrar— y de ahí se reusa.

**Lo que no se puede testear automáticamente**: la ruta de credenciales de la
Decisión 5 no tiene remoto que pida autenticación en CI. Se cubre con un test que
afirma que el entorno no interactivo **se pasa** (verificable sin red) y con
validación a mano en `quickstart.md`; la alternativa —levantar un servidor git
autenticado en los tres runners— es desproporcionada para una rama de código de
diez líneas.
