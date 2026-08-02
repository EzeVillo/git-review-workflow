# Quickstart: validar el contrato porcelain

Prerrequisitos: repo con `reviewworkflow.base` configurado, y una rama con
commits sobre esa base (para poder correr `git review start`). Todo lo de
abajo es de sólo lectura una vez iniciada la review (FR-022): repetible sin
efectos secundarios.

## 1. Estado (US1) + secuencia (US2) + cobertura (US5) en una sola invocación

```sh
git config reviewworkflow.base main
git review start feature/x        # --step si querés ese modo; walk se
                                   # autodetecta si el PR trae un walkthrough
git review status --porcelain
echo "exit: $?"
```

Resultado esperado: exit `0`; primera línea `state\t...` con los campos que
correspondan al modo; cero o más líneas `entry\t...` (vacío en modo `whole`
sin walkthrough); cero o más líneas `uncovered\t...`. Repetir el comando no
cambia nada del estado de la review (verificable con `git status --porcelain`
de git y `git config --get-regexp branch.<rama>.review` antes/después,
idénticos).

Dos comprobaciones que conviene hacer a ojo acá:

- la cantidad de líneas `entry` es **exactamente** el campo `total` del
  registro `state` (no el campo `recorded`, que es el total registrado al
  iniciar la review);
- en modo `step`, el campo `walkthrough` vale `none` y está presente: el
  registro es posicional y no se omite ningún campo del medio.

## 2. "Por qué" de una entrada puntual (US4)

Sólo en modo walk (requiere un PR con `.review/walkthrough.md` construido vía
`git review walkthrough build`):

```sh
git review status --why src/core.ts
```

Resultado esperado: sólo el texto del "why", sin marcadores `> key`/`> at:`,
exit `0`. Para un path fuera de la secuencia actual: exit `1` y diagnóstico en
stderr, stdout vacío.

## 3. Situaciones distintas (US3)

```sh
# Sin review activa
git switch main
git review status --porcelain; echo "exit: $?"     # -> 2, sin líneas

# No es un repositorio git
(cd /tmp && git review status --porcelain); echo "exit: $?"   # -> 1

# Metadata corrupta (rama hecha a mano)
git switch --quiet -c review/orphan-test
git review status --porcelain; echo "exit: $?"     # -> 1, diagnóstico en stderr
git switch main && git branch -D review/orphan-test
```

Y el cuarto caso, el drift (FR-023) — una review walk sobre cuya base se
commiteó:

```sh
git review start feature/x                         # walk, autodetectado
git commit -qam "oops"                             # se come el diff staged
git review status --porcelain; echo "exit: $?"     # -> 3, sin líneas
git review next; echo "exit: $?"                   # -> 3 también: mismo hecho,
                                                   #    mismo código
git reset --soft HEAD~1                            # el arreglo que sugiere stderr
git review status --porcelain; echo "exit: $?"     # -> 0, todo de vuelta
```

`3` y `1` son ambos "no se pudo responder", pero se separan por quién puede
arreglarlo: el `3` tiene una acción concreta del lado del usuario, el `1` no.

## 4. Inventario (US6)

```sh
git review list --porcelain
```

Resultado esperado: una línea `branch\t...` por cada rama `review/*` y
`review-saved/*`, incluidas las huérfanas (`orphan=1`), sin que ninguna se
omita. `position`/`total` acá salen de la config de cada rama —los mismos
números que muestra `list` humano, no la secuencia re-derivada— y se omiten
enteros si falta la clave: en ninguna línea debe aparecer un `?`.

## 5. No regresión (FR-021, SC-004, SC-008)

```sh
./tests/run-docker.sh                 # suite completa sigue en verde
```

Y, puntualmente, que la salida humana no cambió: comparar
`git review status` (sin `--porcelain`) antes y después del cambio, texto
idéntico byte a byte, para los mismos tres modos.

Las únicas aserciones existentes que se tocan en todo el repo son las dos de
exit code de `tests/walk.bats` (líneas 194 y 201, de `-eq 1` a `-eq 3`, por
FR-023). Si hay que editar cualquier otra para que la suite pase, es una
regresión y no un ajuste.
