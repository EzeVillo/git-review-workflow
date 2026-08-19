# Quickstart: el borrador escrito por un agente

**Feature**: `012-prompt-agente-draft` | **Fase**: 1 | **Fecha**: 2026-08-19

Escenarios ejecutables que prueban la feature de punta a punta. Detalle de la
superficie en [`contracts/`](contracts/); modelo del dato en
[`data-model.md`](data-model.md).

## Preparación

```sh
./tests/sandbox.sh
```

Arma un PR de juguete y dice cómo entrar. Ojo con la rama: `feature/checkout`
**trae walkthrough commiteado**, así que no sirve para el camino principal. El
sandbox arma dos ramas sin walkthrough —`feature/telemetry` (la que usan estos
escenarios) y `feature/pagos`— y la base es `develop`.

---

## Escenario 1 — El esqueleto ubica el cambio (US1)

```sh
cd <sandbox>/work
git review walkthrough draft feature/telemetry
sed -n '1,40p' .git/review-walkthrough/feature/telemetry.md
```

Comprobar en el bloque `<!-- git-review-range:`:

1. **Los dos extremos son objetos que git resuelve**, no palabras:

   ```sh
   LOW=$(sed -n 's/^ *base *\([0-9a-f]\{7,\}\).*/\1/p' .git/review-walkthrough/feature/telemetry.md | head -1)
   TIP=$(sed -n 's/^ *tip *\([0-9a-f]\{7,\}\).*/\1/p' .git/review-walkthrough/feature/telemetry.md | head -1)
   git cat-file -e "$LOW" && git cat-file -e "$TIP" && echo OK   # ← FR-001
   ```

2. **Ningún `..` entre los extremos, y ningún comando de historia.** El grep va
   **acotado al bloque**: el andamiaje del propio esqueleto trae `(1, 2, 3, ...)`
   y `.review/`, así que un `grep '\.\.'` sobre el archivo entero matchea siempre
   y no verifica nada.

   ```sh
   F=.git/review-walkthrough/feature/telemetry.md
   BLOCK=$(sed -n '/^<!-- git-review-range:/,/-->/p' "$F")

   printf '%s\n' "$BLOCK" | grep -n '[0-9a-f]\{7,\}\.\.'          # ← FR-003: NO debe haber salida
   printf '%s\n' "$BLOCK" | grep -nE 'git (log|rev-list|shortlog|range-diff)'   # ← NO debe haber salida
   ```

   Los dos motivos, medidos, están en `research.md` § Hallazgo 0: `git log` con
   un lower de tipo tree imprime la historia entera con exit 0, y
   `git diff <a>..<b>` con SHAs completos y sin `--` muere en Windows con el cwd
   profundo, con cualquier tipo de extremo.

3. **Seguir el comando devuelve el contenido del PR**, sobre un archivo que el
   PR *modifica* (no que agrega):

   ```sh
   P=<un archivo modificado por el PR>
   git show "$TIP:$P"  > /tmp/after.txt
   cat "$P"            > /tmp/tree.txt
   diff /tmp/after.txt /tmp/tree.txt   # ← DEBE diferir (FR-002, SC-001)
   ```

4. **La frase de situación dice «estás en la base»** — el árbol tiene la versión
   vieja (FR-004, SC-002).

**Se valida**: FR-001..FR-006, SC-001, SC-002.

## Escenario 2 — El rango incremental y la base mergeada

```sh
git review start feature/telemetry && git review finish      # deja marcador --delta
git review clean                                             # cierra el finish pendiente
git review walkthrough draft --delta --force feature/telemetry
```

El `clean` no es opcional: `finish` deja la review en estado *finish pendiente*,
y el `start` del escenario 3 se niega sobre ese estado. Sin él, la secuencia de
escenarios no corre de punta a punta.

El bloque dice que el rango es incremental y su `base` es el marcador previo, no
la merge-base (FR-005), y su línea `Generated with:` dice `--delta` (FR-005a).

Comprobarlo contra la fuente, no de memoria:

```sh
F=.git/review-walkthrough/feature/telemetry.md
LOW=$(sed -n 's/^ *base *\([0-9a-f]\{7,\}\).*/\1/p' "$F" | head -1)
test "$LOW" = "$(git config reviewworkflow.feature/telemetry.reviewed)" && echo OK
```

**El lower de tipo tree** —el caso que exige un PR que mergee la base adentro—
sí está en el sandbox: `tests/sandbox.sh` arma una rama para eso, por el mismo
motivo por el que ya arma una por cada estado que el PR de juguete no puede
mostrar. Es el caso que se diagnosticó mal tres veces seguidas, así que conviene
poder mirarlo a mano y no sólo en bats:

```sh
git review walkthrough draft --stdout feature/merged-base | sed -n '/^<!-- git-review-range:/,/-->/p'
# el bloque dice "tree" en <lower-kind>, y sus comandos siguen funcionando
```

**Se valida**: FR-003, FR-005, FR-005a.

## Escenario 3 — Generado desde adentro de una review (US1 escenario 4)

```sh
git review start feature/telemetry
git review walkthrough draft feature/telemetry --force     # rama nombrada EXPLÍCITAMENTE
grep -n 'inside an active review' .git/review-walkthrough/feature/telemetry.md
```

Es el caso que `from_review` erraría: la rama va nombrada, así que la detección
tiene que salir de `HEAD`.

**Se valida**: FR-004, SC-002.

---

## Escenario 4 — El circuito con un agente, sin tocar el gitdir (US2)

```sh
git review abort 2>/dev/null || true
cd <sandbox>/work
git status --porcelain > /tmp/before.txt

# 1. el esqueleto por la salida estándar: no se crea nada
git review walkthrough draft --stdout feature/pagos > /tmp/order.md
ls .git/review-walkthrough/feature/ 2>&1        # ← no existe (FR-009)
diff /tmp/before.txt <(git status --porcelain)  # ← vacío

# 2. completarlo AFUERA del directorio de git (a mano, o con un agente)
$EDITOR /tmp/order.md

# 3. instalarlo con una sola invocación
git review walkthrough draft --build --from /tmp/order.md feature/pagos
# → "built $GIT_DIR/review-walkthrough/feature/pagos.md: N entries, ordered and renumbered"

git review start feature/pagos
git review status        # → "mode    walk (draft)  [1/N] on ..."
```

Y por la entrada estándar, con resultado idéntico:

```sh
git review forget --draft feature/pagos
git review walkthrough draft --build --from - feature/pagos < /tmp/order.md
```

**Se valida**: FR-009..FR-013, SC-003.

## Escenario 5 — Nada queda a medias

```sh
# el borrador anterior sigue byte por byte igual tras cada rechazo
cp .git/review-walkthrough/feature/pagos.md /tmp/keep.md

printf '' | git review walkthrough draft --build --from - --force feature/pagos
# → error: is empty ...                                          (FR-015)
git review walkthrough draft --build --from /tmp/nope.md --force feature/pagos
# → error: could not read /tmp/nope.md                           (FR-018)
git review walkthrough draft --build --from /tmp/order.md feature/pagos
# → error: already exists; pass --force to overwrite             (FR-016)

diff /tmp/keep.md .git/review-walkthrough/feature/pagos.md       # ← vacío (FR-014, SC-004)
```

Y la entrada estándar no cuelga. **Ojo con el orden de las guardas**: acá
`feature/pagos` ya tiene borrador, y la existencia se comprueba *antes* de leer
la fuente, así que sin `--force` el mensaje que sale es el de sobrescritura y
este paso no probaría FR-017 en absoluto:

```sh
git review walkthrough draft --build --from - --force feature/pagos   # sin redirigir nada
# → error: --from - reads the draft from standard input; ...     (FR-017, SC-005)
```

Y el otro extremo de SC-005, el que se olvida porque no tiene mensaje: el reporte
sin ningún borrador **termina**.

```sh
git review forget --draft --all
git review config --porcelain          # ← devuelve el prompt; no espera entrada
```

**Se valida**: FR-014..FR-018, FR-021a, SC-004, SC-005.

## Escenario 6 — Reanotar sin reconstruir nada (US2, edge case)

```sh
# el autor pushea y ahora sobra un archivo
git review walkthrough draft --build feature/pagos
# → error de drift, nombrando los dos lados

grep -c 'git-review-range' .git/review-walkthrough/feature/pagos.md   # ← 1
```

El archivo instalado **conserva** el bloque, así que se le vuelve a pasar al
agente tal cual, con los *whys* ya escritos adentro. No hay comando de
recuperación y no hay dos archivos que reconciliar.

**Se valida**: FR-019, SC-014.

## Escenario 7 — El bloque no se ve nunca

```sh
git review start feature/pagos      # el heads-up que imprime NO trae el bloque
git review status --why <path>      # tampoco
```

Y del lado del autor, sobre `feature/checkout` (que trae sidecar):

```sh
git checkout feature/checkout
git review walkthrough build
grep -c 'git-review-range' .review/walkthrough.md   # ← 1, y es un comentario HTML
```

Renderizado en GitHub, un comentario HTML no aparece.

**Se valida**: FR-007, FR-013a, SC-015.

---

## Escenario 8 — Los registros de la CLI (US3, lado CLI)

```sh
git review abort 2>/dev/null || true
git checkout develop
git review walkthrough draft feature/telemetry
git review walkthrough draft feature/pagos

git review config --porcelain | grep '^draft'
```

| Situación | Esperado |
| --- | --- |
| Dos borradores | Dos registros, ruta absoluta existente, progreso `0/N` cada uno |
| Tras anotar tres entradas de uno | Ese registro pasa a `3/N`; el otro no cambia |
| Tras `git review save` de una review con borrador | Ese borrador **desaparece** de los registros |
| Tras `git review continue` | Vuelve |

```sh
git review start feature/telemetry
git review status --porcelain | grep '^draft'   # → draft<TAB><ruta absoluta>
git review list --porcelain | grep 'draft'      # → branch-draft<TAB>review/feature/telemetry
```

**Se valida**: FR-020..FR-024, SC-013.

---

## Escenario 9 — El panel de VS Code (US3 + US4)

Requiere el checkout instalado (`./install.sh`) o `gitReview.path` apuntando a
`bin/git-review`.

1. Con dos borradores a medio escribir y **ninguna review activa**, abrir
   `<sandbox>/work` y F5 desde `vscode-extension/` (*Run Extension*).
2. El panel muestra el bloque arriba, **una fila por borrador**, con su rama y
   su progreso — y debajo, entero, el inventario de reviews y **Start a review**
   (FR-025, SC-006).
3. **Cerrar la ventana y reabrirla**: el bloque sigue ahí, sin abrir ningún
   asistente (SC-006).
4. *Open* → se abre el archivo. *Copy for agent* → pegar y comprobar que el
   texto trae la ruta de **esa** fila (FR-028, SC-007).
5. *Validate and start* sobre el borrador incompleto → muestra el motivo y el
   panel **queda igual** (FR-030).
6. Completarlo (marcando alguna entrada `> key`) → *Validate and start* →
   pregunta recorrido completo vs sólo esenciales → arranca en walk con el badge
   de draft (FR-029).
7. *Discard* sobre el otro → pide confirmación; al confirmar desaparece **sólo
   esa fila** (FR-026, FR-031).
8. Recorrer el asistente sobre una rama sin borrador: la oferta dice
   **Build a reading order first**; elegirla crea el borrador, lo abre y el
   asistente **cierra**, sin dejar ninguna notificación (FR-032, FR-033,
   SC-010, SC-011).

**Se valida**: FR-025..FR-033, SC-006..SC-008, SC-010, SC-011.

## Escenario 10 — Lo mismo en IntelliJ y en Visual Studio (US5)

```sh
cd jetbrains-plugin && ./gradlew runIde        # abrir SOLO <sandbox>/work
```

```powershell
cd visualstudio-extension
./build-vsix.ps1 -Install -Experimental
devenv /rootsuffix Exp
```

Mismo recorrido que el escenario 9. Comprobar en particular que *Copy for
agent* deja **el mismo texto** en los tres (US5 escenario 2).

**Se valida**: FR-034, FR-035, SC-009.

---

## Suites

```sh
./lint-docker.sh                                   # shellcheck
./tests/run-docker.sh                              # bats (CLI)
node scripts/check-client-product-surface.mjs      # canónico multi-cliente
cd vscode-extension && npm run test:unit           # unit de la extensión
./vscode-extension/test/run-docker.sh              # integración de la extensión
cd jetbrains-plugin && ./gradlew test              # dominio del plugin
cd visualstudio-extension && dotnet test tests/GitReview.Domain.Tests
cd visualstudio-extension && dotnet run --project src/GitReview.VS -- --verify
cd visualstudio-extension && ./build-vsix.ps1      # el gate de net472
```

Los tests van al contenedor por la razón de siempre: en Windows crear un proceso
cuesta ~50 ms contra ~1 ms en Linux, y las dos suites son básicamente procesos.
