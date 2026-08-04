# Contrato: invocaciones permitidas a la CLI (ampliado)

**Este documento enmienda
[`002-extension-vscode/contracts/cli-invocation.md`](../../002-extension-vscode/contracts/cli-invocation.md)**
y, a partir de esta feature, es el que rige. Aquel queda con un puntero a éste:
la regla de FR-001 es que no pueden convivir dos listas vigentes que se
contradigan sobre qué puede invocar la extensión.

Sigue siendo **la lista cerrada** de todo lo que la extensión tiene permitido
ejecutar, y el artefacto contra el cual se verifica SC-005. Lo que cambia:

1. **Se levanta la prohibición de los verbos consecuentes** (`start`, `finish`,
   `save`, `abort`), por el criterio de admisión declarado en la spec de `005`.
   La condición que los excluía en `002` era explícitamente temporal ("en una
   primera versión, donde el usuario todavía no tiene modelo mental").
2. **La lista se vuelve cerrada también en los argumentos** (FR-002). Antes
   acotaba qué verbos; ahora acota además qué flags puede pasar cada uno. Un
   argumento que no esté enumerado acá no puede aparecer en el código: es un gate
   **más** estricto que el de `002`, no uno más laxo.
3. `clean`, `forget` y `walkthrough` **siguen prohibidos**, ahora por criterio
   escrito y no por decisión puntual.

Todo lo que este documento no cambia, se mantiene: la forma de invocación, el
des-citado unidireccional de paths, y el uso acotado de la API de `vscode.git`.

## Forma de toda invocación

Sin cambios respecto de `002`:

```text
spawn(gitPath, ["review", <verbo>, …args], { cwd: RepositoryTarget.rootUri, shell: false, timeout, signal })
```

Con dos precisiones que agrega esta feature:

- **`timeout` depende de la clase** (research.md, Decisión 6): 15 s lectura,
  120 s mutación local, 300 s mutación con red. El valor único de `002` se
  calibró para un `status` y matar un `finish` a mitad es peor que esperar.
- **Entorno no interactivo en la única invocación que toca la red** (`start`):
  `GIT_TERMINAL_PROMPT=0` y los askpass neutralizados, para que un pedido de
  credenciales falle de inmediato con el diagnóstico de git en vez de colgarse
  hasta el timeout.

---

## Invocaciones de lectura (sin efectos)

Las cuatro de `002` siguen igual: `--version`, `status --porcelain`,
`status --why <raw>`, `list --porcelain`. Se agrega una.

### `git review config --porcelain [<rama>]`

**Cuándo**: al abrir el asistente de inicio, y al dibujar el estado vacío cuando
hay que decir contra qué se compararía. **No** en cada refresco: nada de lo que
reporta cambia sin que cambie el repositorio, y el estado con review activa no lo
necesita.

**Argumento opcional**: el `name` de una `candidate`, verbatim, para obtener el
registro `delta` de esa rama. Nunca un valor construido por la extensión.

**Se consume**: registros `config`, `candidate` y `delta`, según
[`config-porcelain.md`](config-porcelain.md). Etiquetas desconocidas y campos
extra al final: **se ignoran**, igual que en los demás.

**Se produce**: la configuración efectiva, las ramas candidatas y la
disponibilidad del rango incremental.

**Es la única fuente de**: la base, el remoto efectivo, qué ramas se pueden
elegir y si hay un punto de referencia previo. Un fallo acá deja el asistente sin
abrirse, con el `stderr` a la vista: no se abre "con lo que había".

---

## Invocaciones mutantes

`next`, `prev` y `continue` siguen exactamente como en `002`. Se agregan seis.
Todas: serializadas por el mismo lock, con `gitReview.busy` activo, **no
cancelables** (FR-037), con confirmación explícita previa (FR-029) y con el
testigo de estado revalidado después de confirmar (FR-038).

### `git review start [--step | --no-walk] [--delta] [--local | --offline] -- <rama>`

**Argumentos permitidos**: exactamente los de arriba, y nada más.

**El `--` no es opcional.** Va siempre, después de todos los flags e
inmediatamente antes del nombre de rama. Sin él, una rama llamada `-foo` —o
cualquiera que empiece con guion— la lee el parseo de opciones del verbo y la
invocación hace algo distinto de lo que el usuario eligió. Es el idiom de git y
el verbo ya lo soporta (`bin/git-review-verbs/start:92-109`); pasarlo siempre, y
no sólo cuando el nombre "parece" una opción, evita una rama de código
condicional que se ejercita una vez cada mil.

| Argumento | De dónde sale | Cuándo se pasa |
|-----------|----------------|----------------|
| `<rama>` | El `name` de una `candidate`, verbatim, precedido por `--` | Siempre, explícito. Nunca se omite para "usar la actual": lo que el usuario eligió se dice. |
| `--base <rama>` | El `name` de una `candidate` | Nunca por ahora. La base sale de la configuración; si falta, se fija con `config` **antes**, no se pasa por línea de comandos — así lo que el revisor eligió queda para la próxima vez (FR-010a). |
| `--step` / `--no-walk` | `ReviewIntent.layout` | Mutuamente excluyentes. `layout = auto` no pasa ninguno. |
| `--delta` | `ReviewIntent.range` | Sólo si el registro `delta` existe para esa rama. |
| `--local` / `--offline` | `ReviewIntent.source` | Mutuamente excluyentes. `source = remote` no pasa ninguno. |

**Prohibidos explícitamente**: `--from <commit>` (no hay superficie que lo
produzca sin un selector de commits, que esta feature no incluye) y el `<base>`
posicional (ambiguo con `<rama>`; si alguna vez hace falta, se pasa por
`--base`).

**Se consume**: el exit code y el `stderr`. **No se parsea la salida humana** —
ni el heads-up del walkthrough, ni la primera entrada, ni las notas. El estado
nuevo sale del `status --porcelain` inmediatamente posterior.

**Notas que igual hay que mostrar**: `start` emite a `stderr` advertencias en
invocaciones **exitosas** (rama local en otro punto que la remota, review previa
con commits nuevos). Se muestran aunque el exit sea `0` (FR-031); no mostrarlas
sería descartar información que la CLI decidió dar.

**Es la única que accede a la red**, y por eso la única con la ruta de
credenciales.

### `git review finish [--onto-source]`

**Argumentos permitidos**: sólo `--onto-source`, y sólo cuando el usuario eligió
esa ubicación en el `QuickPick` de dos ítems.

**Se produce**: un refresco. El estado resultante —cierre completo o cierre
trabado— lo dice el contrato, no la salida del verbo.

### `git review finish --resume [--onto-source]`

**Cuándo**: sólo con `finish conflict` presente en `status --porcelain`. Nunca
"por las dudas": sin ese registro, la CLI responde `nothing to resume`.

**`--onto-source` acompaña** si y sólo si el cierre trabado lo llevaba — dato que
el usuario ya eligió y que la extensión recuerda dentro de la misma sesión de
cierre. Si no lo tiene (el editor se reinició), no se pasa: el default es el
comportamiento por defecto, y equivocarse hacia el default es reversible.

### `git review finish --abort`

**Cuándo**: con `finish pending` o `finish conflict` presente.

**Se consume**: el exit code y el `stderr`. Un rechazo por trabajo nuevo en la
rama del cierre es un fallo **esperado**, no un error a esconder: su `stderr` es
lo que se muestra, y es lo que habilita la segunda confirmación de abajo.

### `git review finish --abort --force`

**Cuándo**: **únicamente** después de que la invocación anterior falló por trabajo
nuevo, y de una **segunda** confirmación distinguible de la primera, con el texto
del rechazo a la vista.

**Nunca**: como reintento automático, como opción ofrecida de entrada, ni como
casilla del primer diálogo. Es la traducción del riesgo asimétrico que la CLI ya
aplica (`bin/git-review-verbs/finish:159-181`).

### `git review save`

**Sin argumentos** — el verbo no acepta ninguno.

**Se produce**: un refresco. La review pasa al inventario como `saved`, donde
`continue` (ya permitida desde `002`) la recupera. Es la inversa exacta, y el
motivo por el que `save` cumple el criterio de admisión sin discusión.

### `git review abort`

**Sin argumentos**.

**Confirmación**: la más fuerte de todas junto con `--force`. Descarta las
ediciones no guardadas del working tree, y eso se dice con esas palabras antes de
ocurrir (FR-023).

### `git review config <clave> <valor>` / `git review config --unset <clave>`

**Cuándo**: por acción explícita del usuario, al fijar o limpiar la base desde el
panel.

**Argumentos permitidos**: `<clave>` sólo de la lista cerrada del contrato
(`base`, `remote`); `<valor>` sólo el `name` de una `candidate`, verbatim,
precedido por `--` por el mismo motivo que en `start`. **Nunca** un valor
tipeado a mano sin pasar por el listado, y nunca una clave construida.

**Por qué está permitida** cuando `002` prohibía escribir configuración: la
prohibición de `002` era sobre que **la extensión** escribiera config —mover el
lugar de almacenamiento a su código—. Acá la escribe la CLI: el consumidor pide
"fijá la base en esta rama" y no sabe ni le importa dónde termina guardado. La
frontera es la misma; lo que cambió es que ahora hay un verbo del otro lado.

---

## Prohibiciones explícitas (actualizada)

| Prohibido | Por qué |
|-----------|---------|
| Leer `branch.review/*.review*`, `reviewworkflow.*` u otra config de git | FR-004 — es estado del producto, y es de la CLI |
| Leer o escribir `refs/review-edits/*`, `refs/review-saved-edits/*`, `refs/review-undo/*` | FR-004, FR-005 |
| Determinar el modo, la posición, la secuencia o el estado de un cierre mirando ramas o refs | FR-004 |
| **Enumerar ramas del repositorio por cualquier vía que no sea el registro `candidate`** | FR-009a — incluida la API de `vscode.git`, cuya excepción sigue acotada a dos cosas |
| Parsear `.review/walkthrough.md` | Sigue habiendo dos únicos puntos de normalización de paths |
| Escribir config, mover refs o tocar el índice **directamente** | FR-005 — vía el verbo `config` sí; a mano no |
| Parsear la salida humana de cualquier verbo | El contrato existe para no hacer esto — ver "Clasificar no es parsear" abajo |
| Invocar `clean`, `forget`, `walkthrough`, `compare`, `preview` | Criterio de admisión: `clean`/`forget` no tienen inversa; `walkthrough` es flujo de autor; `compare`/`preview` no participan del ciclo |
| Pasar un argumento no enumerado en este documento | FR-002 — la lista es cerrada también en los argumentos |
| Pasar `--force` sin la segunda confirmación | FR-021 |
| Re-citar un `PathRef.display` para pasárselo a la CLI | Decisión 8 de `002` — el des-citado es unidireccional |

**Único uso permitido de la API de `vscode.git`** (sin cambios respecto de
`002`): descubrir la raíz del repositorio y recibir la señal de que algo cambió.
Ningún campo del view-model puede alimentarse de ahí — y a partir de esta feature
se explicita que **tampoco la lista de ramas**, que era el candidato natural a
convertirse en la primera excepción.

---

## Clasificar no es parsear

La prohibición de parsear salida humana se vuelve ambigua en un solo punto —
`start` es la única invocación que propaga el `stderr` de **git**, y decidir si
ofrecer *Run in Terminal* implica mirarlo. La frontera queda fijada acá para no
tener que re-deducirla:

| Permitido | Prohibido |
|-----------|-----------|
| Clasificar el `stderr` de **git** que un verbo propaga, para elegir qué acción ofrecer junto al mensaje | Leer la salida de **un verbo de `git review`** para derivar cualquier cosa sobre el estado de la review |
| Mostrar ese `stderr` verbatim, siempre | Reemplazarlo, resumirlo o condicionarlo a haberlo entendido |

La prueba que separa los dos casos: **si la clasificación se equivoca, ¿cambia
algún campo del view-model?** Con el `stderr` de git, no — el usuario ve el mismo
texto con un botón de más o de menos. Con la salida de un verbo, sí, y por eso
existe el contrato porcelain.

Corolario operativo: cuando el estado *sí* importa —qué quedó después de un
`finish`, si hubo ediciones que extraer, dónde está el cursor— la respuesta sale
siempre de volver a preguntarle al contrato, nunca del texto que el verbo
imprimió. En particular, "no había ediciones que extraer" se deriva de la
**ausencia** de un cierre `pending` en el refresco posterior, no del mensaje que
la CLI escribe en ese caso.
