# Plan de consolidación del contrato porcelain

> **Esto no es un contrato de formato.** El contrato vigente de
> `git review status` es y sigue siendo
> [`001-contrato-porcelain/contracts/status-porcelain.md`](../../001-contrato-porcelain/contracts/status-porcelain.md).
> Este documento describe **qué cambia ahí** y **qué se elimina**, para que la
> consolidación (US3) sea verificable sin leer el diff. Crear acá un tercer
> documento de formato sería reproducir el problema que US3 cierra.

## Estado inicial

El contrato del verbo está partido en dos:

| Documento | Rol actual |
|-----------|-----------|
| `001-contrato-porcelain/contracts/status-porcelain.md` | Base: invocación, exit codes, `state`, `entry`, paths, `--why` |
| `003-paridad-cli-panel/contracts/status-porcelain-v2.md` | Delta: `subject`, `author`, `base`, y la regla del texto libre |

El rótulo `v2` nunca describió una versión del formato — el propio documento
declara *"Sigue siendo formato porcelain v1"*. Es un número de secuencia de
documentos disfrazado de número de versión de protocolo.

## Estado final

Un solo documento vigente, `001-contrato-porcelain/contracts/status-porcelain.md`,
que describe el formato completo. El delta se elimina.

## Cambios sobre el documento consolidado

### 1. Absorber el delta

Se incorporan, sin cambios de contenido:

- La **regla del texto libre** (último campo del registro, uno por registro, sin
  escapar) y su corolario: esos registros no admiten campos nuevos al final.
- Los registros **`subject`** y **`author`** (sólo `step`).
- El registro **`base`** (sólo `whole`, sólo si hay una registrada).
- La tabla de **exclusiones registradas** (cuerpo del mensaje, diffstat, textos de
  ayuda).

### 2. Corregir la regla de `entry` por modo

La línea vigente dice:

> En `whole` no hay registros `entry` en absoluto.

Queda reemplazada por la regla nueva (FR-002, FR-017):

> En `whole` hay un registro `entry` por archivo del rango, sin ninguno de los dos
> grupos de campos finales.

Y la descripción del registro pasa a cubrir los tres modos:

```
entry<TAB>position<TAB>id[<TAB>essential<TAB>annotated|<TAB>banked]
```

| Modo | `id` | Campos finales |
|------|------|----------------|
| `step` | SHA corto del commit | `banked` |
| `walk` | path | `essential`, `annotated` |
| `whole` | path | ninguno |

### 3. Fijar que `state` de `whole` no cambia

Explícito, porque es la pregunta que un lector se hace al ver entradas en `whole`:
el registro `state` **no** gana `position`/`total`/`recorded`/`current`. La lista es
un inventario, no una secuencia con cursor (FR-004).

### 4. Extender la regla de paths a `whole`

La sección de paths ya cubre `state.current` de `walk` y el `id` de `entry`. Pasa a
nombrar los tres modos: donde el `id` es un path, valen las mismas reglas de bytes.

### 5. Registrar que el sidecar ya no se filtra

El contrato describe hoy `annotated` mencionando los archivos del rango sin entrada
propia. Se agrega que **los archivos bajo `.review/` están incluidos** en esa
categoría (FR-020), con la excepción del generador de entradas, que no es una
superficie del contrato.

## Referencias a reapuntar

El archivo eliminado está nombrado en siete lugares. Todos pasan a apuntar al
documento consolidado:

| Archivo | Qué es |
|---------|--------|
| `bin/git-review-verbs/status:148` | Comentario que justifica el texto libre en su propio registro |
| `vscode-extension/src/cli/porcelain.ts:45` | Comentario del mapa de `subjects` |
| `specs/003-paridad-cli-panel/tasks.md:11` | Enlace del encabezado |
| `specs/003-paridad-cli-panel/tasks.md:213` | Cita de la regla de orden entre registros |
| `specs/003-paridad-cli-panel/quickstart.md:5` | Enlace |
| `specs/003-paridad-cli-panel/plan.md:117` | Árbol de archivos de la feature |
| `specs/003-paridad-cli-panel/data-model.md:126` | Enlace a la tabla de exclusiones |

Los cuatro de `003` son documentos históricos de una feature cerrada: **se les
actualiza el enlace, no el relato**. Un registro histórico puede describir lo que se
hizo entonces, pero no puede apuntar a un archivo que ya no existe.

## Criterio de verificación

`grep -ri 'porcelain[- ]v2\|status-porcelain-v2' .` no devuelve nada, y el único
rótulo de versión del formato presente en el repositorio es `v1` (SC-005).
