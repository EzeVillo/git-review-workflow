# Modelo de datos: comentarios portables

Diseño para [spec.md](spec.md). Las entidades de custodia no agregan estados
de resolución a los comentarios. Las rutas internas pertenecen al gitdir del
worktree; no a `--git-common-dir`, reservado a la guía compartida existente.

## Contexto documental

| Campo | Tipo / significado |
|-------|--------------------|
| `context` | Token opaco de contexto, hexadecimal validado; no id de entrada |
| `kind` | `review` o `compare` |
| `source`, `target` | Origen canónico y destino de integración para buscar continuidad |
| `full_base`, `last_tip` | OID completos; rango completo independiente del lower/delta |
| `generation` | Último resultado conservado completo |
| `source_baseline` | Presencia y bytes del Compartido fuente que produjo ese resultado |
| `owner_gitdir` | Identidad del worktree que custodia archivos locales |

El marcador portable de Compartido asocia clones al mismo contexto. Local
nunca se importa del compartido. Sin marcador, se usa el registro local y la
relación de ancestros; los casos ambiguos se resuelven explícitamente. Dos PR
de proveedor con idéntico linaje no se distinguen automáticamente con Git.
La resolución exacta está en [lifecycle.md](contracts/lifecycle.md).

## Sesión y checkpoint

| Campo | Tipo / significado |
|-------|--------------------|
| `session` | Token único de una ejecución de review/compare |
| `context`, `owner_gitdir` | Propiedad del trabajo y ubicación de custodia |
| `custodian` | Rama activa o guardada autorizada a continuar/descartar |
| `mode`, `capture_base`, `capture_head`, `cursor` | Contexto exacto de captura actual |
| `baseline` | Presencia/bytes de ambos documentos al comenzar la pasada |
| `discard_checkpoint` | Baseline inicial o última generación guardada en compare |
| `destination_baseline` | Presencia/bytes del archivo versionado al comenzar |
| `delivery` | Sin cambios, preparado o pendiente de entrega tras extraer código |

Antes de confirmar un contexto fresh/ambiguo, la sesión puede ser provisional:
no lleva todavía `context` ni documentos editables. Su token de guarda se
deriva del estado de review y existe igualmente; confirmar la primera captura
valida esa guarda antes de materializar contexto y destino.

Metadata de rama nueva: `reviewcommentscontext`, `reviewcommentssession` y
`reviewcommentsowner`. Son comunes a todos los modos y se permiten expresamente
en los guards de metadata, sin reutilizar claves step/walk. Se leen con
`|| true`. Sesiones previas a la función pueden inicializar custodia al pedir
una primera mutación; consultar no crea documentos ni modifica config.

## Documento

| Campo | Regla |
|-------|-------|
| `document` | `local` o `shared`; se elige en cada captura |
| `path` | Ruta absoluta reportada por la CLI; los clientes no la reconstruyen |
| `presence` | Ausente y vacío son distintos |
| `bytes_revision` | Hash de bytes más presencia; `absent` indica ausencia y `unreadable` indica archivo existente sin revisión legible, sin habilitar escritura (D22) |
| `count` | Cantidad de encabezados de entrada válidos; no disponible si no puede leerse/parsearse |
| `diagnostics` | Lectura, estructura, identidad, ubicación o entrega; no estado de comentario |

Presencia usa existencia de archivo; contenido se interpreta por separado.
Los resultados conservados contienen Local y Compartido como archivos distintos,
incluso cuando sólo el segundo se destinará al repositorio.

## Entrada y ubicación

Una entrada es un bloque físico de Markdown: número visible, etiqueta libre,
cuerpo, metadata opcional y posición física derivada. No persiste id, tipo de
observación ni respuesta. Su selector temporal es `(context, document,
bytes_revision, ordinal)`. Copiar y pegar un bloque conserva sus referencias
sin requerir una operación de traslado del producto.

La ubicación puede ser general, archivo o rango inclusivo 1-based. La referencia
versionada contiene `base`, `head`, `base-path`, `head-path`, `side` y líneas
cuando correspondan. Los extremos aceptan commit/tree; la receta de consulta
deriva sus blobs. Un archivo no versionado o buffer sucio conserva ubicación y
`unversioned=1`; no se atribuyen sus bytes al head del PR.

## Persistencia

```text
<gitdir>/review-comments/
├── contexts/<context>/manifest
├── results/<context>/current
├── results/<context>/<generation>/{manifest,local.md,shared.md}
├── sessions/<session>/
│   ├── manifest
│   ├── local.md
│   ├── shared.md
│   ├── baseline/{manifest,local.md,shared.md}
│   └── source-baseline.md
└── locks/<context>.lock/
```

Los archivos ausentes no se materializan como vacíos; su presencia figura en
el manifest. Un token se valida antes de construir paths; las rutas de entradas
nunca se concatenan en este árbol. `current` se reemplaza después de completar
la generación entera. Las generaciones bajo edición fuera de sesión también
se protegen con revisión de bytes: no se presupone que un editor respete locks.

El manifest de generación registra `local_revision` y `shared_revision` como
límite de publicación, además de la presencia. Esos hashes no cambian cuando
se editan después los archivos conservados. Antes de `finish --abort`, se
comprueban ambos documentos: si un editor antiguo modificó la preparación
original y difiere del resultado actual, se preservan las dos versiones y no
se sobrescribe ninguna. Ausencia y archivo vacío también se propagan al volver
a la preparación; no se resucita un documento borrado deliberadamente.

El puntero `results/<context>/current` es también el checkpoint de descarte de
compare. No existe un segundo puntero que pueda fallar después de publicar el
par. Si falla publicar un cierre, la sesión aún custodiada se expone como
recuperación hasta conservar una generación íntegra; limpiar no la elimina
antes de lograr esa conservación. Deshacer el cierre vuelve al estado preparado
y deja de anunciar el destino anterior como entrega realizada o pendiente.

`save` de review cambia el custodio al `review-saved/*` conservando directorio
y baseline. `continue` revierte esa transferencia sólo tras validar propiedad.
No se usa un nombre de rama como ruta exclusiva de los documentos.

## Transiciones

| Suceso | Preparación | Resultado conservado | Archivo versionado |
|--------|-------------|----------------------|--------------------|
| Inicio | Carga documentos previos aplicables y baselines | No cambia | No cambia |
| Captura/edición/renumeración | Cambia sólo el documento elegido | No cambia durante sesión | No cambia |
| next/prev | Persiste completa; cambia contexto de nuevas capturas | No cambia | No cambia |
| save/continue | Transfiere custodio, conserva ambos | No publica resultado nuevo | No cambia |
| comments save en compare | Sigue editable; checkpoint avanza | Publica ambos localmente | No cambia |
| finish exitoso | Se conserva para undo | Publica ambos | Entrega sólo Compartido modificado |
| finish con entrega fallida | Conserva preparado y diagnóstico | Conserva ambos para recuperar | No sobrescribe destino ajeno |
| finish --abort | Vuelve a edición con prosa actual | No pierde documentos | Restaura según undo protegido |
| abort de sesión / forget saved | Descarta posterior al checkpoint | Respeta anterior o guardado en compare | Respeta documento previo del PR |
| clean de review completada | Libera custodia auxiliar | Conserva resultados | Política actual de ramas |

Una escritura concurrente del mismo Compartido se compara contra su baseline;
Local jamás participa en esa conciliación. Si fuente y preparado evolucionaron
por separado se conservan ambas versiones, sin fusión automática.
