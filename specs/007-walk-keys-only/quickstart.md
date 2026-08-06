# Quickstart de validación: walk solo-keys

**Feature**: `007-walk-keys-only`

Guía manual corta para comprobar el feature de punta a punta. Los tests
automatizados son la fuente de verdad; esto es el smoke humano.

## Prerrequisitos

- Checkout de la rama `007-walk-keys-only` con `./install.sh` (o `PATH` al
  `bin/`).
- Repo de juguete: `./tests/sandbox.sh` (incluye walkthrough con keys en
  `feature/checkout`).

## 1. CLI — start y cursor

```sh
# entrar al sandbox work dir que imprime sandbox.sh
git review start feature/checkout --keys
```

**Esperado**:

- Mensaje de ready con el total **K** de keys (no el N completo).
- Primera entrada es una key; header del estilo `[1/K] … (key)`.
- `git review next` recorre solo keys; al final de K no aparecen uncovered
  ni no-keys.
- `git review status` (humano) indica keys-only / solo esas entradas.

```sh
git review status --porcelain
```

**Esperado**: línea `keys`; solo `entry` esenciales; `state` con
`total=K`.

## 2. Persistencia

```sh
git review save
git review continue   # o continue desde el nombre que use save
git review status --porcelain
```

**Esperado**: sigue el registro `keys` y la misma posición.

## 3. Rechazos

```sh
git review abort   # limpiar si hace falta
# En un branch/PR sin ninguna "> key" (o forzar walkthrough sin keys):
git review start <src> --keys          # → error, sin rama review/* nueva
git review start <src> --keys --step   # → error
git review start <src> --keys --no-walk # → error
```

## 4. Finish no exige no-keys

Con solo-keys activo y alguna edición trivial:

```sh
# editar un archivo del PR
git review finish
```

**Esperado**: misma semántica que walk; no pide visitar el resto del
orden.

## 5. Extensión

1. F5 / Extension Development Host con el sandbox work abierto.
2. Start review → layout **Walkthrough — keys only** (o etiqueta final).
3. Panel muestra indicador keys-only, lista K entradas, next/prev no salen
   del set.

## 6. Suite

```sh
./tests/run-docker.sh          # o el archivo bats del feature
cd vscode-extension && npm test
shellcheck $(find bin -type f ! -name '.gitkeep') …
```

Ver `CLAUDE.md` para la línea exacta de shellcheck del repo.
