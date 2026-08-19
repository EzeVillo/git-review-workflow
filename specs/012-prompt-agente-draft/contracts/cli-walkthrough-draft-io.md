# Contrato: `walkthrough draft` sin escribir en el gitdir

**Feature**: `012-prompt-agente-draft`

Enmienda a
[`011-walkthrough-draft-revisor/contracts/cli-walkthrough-draft.md`](../../011-walkthrough-draft-revisor/contracts/cli-walkthrough-draft.md).
Describe el delta: dos flags nuevos. Todo lo demás —resolución de rama y rango,
reglas de validación, efecto sobre los otros verbos— no cambia.

## Invocación

```sh
git review walkthrough draft [--local | --offline] [--delta] [--force] [--stdout] [--] [<branch>]
git review walkthrough draft --build [--from <file> | --from -] [--local | --offline] [--delta] [--force] [--] [<branch>]
```

| Flag | Significado |
| --- | --- |
| `--stdout` | Emitir el esqueleto por la salida estándar. **No escribe nada, en ninguna parte.** |
| `--from <file>` | Con `--build`: leer el borrador de `<file>` en vez del archivo canónico. |
| `--from -` | Con `--build`: leerlo de la entrada estándar. |

### Matriz de compatibilidad

Todas las combinaciones ilegales son **error de uso** (exit 1, mensaje en
stderr, `usage` no se imprime salvo donde ya se imprime hoy), verificadas antes
de tocar nada:

| Combinación | Resultado |
| --- | --- |
| `--stdout` + `--build` | `error: --stdout writes the skeleton; --build validates one. Use one or the other` |
| `--stdout` + `--force` | `error: --stdout writes no file, so there is nothing to force` |
| `--stdout` + `--from` | `error: --from applies only to git review walkthrough draft --build` |
| `--from` sin `--build` | `error: --from applies only to git review walkthrough draft --build` |
| `--from` dos veces | `error: --from given more than once` |
| `--from` sin valor | `error: --from requires a file (or - for standard input)` |
| `--build --force` sin `--from` | **sin cambios**: sigue siendo el error de hoy |
| `--stdout` en `init`/`build` | `error: --stdout ... apply only to git review walkthrough draft` (se suma a la guarda que ya existe) |

## `--stdout` — el esqueleto por la salida estándar

**Comportamiento**: idéntico a la creación, hasta el `mv`, que no ocurre, **con
una diferencia deliberada en el andamiaje**: la línea de cierre que le dice a
quien anota cómo validar.

### La línea de cierre conmuta

El esqueleto cierra hoy con una instrucción de validación
([walkthrough:463](../../../bin/git-review-verbs/walkthrough)):

```text
     Then validate and write with:  git review walkthrough draft --build <flags> <branch>
```

Bajo `--stdout` esa línea es **falsa y peligrosa**, y hay que cambiarla:

```text
     Then validate and install with:
       git review walkthrough draft --build --from <file> <flags> <branch>
     (or --from - to read it from standard input)
```

Por qué no puede quedar como está: con `--stdout` no se escribió ningún archivo,
así que un agente que siga la línea original corre un `--build` **sin `--from`**
y pasa una de dos cosas — muere con `no draft for <branch>`, que al menos es
ruidoso; o, si esa rama ya tenía un borrador de antes, **valida ese otro archivo
y lo reescribe**, ignorando por completo lo que el agente acaba de producir, con
exit 0 y un mensaje de éxito. Es exactamente el fallo silencioso que esta feature
existe para eliminar, y estaría escrito por nosotros en el archivo que el agente
recibe.

El contenido que sale por stdout es, salvo esa línea, **byte por byte** el que el
archivo tendría.

| Condición | Salida | Exit |
| --- | --- | --- |
| Éxito | El esqueleto por **stdout**; las notas de siempre (guía de autoría, precedencia sobre el walkthrough del autor, archivado huérfano) por **stderr** | `0` |
| Ya existe borrador | **Se imprime igual.** Imprimir no destruye: la protección contra sobrescribir es del que escribe, no del que muestra (edge case de la spec) | `0` |
| Sin `reviewworkflow.base`, rama/tip inexistente, sin cambios vs la base, `--delta` sin marcador | Los mismos mensajes accionables de hoy. **Nunca se imprime un esqueleto vacío** | `1` |
| Nombre de rama no usable como archivo (`nul`, `aux`, `com1`) | **Éxito**: no se escribe ningún archivo, así que la restricción no aplica (edge case de la spec) | `0` |

**Invariantes**:

- No se crea, se modifica ni se borra **ningún** archivo, tampoco un temporal.
  Concretamente: no se ejecuta el `mkdir -p`, ni el `: >"$tmp"`, ni el `mv`, y
  no se instalan los traps de limpieza.
- El índice, el árbol de trabajo y las refs quedan idénticos.
- La línea informativa que la creación imprime («wrote … with N file(s) …»)
  **no** se emite: por stdout sale sólo el esqueleto, para que
  `git review walkthrough draft --stdout feature/x > /tmp/x.md` sea un archivo
  válido sin filtrar nada. El recuento de archivos, si se quiere, va a stderr.

## `--build --from` — instalar contenido externo

**Comportamiento**: exactamente el `--build` de hoy, con `$content` leído de
otra fuente. Las ocho reglas de validación se aplican **sin una de más ni una
de menos** (FR-013), contra el mismo rango resuelto por los mismos flags de
origen y rango.

| Condición | Salida | Exit |
| --- | --- | --- |
| Válido, sin borrador previo | Instala en la ubicación canónica y reescribe canónicamente. `built <ruta>: N entries[ (K key)], ordered and renumbered; git review start … now reads it` | `0` |
| Válido, con borrador previo y `--force` | Lo mismo, reemplazando | `0` |
| Válido, con borrador previo, **sin** `--force` | `error: <ruta> already exists; pass --force to overwrite` — **y no se instala nada** | `1` |
| `<file>` inexistente o ilegible | `error: could not read <file>` — nombrándolo, sin tocar el borrador que hubiera (FR-018) | `1` |
| Entrada vacía o de puro espacio en blanco | `error: <origen> is empty; a reading order needs at least one entry` (FR-015) | `1` |
| `--from -` con stdin en una terminal, sin redirección | `error: --from - reads the draft from standard input; redirect a file into it (git review walkthrough draft --build --from - <branch> < order.md) or pass --from <file>` (FR-017) | `1` |
| Cualquier rechazo de validación | El mensaje específico de esa regla | `1` |

### Orden de las guardas

Fijado, porque de él dependen FR-014 y FR-016:

1. Compatibilidad de flags.
2. Resolución de rama, base, tip, rango. (Los errores de acá no leen nada.)
3. **Existencia del borrador previo vs `--force`.** Antes de leer la entrada:
   negarse después de consumir stdin deja al llamador sin forma de reintentar.
4. Lectura de la fuente → `walk_normalize` → `$content`.
5. Vacío / puro espacio en blanco.
6. Las ocho reglas de validación.
7. `mkdir -p` del namespace, escritura del temporal, `mv`.

**Atomicidad (FR-014, SC-004)**: el paso 7 es la **única** escritura. Cualquier
fallo anterior deja el borrador previo byte por byte como estaba. Eso ya es
verdad del `build` actual ([walkthrough:700-759](../../../bin/git-review-verbs/walkthrough));
lo que hay que sumar en el paso 7 es lo que hoy sólo vive en la rama del
esqueleto:

- `mkdir -p "$(dirname "$targetpath")"` — el namespace puede no existir;
- la guarda de nombre de archivo reservado (`if ! : >"$tmp"`), con el mismo
  mensaje que ya existe;
- los traps `EXIT` / `INT` / `TERM`, para que un Ctrl-C no deje un `.tmp.NNN`
  que nada recoge (`walk_draft_list` sólo matchea `*.md`, `clean` es hands-off
  ahí y `forget --draft` sólo sabe deletrear nombres).

### Lectura de la fuente

- `--from <file>`: `walk_normalize <"$file"`, con la comprobación de legibilidad
  hecha antes para poder nombrar el archivo en el error.
- `--from -`: `walk_normalize` sobre stdin, precedido de la guarda `[ -t 0 ]`
  —POSIX y builtin, cero procesos.

En los dos casos la normalización es la de siempre (CR final, BOM UTF-8): un
agente que escriba desde PowerShell produce las dos cosas, y sin esto el drift
nombraría el mismo archivo de los dos lados.

## Lo que no cambia

- La ubicación canónica del borrador, y por lo tanto la precedencia sobre el
  walkthrough del autor, `reviewdraft`, `reviewwalkfromdraft`, el archivado al
  pausar, la restauración al retomar, `forget`, el informe de estado, las
  ofertas de lectura y el guard de metadata de `finish` (FR-012).
- Ninguna regla de validación (FR-013).
- El comportamiento de `walkthrough draft` y `draft --build` sin los flags
  nuevos: byte por byte el de hoy.

## Tests (bats — `tests/walkthrough-draft-io.bats`)

| Caso | Afirma |
| --- | --- |
| `--stdout` no crea nada | `find`-libre: el namespace no existe antes ni después; `git status --porcelain` idéntico; exit 0 y stdout no vacío |
| `--stdout` == el archivo, salvo la línea de cierre | Escribir con el verbo y comparar con la salida capturada: idénticos **excepto** esa línea |
| La línea de cierre de `--stdout` manda `--from` | La salida contiene `--build --from` y **no** contiene un `--build` sin `--from`. Sin esta aserción, la conmutación se puede caer sin que nada falle |
| Seguir la línea de cierre instala lo del agente | Capturar `--stdout`, llenarlo, correr **el comando literal que la salida imprime**, y afirmar que el borrador canónico es el llenado. Es el test que cubre el fallo silencioso completo, no sólo el texto |
| `--stdout` sobre una rama con borrador | Exit 0, imprime, y el borrador queda byte por byte igual |
| `--stdout` con `nul` de nombre de rama | Exit 0 (no se escribe nada) |
| `--stdout` sin base / rama inexistente / sin cambios | Exit 1, el mensaje de siempre, stdout **vacío** |
| Instalar desde archivo | Exit 0; el archivo canónico existe con el contenido renumerado; `git review start` entra en walk sobre él |
| Instalar desde stdin | Resultado **idéntico** al anterior (comparación byte por byte de los dos archivos canónicos) |
| Paridad de custodia | Tras instalar por las dos vías: `status` dice `walk (draft)`, `list` marca la fila, `save`/`continue` mueven el archivo, `forget --draft` lo borra |
| Sin `--force` sobre un borrador existente | Exit 1, mensaje, **y el borrador anterior byte por byte igual** |
| Con `--force` | Exit 0, reemplazado |
| Entrada vacía | Exit 1, mensaje accionable, borrador anterior intacto |
| Entrada de puro whitespace | Ídem |
| Entrada que no valida (placeholder, duplicado, drift, `> key` con valor) | Exit 1, el mensaje de esa regla, **borrador anterior intacto** |
| Archivo inexistente | Exit 1, el mensaje nombra el archivo, borrador intacto |
| Archivo ilegible (permisos) | Ídem — se salta en Windows |
| `--from -` con stdin de terminal | No cuelga: exit 1 con la explicación. Se prueba sin TTY forzando la rama con un `--from -` cuyo stdin es `/dev/tty` no disponible, o afirmando el mensaje bajo `script`/redirección según lo que el runner permita |
| Toda la matriz de flags ilegales | Exit 1, el mensaje de cada uno, y ningún efecto |
| CRLF y BOM en la fuente | Instala igual, sin drift |
| El namespace no existe | Se crea (`mkdir -p`), incluido un nombre con `/` |
