# Contrato: superficie de la extensión en VS Code

Lo que la extensión le contribuye al editor y, por lo tanto, lo que el usuario
puede invocar, ver o configurar. Es la parte del `package.json` (manifiesto)
que constituye interfaz pública: cambiar un `command.id` o una clave de
configuración rompe keybindings y `settings.json` de usuarios.

Las decisiones de forma están en `research.md` (4, 5, 6, 12); acá va el detalle
normativo.

## Activación

```json
"activationEvents": ["onView:gitReview.walkthrough"]
```

Activación perezosa: no corre nada hasta que la vista se abre por primera vez.
Ninguna invocación a la CLI ocurre al arrancar el editor — abrir una ventana en
un repositorio cualquiera no debe costar un proceso.

## Vista

Un view container propio en la Activity Bar, con una sola vista.

| Campo        | Valor                       |
|--------------|-----------------------------|
| Container id | `gitReview`                 |
| View id      | `gitReview.walkthrough`     |
| Tipo         | `tree` (`TreeDataProvider`) |

**`TreeView.description`**: `N/M` — posición actual y total derivado (FR-009).
Cuando `total ≠ recorded`, se agrega la advertencia de que la base se movió
(FR-011). En multi-root, incluye de qué repositorio se trata (FR-029).

**`TreeView.message`**: se usa para "trabajando…" mientras hay una invocación en
vuelo (FR-030) y para la nota de walkthrough degradado con su motivo (FR-010).

### Estructura del árbol

```text
├── <entrada 1>            ← SequenceEntry, en orden de lectura
├── <entrada 2>  ●         ← la actual: ThemeIcon distintivo
├── <entrada 3>  ★         ← esencial: ThemeIcon distintivo (walk)
│   …
└── Sin cobertura          ← nodo colapsable, sólo si hay UncoveredFile
    ├── <archivo a>
    └── <archivo b>
```

Reglas normativas:

- El orden es el de los registros `entry`; no se reordena (FR-005).
- La entrada actual se marca por `position`, no por `id` (FR-006).
- Esencial (walk) y con ediciones guardadas (step) se distinguen por ícono
  **más** texto en `description`, nunca sólo por color (FR-007, FR-027).
- Los archivos sin cobertura van agrupados y separados (FR-008).
- El `label` de todo ítem es `PathRef.display` (FR-012).
- En `mode = whole` sin walkthrough el árbol está vacío y lo explica un
  `viewsWelcome` (FR-026); no es un error.

### Estados vacíos (`viewsWelcome`)

Uno por valor de `Situation` distinto de `review`, seleccionado por
`when: gitReview.situation == <valor>`. Cada uno con su texto y su botón, salvo
`error` (Decisión 5).

## Comandos

Los ids son interfaz pública.

| Command id             | Título            | Dónde aparece                       |
|------------------------|-------------------|-------------------------------------|
| `gitReview.openEntry`  | Abrir entrada     | clic en un ítem del árbol (default) |
| `gitReview.openChange` | Ver cambios       | acción inline del ítem              |
| `gitReview.showWhy`    | Ver el porqué     | acción inline del ítem, paleta      |
| `gitReview.next`       | Entrada siguiente | título de la vista, paleta          |
| `gitReview.prev`       | Entrada anterior  | título de la vista, paleta          |
| `gitReview.refresh`    | Refrescar         | título de la vista, paleta          |
| `gitReview.installCli` | Instalar la CLI   | botón del `viewsWelcome`            |

Reglas normativas:

- `next` y `prev` están deshabilitados por `when: !gitReview.busy` mientras hay
  una mutación en curso (FR-020). **No** se deshabilitan al llegar a un extremo
  de la secuencia: eso lo decide la CLI (FR-016).
- Los comandos de la paleta se ocultan con `when: gitReview.situation == review`
  — no tiene sentido ofrecer "entrada siguiente" donde no hay review.
- `gitReview.openEntry` abre el documento del working tree; con el archivo
  ausente (eliminado en el rango) cae en el diff (Decisión 10).

## Context keys

Publicadas con `setContext`. Son la única forma en que el estado influye en el
manifiesto.

| Key                   | Valores                                                                                 |
|-----------------------|-----------------------------------------------------------------------------------------|
| `gitReview.situation` | `review` \| `no-review` \| `out-of-range` \| `error` \| `cli-missing` \| `cli-outdated` |
| `gitReview.mode`      | `whole` \| `step` \| `walk`                                                             |
| `gitReview.busy`      | booleano                                                                                |

## Configuración

| Clave            | Tipo   | Default | Para qué                                                                                   |
|------------------|--------|---------|--------------------------------------------------------------------------------------------|
| `gitReview.path` | string | `""`    | Ruta al dispatcher cuando `git` no lo descubre (Decisión 3). Vacío = invocar `git review`. |

Deliberadamente mínima. Nada de opciones de presentación ni de comportamiento:
lo que el panel muestra lo determina la CLI, y agregar ajustes crearía estado
del lado de la extensión que puede divergir de ella.

## Documento virtual del *why*

| Campo     | Valor                                  |
|-----------|----------------------------------------|
| Esquema   | `git-review-why`                       |
| Contenido | el payload de `status --why`, tal cual |
| Modo      | Markdown, sólo lectura                 |

El URI incorpora el path de la entrada; el contenido se resuelve en el momento,
sin caché (ver `data-model.md`, `Why`).

## Motor

`engines.vscode: ^1.75.0` (Decisión 12). Compatible con Windows, macOS y Linux
sin código específico por plataforma (FR-028) — la única diferencia por sistema
operativo es el descubrimiento del ejecutable, que resuelve `git`.
