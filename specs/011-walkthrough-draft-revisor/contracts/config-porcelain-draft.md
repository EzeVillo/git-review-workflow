# Contrato (enmienda): ofertas `draft` en `config --porcelain`

**Feature**: `011-walkthrough-draft-revisor`

Enmienda aditiva a
[`008-start-layout-offers/contracts/config-porcelain-offers.md`](../../008-start-layout-offers/contracts/config-porcelain-offers.md).
No reemplaza ese archivo: describe el delta. La invocación, los flags, la
gramática porcelain v1 y la forma del registro no cambian.

## Delta

Dos ids nuevos para el registro `offer`, cuya forma sigue siendo:

```text
offer<TAB>id<TAB>rank
```

- `id` pasa a ser: `walk` | `keys` | **`draft`** | **`draft-resume`** | `step` | `whole`
- `rank` no cambia: `recommended` | `available`

### Reglas de viabilidad (delta)

| id | Emitir cuando | Rank |
| --- | --- | --- |
| `draft` | **no** existe borrador para `<branch>` **y** no se emitió `walk` | `available` |
| `draft-resume` | existe borrador para `<branch>` | `available` |

- Son **mutuamente excluyentes**: nunca se emiten los dos.
- `draft` exige que no se haya emitido `walk`. Es la regla que implementa
  FR-016a: si el PR trae walkthrough del autor utilizable, el asistente no
  propone reemplazarlo.
- `draft-resume` **sí** se emite junto con `walk`, y es el caso normal cuando el
  revisor ya tiene borrador: es legible (por eso `walk`) y todavía completable
  (por eso `draft-resume`).
- Ambos requieren, como `step` y `whole`, que tip y lower sean resolubles.

### Orden de emisión

Estable y ampliado en un solo punto:

```text
walk, keys, draft|draft-resume, step, whole
```

Los ids no viables se omiten. Nunca se reordena por locale.

## Ejemplos

PR sin walkthrough, sin borrador:

```text
offer	draft	available
offer	step	available
offer	whole	available
```

Mismo PR, con borrador del revisor ya empezado:

```text
offer	walk	recommended
offer	draft-resume	available
offer	step	available
offer	whole	available
```

PR con walkthrough del autor, sin borrador (**sin cambios respecto de hoy**):

```text
offer	walk	recommended
offer	keys	available
offer	step	available
offer	whole	available
```

## Compatibilidad

Aditivo por diseño. Un cliente publicado que no conoce los ids nuevos los
ignora y sigue viendo exactamente las mismas ofertas que hoy — incluido el caso
en que hay borrador, donde `walk` ya le alcanza para ofrecer la lectura.

## Coste

La viabilidad de los dos ids se decide con un test de existencia de archivo
(builtin del shell): cero procesos nuevos por invocación. Es una restricción
dura y no una preferencia — `config --porcelain` se invoca en cada apertura del
asistente, y el proyecto ya sufrió regresiones de segundos bajo Git Bash por
agregar procesos en caminos calientes.
