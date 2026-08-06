# Quickstart: validar ofertas de lectura al start

**Feature**: `008-start-layout-offers`

## Prerrequisitos

- Checkout con CLI instalada (`./install.sh` o `gitReview.path` → `bin/git-review`)
- Base configurada: `git review config base main` (o la del sandbox)
- Sandbox opcional: `./tests/sandbox.sh` (trae walkthrough en `feature/checkout`)

## 1. CLI — matrix de ofertas (sin red)

En un repo de prueba con base y tres tip shapes:

### A. Sin walkthrough

```sh
git review config --porcelain -- feature/sin-walk
# Esperado entre las líneas:
# offer	step	available
# offer	whole	available
# y NO: walk, keys
```

### B. Walk sin keys

```sh
git review config --porcelain -- feature/walk-no-keys
# offer	walk	recommended
# offer	step	available
# offer	whole	available
# sin keys
```

### C. Walk con keys

```sh
git review config --porcelain -- feature/walk-keys
# offer	walk	recommended
# offer	keys	available
# offer	step	available
# offer	whole	available
```

### D. Remoto sin tracking ref

```sh
git review config --porcelain -- rama-sin-origin
# exit ≠ 0, stderr menciona no found / not found; sin offers usables
```

### E. Local vs remoto distinto tip

Si el tip local no tiene walk y `origin/branch` sí:

```sh
git review config --porcelain --local -- branch   # step+whole
git review config --porcelain -- branch          # walk(+keys)…
```

### F. Sin fetch

Mientras corre el comando de ofertas, no debe aparecer actividad de red
hacia el remote (no `fetch` en traza/`GIT_TRACE` si se instrumenta).

## 2. Extensión — asistente

1. Repo sin review activa; F5 o host con la extensión.
2. Start review → elegir rama con walk+keys.
3. Origen → remoto (o el que tenga el tip con walk).
4. Rango full (o delta si aplica).
5. Forma de lectura: ver Walkthrough (recommended), Keys only, Commit by
   commit, Whole diff — **sin** Automatic.
6. Elegir Walkthrough → confirmar → panel en walk.
7. Abort; repetir eligiendo Keys only → panel con filtro keys (007).
8. Rama sin walk: solo Whole + Commit by commit, sin recommended.

## 3. Tests automatizados

```sh
./tests/run-docker.sh config-offers.bats   # o el archivo que implemente tasks
# extensión:
cd vscode-extension && npm run test:unit
# integration start-review si el entorno lo permite
```

## 4. Criterio de done rápido

- [ ] Matrix A–C en CLI con líneas `offer` exactas
- [ ] Tip missing → exit ≠ 0
- [ ] Asistente sin “Automatic”
- [ ] Keys oculto cuando el informe no emite keys
- [ ] `intentToArgs(whole)` incluye `--no-walk`; `walk` no añade flag de layout
