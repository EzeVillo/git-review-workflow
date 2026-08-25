# Quickstart: validar el walkthrough del revisor

**Feature**: `011-walkthrough-draft-revisor` | **Fase**: 1 | **Fecha**: 2026-08-09

Escenarios ejecutables que prueban la feature de punta a punta. Detalle de la
superficie en [`contracts/`](contracts/); modelo del dato en
[`data-model.md`](data-model.md).

## Preparación

```sh
./tests/sandbox.sh
```

Arma un PR de juguete y dice cómo entrar. Ojo con la rama: el PR principal
(`feature/checkout`) **trae walkthrough commiteado**, así que no sirve para el
camino principal de esta feature. El sandbox ya arma dos ramas sin walkthrough
— `feature/telemetry` (la que estos escenarios usan) y `feature/pagos` — y la
base del sandbox es `develop`, no `main`.

## Escenario 1 — El camino completo, sin tocar el repositorio (US1)

```sh
cd <sandbox>/work
git status --porcelain > /tmp/before.txt

git review walkthrough draft feature/telemetry
# → escribe .git/review-walkthrough/feature/telemetry.md y dice cuántos archivos

# completar el borrador (a mano, o pidiéndoselo a un agente)

git review walkthrough draft --build feature/telemetry
# → "walkthrough draft ok: N entries, in sync with feature/telemetry"

git status --porcelain > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt   # DEBE estar vacío  ← SC-002

git review start feature/telemetry
# → "review/... ready (...) — walkthrough: N entries; read, edit, then run git review next"
git review status
# → "mode    walk (draft)  [1/N] on ..."   ← FR-014a / SC-009
```

**Se valida**: FR-001..FR-003, FR-006, FR-010, FR-014a, SC-001, SC-002, SC-009.

## Escenario 2 — La review es indistinguible de una con walkthrough del autor

Sobre la review del escenario 1:

```sh
git review next            # avanza en el orden escrito
git review prev
git review status --why <path>   # imprime el why del borrador
git review preview               # las ediciones del revisor, sin el borrador
```

**Se valida**: FR-011, SC-005.

## Escenario 3 — El borrador nunca se cuela en las ediciones

```sh
# editar algún archivo del PR, luego:
git review finish
git diff --name-only develop review-fixes/feature/telemetry
# → sólo los archivos editados; NUNCA nada del borrador   ← FR-009 / SC-006
```

**Se valida**: FR-009, SC-006.

## Escenario 4 — Pausar y limpiar no pierde el orden (US1, clarificación)

```sh
git review save
ls .git/review-saved-walkthrough/feature/     # el borrador se movió acá
git review clean
ls .git/review-saved-walkthrough/feature/     # sigue estando   ← FR-008a
git review continue feature/telemetry
git review status                              # misma entrada, mismo orden ← SC-011
```

`clean` tampoco toca un borrador **activo** (ni el escrito antes de que la review
exista, que es el primer paso del flujo de arriba). Para borrar uno hay que
pedirlo:

```sh
git review forget --draft feature/telemetry   # o --all, o --dry-run para ver
```

**Se valida**: FR-008, FR-008a, SC-011.

## Escenario 5 — Rechazos que no dejan nada a medias

```sh
git review walkthrough draft feature/telemetry        # sin completar
git review walkthrough draft --build feature/telemetry
# → error nombrando los placeholders sin completar; exit ≠ 0

git review walkthrough draft feature/telemetry        # otra vez
# → superado: actualiza el borrador existente (FR-005 ya no aplica)
```

Con un borrador al que le falta un archivo del PR, `--build` nombra los dos
lados del drift y no reescribe nada.

**Se valida**: FR-005, FR-007, SC-007.

## Escenario 6 — Las ofertas que ve el asistente

```sh
git review config --porcelain -- feature/telemetry | grep '^offer'
```

| Situación | Esperado |
| --- | --- |
| Sin borrador, sin sidecar | `draft`, `step`, `whole` |
| Con borrador | `walk`, `draft-resume`, `step`, `whole` |
| Sidecar del autor, sin borrador | `walk`, `keys`?, `step`, `whole` — **sin** `draft` |

**Se valida**: FR-015, FR-016a.

## Escenario 7 — El asistente de VS Code (US2)

Requiere el checkout instalado (`./install.sh`) o `gitReview.path` apuntando a
`bin/git-review`.

1. Abrir `<sandbox>/work`, F5 desde `vscode-extension/` (*Run Extension*).
2. Panel → **Start a review** → rama sin walkthrough → origen → rango.
3. En forma de lectura aparece **Walkthrough — draft one**.
4. Elegirla: se abre el borrador y queda una notificación con *Continue* /
   *Cancel*. **Comprobar que se puede escribir en el archivo con la
   notificación visible** y que no se auto-oculta.
5. *Continue* sin completar → muestra el motivo y la notificación sigue ahí.
6. Completar (marcando alguna entrada con `> key`) → *Continue* → pregunta
   recorrido completo vs sólo esenciales → arranca en walk con el badge de
   draft.
7. Repetir hasta el paso 4 y usar *Cancel* → vuelve a forma de lectura con el
   borrador intacto; elegir *Whole diff* arranca la review igual.
8. Repetir hasta el paso 4, cerrar la ventana, reabrir el asistente → la oferta
   dice **continue draft**.

**Se valida**: FR-016..FR-020, SC-003, SC-004, SC-010.

## Escenario 8 — Lo mismo en IntelliJ (US3)

```sh
cd jetbrains-plugin && ./gradlew runIde
```

Abrir sólo `<sandbox>/work`, tool window **git review**, mismo recorrido que el
escenario 7. Comprobar en particular que el diálogo de espera **no bloquea el
IDE**: el archivo tiene que poder editarse con el diálogo abierto.

**Se valida**: FR-021, SC-008.

## Suites

```sh
./lint-docker.sh                                  # shellcheck
./tests/run-docker.sh                             # bats (CLI)
cd vscode-extension && npm run test:unit          # unit de la extensión
./vscode-extension/test/run-docker.sh             # integración de la extensión
cd jetbrains-plugin && ./gradlew test              # dominio del plugin
```

Los tests van al contenedor por la razón de siempre: en Windows crear un proceso
cuesta ~50 ms contra ~1 ms en Linux, y ambas suites son básicamente procesos.
