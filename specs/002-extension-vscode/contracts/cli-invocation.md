# Contrato: invocaciones permitidas a la CLI

Este documento es **la lista cerrada** de todo lo que la extensión tiene
permitido ejecutar. Es el artefacto contra el cual se verifica SC-005 ("ninguna
funcionalidad del panel deriva estado de review por fuera de la CLI; una
revisión del código lo verifica"): si en el código aparece una invocación que no
está acá, o una lectura de config/refs/ramas para derivar estado de review, la
revisión falla.

Es el lado consumidor del contrato de
[`001-contrato-porcelain`](../../001-contrato-porcelain/contracts/status-porcelain.md),
que sigue siendo la fuente normativa del formato. Acá sólo se fija **qué se
invoca, cuándo y qué se hace con el resultado**.

## Forma de toda invocación

```text
execFile(gitPath, ["review", <verbo>, …args], { cwd: RepositoryTarget.rootUri, shell: false, timeout, signal })
```

- `shell: false` es obligatorio: los paths viajan como argv, sin re-parseo
  (Decisión 3 de `research.md`).
- `cwd` es siempre la raíz del repositorio objetivo, nunca el cwd del proceso
  del editor.
- `gitPath` es `git`, salvo que el ajuste `gitReview.path` apunte al dispatcher.
- Toda invocación es cancelable y tiene timeout.

---

## Invocaciones de lectura (sin efectos)

Garantizadas libres de mutación por FR-022 de la feature 001.

### `git review --version`

**Cuándo**: una vez por activación y al reintentar tras un `cli-missing`.

**Se consume**: la única línea de stdout, versión pelada (`0.3.0`).

**Se produce**: `Situation.cli-outdated` si es menor que `0.3.0`;
`Situation.cli-missing` si el proceso falla con `ENOENT` o git no reconoce el
subcomando.

### `git review status --porcelain`

**Cuándo**: en cada refresco — activación, evento de cambio del repositorio,
después de cada invocación mutante propia, y a pedido del usuario.

**Se consume**: registros `state` (uno), `entry` (cero o más). Etiquetas
desconocidas y campos extra al final: **se ignoran** (FR-003).

**Se produce**: el árbol entero salvo los `Why`. Exit `0` → `review`; `2` →
`no-review`; `3` → `out-of-range`; `1` u otro → `error`, con el stderr
preservado.

**Es la única fuente de**: modo, posición, total, total registrado, entrada
actual, esencialidad, si una entrada está anotada en el walkthrough (`entry.
annotated` — un archivo del rango sin entrada propia se agrega al final de la
secuencia, no se reporta aparte), y situación del walkthrough.

### `git review status --why <raw>`

**Cuándo**: sólo bajo demanda — al hacer hover sobre una entrada
(`resolveTreeItem`) o al pedir la lectura completa. **Nunca** al construir el
árbol: la feature 001 separó el *why* de la secuencia justamente para eso (su
FR-014) y SC-002 acota la vista completa a 3 invocaciones.

**Argumento**: `PathRef.raw`, verbatim. Nunca `display`.

**Se consume**: stdout completo como payload, sin framing.

**Se produce**: `Why`. Vacío con exit `0` → `present = false`; exit `1` → fallo,
que es un estado distinto (FR-018).

### `git review list --porcelain`

**Cuándo**: sólo con `Situation.no-review` — el estado vacío del panel es el
único lugar que muestra el inventario. Estando dentro de una review no se
invoca: `status --porcelain` ya reporta la que importa, y agregar un proceso a
cada refresco por información que no se dibuja iría contra SC-002.

**Se consume**: registros `branch` (cero o más), según
[`001-contrato-porcelain`](../../001-contrato-porcelain/contracts/list-porcelain.md).
Etiquetas desconocidas y campos extra al final: **se ignoran**, igual que en
`status` (FR-003).

**Se produce**: el inventario de reviews del repositorio, activas y guardadas.
Exit `0` siempre que sea un repositorio git — un inventario vacío es un
resultado válido, no un error, así que **no** hay `Situation` propia: un fallo
acá deja el estado vacío como estaba antes de esta iteración, sin inventario.

**Es la única fuente de**: qué reviews existen fuera de la rama actual, su modo
y su posición registrada.

**El `name` viaja de vuelta a la CLI**, y es el único valor del que eso vale:
`porcelain_row` (`bin/git-review-lib.sh:23`) no escapa nada y git prohíbe tabs,
espacios y caracteres de control en un nombre de rama, así que el campo es el
nombre byte por byte. Quitarle el prefijo `review/` o `review-saved/` reconstruye
el argumento de `continue`. No aplica la Decisión 8: ésa es sobre paths citados,
que sí pasan por `unquote`.

---

## Invocaciones mutantes

Las únicas tres. Serializadas y con `gitReview.busy` activo mientras corren
(FR-020, Decisión 9).

### `git review next` / `git review prev`

**Cuándo**: por acción explícita del usuario desde el panel o la paleta.

**Se consume**: el exit code y el stderr. **No se parsea la salida humana** —
ni para saber dónde quedó el cursor ni para nada. La posición nueva se obtiene
del `status --porcelain` que corre inmediatamente después.

**Se produce**: un refresco, y la apertura del archivo de la entrada resultante
(FR-015).

**Límites de la secuencia**: lo que la CLI responda al intentar pasarse del
final o del principio se propaga tal cual, sin comportamiento propio (FR-016).
En un extremo la CLI **no falla**: imprime su aviso (`no more entries — run git
review finish`) en **stdout** y sale con 0, dejando el cursor donde estaba. La
extensión detecta ese caso comparando la `position` de antes con la del
`status --porcelain` de después —nunca leyendo el texto del verbo (FR-015)— y
muestra ese mismo aviso, el de la CLI y no uno redactado acá. Sin eso el
comando sería mudo, que es lo contrario de propagar.

### `git review continue <src>`

**Cuándo**: por acción explícita del usuario desde el inventario del estado
vacío, y sólo sobre una fila `saved`. Nunca sin argumento: sin él el verbo
resume la única guardada o falla listando las demás
(`bin/git-review-verbs/continue:66`), y cuál resumir ya lo eligió el usuario.

**Argumento**: el `name` del registro `branch` sin su prefijo `review-saved/`.
El verbo espera el nombre *source* (`feature/checkout`), no el de la rama.

**Se consume**: el exit code y el stderr. **No se parsea la salida humana**
("resumed review of …"), igual que con `next`/`prev`: el estado nuevo lo da el
`status --porcelain` que corre inmediatamente después.

**Se produce**: un refresco. La invocación cambia `HEAD` —crea `review/<src>`,
restaura las ediciones en el working tree y borra `review-saved/<src>`—, así que
va detrás de una confirmación explícita, a diferencia de `next`/`prev`.

**Por qué está permitida** cuando `start` no lo está: no toca la red (no hay
`fetch`), y es la inversa exacta de `save`, que la deshace. El riesgo es
simétrico; el de `start` no.

**Fallos que no se anticipan**: de los tres modos de fallo del verbo, dos se
leen del propio inventario y deshabilitan el botón — que `review/<src>` ya esté
activa (fila activa y fila guardada para el mismo source) y que la rama sea
huérfana (`orphan = 1`). El tercero, el working tree sucio
(`bin/git-review-verbs/continue:84`), **sólo lo sabe git**: anticiparlo sería
derivar por afuera de la CLI. Se deja fallar y se muestra su stderr tal cual
(FR-024).

---

La extensión **no** decide si el cursor se mueve: eso sigue siendo del verbo.
Lo que sí hace el panel es deshabilitar el botón cuyo destino no existe, leyendo
la `position`/`total` que la CLI ya reportó (`atFirst`/`atLast` del
`PanelModel`) — la misma lectura que ya dibuja `2/3` en la barra, no una segunda
implementación de la regla. La paleta y cualquier otra superficie siguen
pudiendo invocar el verbo en un extremo, y ahí el aviso es la respuesta.

---

## Prohibiciones explícitas

Lo que sigue **no** puede aparecer en el código de la extensión. Cada línea es
un ítem verificable de la revisión de SC-005.

| Prohibido                                                                    | Por qué                                                                              |
|------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| Leer `branch.review/*.review*` u otra config de git                          | FR-001 — es el estado de la review, y es de la CLI                                   |
| Leer o escribir `refs/review-edits/*`, `refs/review-saved-edits/*`           | FR-001, FR-002                                                                       |
| Determinar el modo, la posición o la secuencia mirando ramas o refs          | FR-001                                                                               |
| Parsear `.review/walkthrough.md`                                             | El proyecto tiene dos únicos puntos de normalización de paths; esto sería el tercero |
| Escribir config, mover refs o tocar el índice                                | FR-002                                                                               |
| Parsear la salida humana de cualquier verbo                                  | El contrato existe para no hacer esto                                                |
| Invocar `finish`, `abort`, `save`, `start`, `clean`, `forget`, `walkthrough` | Fuera de alcance por decisión del spec (riesgo asimétrico)                           |
| Re-citar un `PathRef.display` para pasárselo a la CLI                        | Decisión 8 — el des-citado es unidireccional                                         |

`continue` queda deliberadamente fuera de esa fila: es la única mutante que la
lista **no** prohíbe, por el riesgo simétrico explicado más arriba. Que falte no
es una omisión que se pueda leer como permiso tácito para las otras — cualquier
verbo que no esté en la sección de mutantes sigue prohibido.

**Único uso permitido de la API de `vscode.git`**: descubrir la raíz del
repositorio y recibir la señal de que algo cambió. Ningún campo del view-model
puede alimentarse de ahí (Decisión 7).
