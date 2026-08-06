# Data Model: 006-superficie-panel-completa

Sin entidades persistidas nuevas en la extensión. Solo intenciones efímeras y
acciones.

## HousekeepingAction

| Campo    | Valores                                                                                                                                                          | Notas                                                                  |
|----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| `kind`   | `clean-one` \| `clean-keep-fixes` \| `clean-all` \| `forget-saved-one` \| `forget-saved-all` \| `forget-delta-one` \| `forget-delta-all` \| `forget-delta-stale` |                                                                        |
| `source` | string opcional                                                                                                                                                  | Requerido en `*-one`; nombre source (`feature/x`), no `review-saved/x` |
| `token`  | StateToken opcional                                                                                                                                              | Si la acción nació de una fila del inventario                          |

Mapeo a CLI:

| kind               | args                                                                                                     |
|--------------------|----------------------------------------------------------------------------------------------------------|
| clean-one          | `clean`, `[source]`                                                                                      |
| clean-keep-fixes   | `clean`, `--keep-fixes`, `[source]` — post-finish del panel: tira `review/` + undo, deja `review-fixes/` |
| clean-all          | `clean`                                                                                                  |
| forget-saved-one   | `forget`, `--saved`, `source`                                                                            |
| forget-saved-all   | `forget`, `--saved`, `--all`                                                                             |
| forget-delta-one   | `forget`, `--delta`, `source`                                                                            |
| forget-delta-all   | `forget`, `--delta`, `--all`                                                                             |
| forget-delta-stale | `forget`, `--delta`, `--stale`                                                                           |

## CompareIntent

| Campo    | Valores                       |
|----------|-------------------------------|
| `lower`  | commit-ish                    |
| `upper`  | commit-ish                    |
| `layout` | `auto` \| `step` \| `no-walk` |

Args: `compare` + opcional `--step` o `--no-walk` + lower + upper (con `--`
si hace falta según el verbo).

## PreviewRequest

| Campo  | Valores |
|--------|---------|
| `stat` | boolean |

Args: `preview` o `preview --stat`.

## WalkthroughCommand

| Campo   | Valores             |
|---------|---------------------|
| `sub`   | `init` \| `build`   |
| `force` | boolean (solo init) |

Args: `walkthrough init` [`--force`]; `walkthrough build`.

## Inventory row → acción sugerida

| Fila                         | Acción por defecto del botón                                   |
|------------------------------|----------------------------------------------------------------|
| `saved` && !orphan           | forget-saved-one                                               |
| `saved` && orphan            | forget-saved-one                                               |
| !saved && orphan             | clean-one                                                      |
| active no-current (opcional) | clean-one (destructivo de leftovers; no es abort de la actual) |
