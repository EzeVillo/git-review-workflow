# Quickstart: 006-superficie-panel-completa

## Prerrequisitos

```sh
./install.sh   # o gitReview.path → bin/git-review
cd vscode-extension && npm install && npm test
```

Sandbox útil:

```sh
./tests/sandbox.sh
# en work: reviews, walkthrough, etc. según el sandbox
```

## P1 — Housekeeping

1. En sandbox, `git review start …` + `save` → inventario con saved.
2. Panel: **Discard** en la fila → confirmar → `git review list --porcelain`
   ya no la lista.
3. Crear leftover: start, checkout otra rama dejando `review/*` (o save +
   forget parcial según fixture de tests).
4. Palette **Clean Review Leftovers** para un source → confirmar → ramas
   `review/<src>` / `review-fixes/<src>` ausentes.
5. Forzar orphan (borrar metadata a mano en fixture de test) → botón Discard
   → `forget --saved` o `clean` según tipo.
6. Descartar el modal → sin cambios en el repo.

## P2 — Preview

1. Review activa, editar un archivo.
2. **Preview Edits** → documento con el diff; `git status` igual que antes.
3. **Preview Edits (stat)** → resumen.
4. En finish-conflict, preview muestra error de CLI.

## P3 — Compare

1. Sin review (o repo limpio).
2. **Compare Revisions** → elegir dos ramas/commits, layout, confirmar.
3. Panel en review; `git review status --porcelain` alineado con
   `git review compare a b` manual en otro clone.

## P4 — Walkthrough

1. En rama de feature con cambios vs base, **Walkthrough: Init** → se abre
   `.review/walkthrough.md`.
2. Rellenar números y whys mínimos.
3. **Walkthrough: Build** → archivo renumerado o error de validación.
4. Init de nuevo → confirm force → sobrescribe.

## Verificación automática

```sh
cd vscode-extension
npm run test:unit
npm run test:integration   # o subset de specs nuevos
```
