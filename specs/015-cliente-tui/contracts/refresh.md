# Contract: El refresco (cliente TUI)

**Consumidor normativo**: `tui/internal/host/{watch,watchset,lock}.go` +
`tui/internal/domain/watchrules.go`

Los paneles de IDE se enteran porque el host les avisa. **La TUI no tiene host**, así que el aviso
hay que construirlo. Este contrato fija qué se vigila, cómo se arma y rearma, cómo se debouncea y
coalesce, cómo se serializa contra el lock de mutación y **cómo se apaga entero**.

La regla que gobierna todo lo demás: **la vigilancia es un acelerador, no un cimiento** (FR-063). No
sostiene ningún requisito. Si se apaga, la TUI sigue siendo completamente correcta y sólo tarda más
en enterarse.

## Los cuatro disparadores

| # | Disparador | Se suprime por el lock | Puede faltar |
|---|---|---|---|
| 1 | **Acción propia** — terminó una invocación que lanzó la TUI | no (es el refresco del lock) | no |
| 2 | **Evento de archivo** | **sí** | sí (montaje de red, bind mount, backend sin `refs/`) |
| 3 | **Focus-in** (`tea.FocusMsg`) | no | sí (tmux con `focus-events off`, terminal sin soporte) |
| 4 | **Tecla `r`** | no | **nunca** — disponible en las ocho situaciones (FR-038) |

**No se pollea** (FR-032). El único poll del sistema es el piso opt-in del final de este documento,
que está apagado por default y nunca se presenta como el mecanismo.

Disparador 3: se pide con `tea.WithReportFocus()`. Si el terminal o el multiplexor no lo entregan,
**no llega ningún mensaje** — la degradación es silencio, no un error, y no hay nada que detectar
(FR-037). **La TUI no le dice al usuario que encienda `focus-events`**: sería copy nombrando un
mecanismo, y la regla de §15 lo prohíbe.

## Qué se vigila

### Las seis raíces (FR-033, FR-080)

| # | Raíz | De dónde sale | Filtro |
|---|---|---|---|
| A | `<git-common-dir>/` | `git rev-parse --git-common-dir` | **sólo** `config` y `packed-refs` |
| B | `<git-common-dir>/refs/` | idem | ninguno |
| C | `<git-common-dir>/reftable/` | idem, **si existe** | ninguno |
| D | `<git-dir>/review-walkthrough/` | el path del registro `draft` que la CLI reportó (FR-036) | `*.md` |
| E | `<git-dir>/review-saved-walkthrough/` | idem | `*.md` |
| F | `<git-dir>/` | `git rev-parse --git-dir` | **sólo** `HEAD` |

**La raíz F va sobre `<git-dir>` y no sobre el común** porque cada worktree tiene su propio `HEAD`, y
el que le importa al panel es el del worktree donde estás parado (FR-080).

**Es la misma forma que A, no un mecanismo nuevo**: un directorio vigilado, filtrado por nombre de
archivo. Y `HEAD` es de lo menos frágil que hay para mirar — junto con `config`, es parte de la
disposición **documentada** del repositorio (`gitrepository-layout`). Lo frágil de verdad es el
empaquetado de refs y el backend alternativo, que este contrato ya trata como best-effort.

Cubre el evento que **más** cambia lo que el panel muestra: toda la sesión de review es por rama, así
que un `git checkout` en otro pane cambia el panel entero. Y `git checkout` escribe `HEAD` con el
mismo rename atómico (`HEAD.lock` → `HEAD`) que `git config`, así que el mecanismo del agujero 1 lo
cubre sin agregar nada.

**Dedup: el conjunto está indexado por directorio, y el filtro de un directorio repetido es la unión
de sus filtros.** Fuera de un worktree enlazado, `--git-dir` y `--git-common-dir` resuelven al mismo
lugar: A y F son **una sola** entrada con filtro `{config, packed-refs, HEAD}` (FR-080: «la raíz MUST
contarse una sola vez»). Adentro de un worktree enlazado son dos directorios distintos con dos
filtros distintos, y ahí no hay nada que unir.

`<git-dir>` y `<git-common-dir>` **se piden a git**, no se arman: en un worktree enlazado son
distintos, y vigilar el equivocado deja media pantalla muerta (edge case de la spec). Una sola
invocación los trae:

```text
git rev-parse --git-dir --git-common-dir --show-toplevel
```

Los paths relativos se resuelven contra el `cwd` del proceso. `--path-format=absolute` **no se usa**:
es de git 2.31 y el proyecto declara 2.23+.

### El cierre sobre directorios (agujero 3)

Las seis raíces son las **semillas**. El conjunto vigilado es su cierre sobre **directorios**, y eso
no es recursión en vivo: es una derivación con presupuesto, que se rehace cuando cambia.

| Raíz | Profundidad | Allowlist de prefijos |
|---|---|---|
| A | 0 (la raíz sola) | — |
| B `refs/` | 3 | `heads/`, `remotes/`, `review-edits/`, `review-saved-edits/` |
| C `reftable/` | 0 (es plano por diseño) | — |
| D, E | 3 | — |
| F | 0 (la raíz sola) | — |

**La raíz nueva no mueve el presupuesto.** Es de profundidad 0 y con filtro por nombre, igual que A:
suma **una** entrada en un worktree enlazado y **cero** fuera de él (ahí se funde con A por el dedup).
`max_dirs` sigue en 512 y la allowlist de `refs/` no cambia — F no descuelga ningún subárbol, y los
dos directorios de borradores (D y E) siguen siendo raíces propias con su profundidad 3, porque el
filtro `{HEAD}` de F no los alcanza aunque vivan adentro del mismo `<git-dir>`.

Cada entrada agregada es un **directorio**; ninguna es un ref. Por eso el cierre no contradice
"vigilar contenedores, no refs finos": lo que hace es descubrir los contenedores hijos.

**Por qué hace falta, con nombres del repo**:

- `refs/heads/review/<branch>` — la rama de una review. El directorio `refs/heads/review/` nace con
  la primera review y muere con la última.
- `refs/review-edits/<src>/<step>` — dos niveles, y `<src>` puede traer barra (`feature/foo`), así
  que en la práctica son tres.
- `review-walkthrough/<src>.md` — `walk_draft_path` compone el `<src>` **crudo**, así que un
  borrador de `feature/foo` vive en `review-walkthrough/feature/foo.md`. `walk_draft_list`
  recursiona por eso mismo.

**Y por qué no alcanza con vigilar `config`**: `branch.<rb>.reviewdraft` la escriben `start` y
`compare`. `walkthrough draft` fuera de una review **no escribe config**, así que el nacimiento de un
borrador —el escenario 3 de la User Story 1, el agente llenándolo— sólo es visible por D/E.

**Presupuesto** (`max_dirs`, valor inicial 512): al pasarse, se conservan las semillas y las entradas
más someras, y se deja una nota en el registro de invocaciones. **Nunca es un error** (FR-064).

### Prefijos deliberadamente excluidos

`refs/tags/`, `refs/notes/`, `refs/stash`, `refs/bisect/`, `refs/rewritten/`. Ninguno participa del
estado de una review, y `tags/` en un repo grande es la mitad del presupuesto.

### La ráfaga de `HEAD`, y qué la acota

`HEAD` es la única raíz con una ráfaga plausible: un `rebase` en otro pane lo reescribe una vez por
commit, y un `next`/`prev` en modo step hace un checkout por paso. **El techo del debounce es lo que
la acota**: durante un rebase de cuarenta commits el panel lee a lo sumo una vez por segundo, no
cuarenta veces. Y cuando el checkout lo causó una mutación de la propia TUI, lo absorbe la ventana de
silencio.

Es el mismo par de mecanismos que ya existía —no hay nada nuevo que agregar por la raíz nueva—, y es
el motivo por el que el techo de 1 s no es opcional.

### Lo que queda sin cubrir

Con la sexta raíz, **todos los eventos que mueven lo que el panel muestra tienen un camino**: `config`
y `packed-refs` por A, los refs por B/C, los borradores por D/E, la rama por F. Lo que queda afuera es
lo que este contrato ya trata como best-effort por diseño:

- **inotify que no dispara** (bind mount Windows→WSL, varios NFS/SMB): el agujero 5, que falla en
  silencio y se compensa con los otros tres disparadores y con el piso de poll opt-in.
- **El índice y el working tree**: no se vigilan, y no hace falta — el panel no reporta estado del
  árbol, y lo que sí depende de él (que `finish` se niegue con el árbol sucio) lo contesta la CLI
  cuando se la invoca, no el panel de antemano.

En los dos casos el costo es latencia, no incorrección: FR-063 hace que un evento no visto sea
«tarda más en enterarse», nunca «muestra algo falso».

## Los cuatro agujeros, cada uno con su mecanismo y su test

| # | Agujero | Mecanismo | Test (FR-058) |
|---|---|---|---|
| 1 | **Rename atómico** — `git config` escribe `config.lock` y renombra; un watch sobre el *archivo* deja de disparar cuando el inode se reemplaza | vigilar el **directorio** A y filtrar por nombre. Idem `packed-refs`, e idem `HEAD` en la raíz F: `git checkout` escribe `HEAD.lock` y renombra igual | escribir `reviewworkflow.base` con `git config` y afirmar que llegó un evento; repetirlo **dos veces** (el segundo prueba que el watch sobrevivió al primer rename). Lo mismo con dos `git checkout` seguidos contra la raíz F |
| 2 | **Refs empaquetados** — `git gc` / `git pack-refs` mueven los refs sueltos a `packed-refs` | A los cubre por nombre; B por la desaparición de los archivos | crear una review, `git pack-refs --all`, afirmar evento; después `git update-ref -d` de un ref empaquetado |
| 3 | **Anidamiento** — `refs/review-edits/<src>/<step>` y `review-walkthrough/<src>.md` con `<src>` con barra | el cierre sobre directorios, con rehecho al nacer un subdirectorio | escribir un borrador para la rama `feature/foo` con la TUI ya arrancada, y afirmar que llegó **un** evento; ídem crear una review de `feature/foo` en modo step y avanzar un paso |
| 4 | **Backend `reftable`** — no existe el directorio `refs/` | raíz C, y B ausente se ignora en silencio | inicializar un repo con `--ref-format=reftable`, arrancar, afirmar que no hubo error de arranque y que una mutación dispara |

Y el quinto, que no es un agujero sino un modo de falla del sistema:

| 5 | **inotify no dispara** (bind mount Windows→WSL, varios NFS/SMB) — **falla en silencio** | no se detecta; se compensa con los disparadores 1, 3 y 4, y con el piso de poll opt-in | montar el repo de prueba donde el watcher no dispara no es reproducible en CI: el test es el de **FR-074** (la suite entera con la vigilancia apagada), que es la misma condición llevada al extremo |

Test adicional que FR-058 pide explícitamente: **worktree enlazado**. Crear `git worktree add`,
arrancar la TUI adentro, y afirmar tres cosas: que los eventos del **directorio común** (config,
packed-refs) llegan, que los del borrador salen del gitdir **del worktree**, y que un `git checkout`
en **ese** worktree dispara mientras que uno en el worktree principal **no** — que es lo que prueba
que la raíz F está sobre `<git-dir>` y no sobre el común.

Y el test del dedup, que es barato y protege una propiedad fácil de romper: fuera de un worktree
enlazado, `BuildWatchSet` devuelve `<git-dir>` **una sola vez**, con el filtro unido
`{config, packed-refs, HEAD}`.

## Cómo se arma y se rearma

```text
BuildWatchSet(gitDir, gitCommonDir, draftPaths) -> WatchSet
```

1. Materializa las seis raíces. Una que no exista **se ignora en silencio** (FR-064) y no impide el
   arranque.
2. **Deduplica por directorio**, uniendo los filtros de las raíces que resuelven al mismo lugar
   (A + F fuera de un worktree enlazado).
3. Aplica el cierre con su profundidad y su allowlist, hasta el presupuesto.
4. Devuelve un conjunto **ordenado y comparable**, para que "¿cambió?" sea una comparación y no un
   recorrido.

**Cuándo se rehace**:

- al arrancar;
- cuando el lote de eventos coalescido contiene la creación o el borrado de un **directorio** dentro
  de una ruta vigilada;
- cuando la lectura anterior reportó paths de borrador distintos a los que armaron el conjunto
  actual.

**El orden importa, y es la respuesta al edge case "el conjunto cambia y se pierden los eventos que
llegan mientras se rehace"**:

```text
disparo del debounce
  -> ¿hace falta rehacer?  sí -> Rebuild(WatchSet)      [primero]
  -> emitir UN watchMsg{}                                [después]
```

Rehacer **antes** de pedir la lectura hace que la carrera sea inofensiva: un evento que se pierda
durante el `Rebuild` está, por construcción, **antes** de la lectura que viene inmediatamente
después, y esa lectura re-lee todo desde porcelain. Un evento perdido durante un rebuild puede
duplicar trabajo; **no puede perder estado**.

`Rebuild` es incremental: agrega los watches nuevos y saca los que ya no están. Nunca tira el
watcher entero, porque eso sí abriría una ventana ciega real.

## Debounce y coalescencia

- **Debounce trailing de 200 ms**, con **techo de 1 s**. El techo no es adorno: un debounce trailing
  puro se muere de hambre bajo un flujo continuo de escrituras, que es exactamente lo que hace un
  agente llenando el borrador —el caso de la User Story 1—. Con techo, el panel se actualiza cada
  segundo mientras el agente escribe, en vez de recién cuando termina.
- **Coalescencia total**: N eventos de cualquier ruta producen **un** `watchMsg{}`.
- **Sin payload** (FR-062). El mensaje no dice qué cambió ni dónde. Su único significado es
  «reinvocá `status --porcelain`».
- **La vigilancia nunca lee** el contenido de una ruta vigilada: no parsea un ref, no abre `config`,
  no lee un `.md`. Sólo usa nombres de archivo, y sólo para filtrar.

Por eso los dos modos de falla son baratos: un **falso positivo** cuesta un proceso; un **falso
negativo** deja el panel viejo hasta el próximo disparador.

## El lock y la ventana de silencio

Mientras corre un verbo, el watch dispara N veces —el verbo mismo escribe `config` y refs—. Sin
serialización, un `finish` repinta cinco veces.

```text
mutación empieza  -> busy = true; los watchMsg{} se DESCARTAN y se recuerda que hubo
mutación termina  -> busy = false
                  -> UNA lectura inmediata            (disparador 1)
                  -> ventana de silencio: 600 ms      (debounce 200 + techo 1s/2 + gracia)
ventana cierra    -> si hubo disparos descartados: UNA lectura más
```

**Por qué la segunda lectura no rompe SC-004** ("exactamente un repintado"): los eventos de la propia
mutación siguen llegando *después* de que el proceso salió, así que descartarlos y no volver a mirar
dejaría un agujero real —un cambio externo que aterrice en esos 600 ms se perdería—. La segunda
lectura lo cubre y **no repinta**, porque devuelve el mismo estado, el `PanelModel` es **comparable
por valor** y un modelo igual al anterior no produce frame. SC-004 se afirma sobre el **repintado**,
no sobre el número de lecturas.

Costo aceptado: dos procesos por mutación en vez de uno. Es el único lugar del diseño donde se gasta
un proceso a propósito, y compra que la corrección no dependa de adivinar cuánto tarda inotify en
callarse.

**Profundidad del lock: 1.** Una segunda mutación mientras hay una en curso **se descarta con
aviso**, no se encola (User Story 5, escenario 6). Antes del spawn, ya adentro del lock, se revalida
el `StateToken` capturado al abrir la confirmación.

## Cómo se apaga entera (FR-063, FR-074, SC-016)

No es un flag chequeado en veinte lugares: es una **interface con dos implementaciones**.

```go
type Watcher interface {
    Start(ctx context.Context, set WatchSet, out chan<- struct{}) error
    Rebuild(set WatchSet) error
    Stop() error
}
```

- `fsnotifyWatcher` — **el único archivo del árbol que importa `fsnotify`**
  (`internal/host/watch_fsnotify.go`). Un test de frontera de imports lo afirma.
- `nopWatcher` — `Start` no hace nada, `Rebuild` no hace nada, el canal nunca recibe.

La elección se hace **una sola vez**, en `cmd/git-review-ui/main.go`, leyendo
`GIT_REVIEW_UI_WATCH` (`0` → `nopWatcher`). No es una clave `reviewui.*`: apagar el motor no es una
preferencia del revisor sino una palanca de suite y de soporte, y meterla en `reviewui.*` la
convertiría en superficie de producto que habría que dibujar y declarar. Se documenta en
`tui/CONTRIBUTING.md`.

**La suite corre con `nopWatcher` por default.** Eso hace que FR-063 y SC-016 se prueben **por
construcción en todos los tests**, no en un test dedicado: si algún camino necesitara que el watcher
disparara, la suite entera estaría roja. `watch_fsnotify_test.go` es el único paquete que instancia
el real, y es donde viven los tests de la tabla de agujeros más los del worktree enlazado y el dedup.

Consecuencia que hay que respetar al escribir tests: **ningún test puede esperar un evento de
archivo como forma de sincronizarse**. Los tests de comportamiento disparan el refresco con el
mensaje, no con el filesystem.

## El piso de poll opt-in (FR-039)

`reviewui.pollseconds`, clave `git config` bajo el namespace del cliente, **sin default** (ausente =
apagado). Leída defensivamente, como el resto de la config del proyecto.

- Es un **piso**, no un poll: programa una lectura sólo si no hubo ninguna en los últimos N segundos,
  y se re-arma en cada lectura venga de donde venga. Con la vigilancia funcionando, no agrega ni una
  invocación.
- **No se presenta como el mecanismo**: no está en la barra de teclas, no tiene control en el panel,
  no aparece en ninguna copy. Vive en `tui/CONTRIBUTING.md` y en la línea de los README que habla de
  montajes de red.
- Existe para el agujero 5, que falla en silencio y es el peor modo de falla para lo único que
  sostiene «se re-renderiza sola».

## Lo que la vigilancia NO hace

1. No lee el contenido de ninguna ruta vigilada.
2. No deriva estado de un evento (FR-034): produce un mensaje sin payload y nada más.
3. No depende de que un ref exista como archivo (FR-035).
4. No rearma paths del layout del gitdir: los de borrador salen de lo que la CLI reportó, los de git
   de preguntarle a git (FR-036).
5. No falla ni impide el arranque cuando una ruta no existe (FR-064).
6. No vigila las guías de autoría ni el walkthrough del autor. La guía propia vive en la raíz del
   gitdir, que cambia en cada operación de git —vigilarla sería una tormenta de refrescos por el
   archivo que menos cambia del panel— y el walkthrough vive en el work tree. Los tres son
   `watched: on_save` en el canónico: el cliente que corre el verbo refresca solo, y el guardado del
   documento lo escucha cada cliente a su manera. **En la TUI no hay editor propio**, así que el
   equivalente es el refresco al volver de una acción delegada (`tea.ExecProcess`), que es el
   momento exacto en que el revisor terminó de editar.
