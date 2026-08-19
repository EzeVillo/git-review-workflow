# Contrato (enmienda): la ruta en `status --porcelain` y la marca en `list --porcelain`

**Feature**: `012-prompt-agente-draft`

Dos enmiendas aditivas, en un solo documento porque son la misma pregunta
—«¿este borrador dónde está y de quién es?»— contestada en las dos superficies
que ya hablan de una review concreta.

Enmienda a
[`001-contrato-porcelain/contracts/status-porcelain.md`](../../001-contrato-porcelain/contracts/status-porcelain.md),
[`011-.../contracts/status-porcelain-draft.md`](../../011-walkthrough-draft-revisor/contracts/status-porcelain-draft.md)
y al contrato de `list --porcelain`. Las gramáticas v1 no cambian.

---

## 1. `status --porcelain`: el registro `draft` gana un campo

**Antes** (011): registro de presencia sin campos.

```text
draft
```

**Ahora**:

```text
draft<TAB><path>
```

| Campo | Valor |
| --- | --- |
| `<path>` | Ruta **absoluta** del borrador en vigor de esta review, ya resuelta (FR-020) |

**Cuándo se emite**: exactamente cuando se emitía antes — la review activa corre
sobre un borrador del revisor (`mode = walk` y `walk_is_draft` verdadero sobre
`${walk_draft_src:-$src}`). Sin cambios en la condición.

**Alcance**: sigue hablando **sólo** de la review de la rama en la que se
consulta. No reporta borradores sueltos: eso es
[`config-porcelain-drafts.md`](config-porcelain-drafts.md) (FR-020, última
frase).

### Por qué un campo y no un registro nuevo

Porque acá sí es seguro, y está verificado en los tres clientes publicados:

| Cliente | Cómo parsea `draft` | Efecto de un campo extra |
| --- | --- | --- |
| VS Code | `case "draft": isDraft = true` ([porcelain.ts:334](../../../vscode-extension/src/cli/porcelain.ts)) | ninguno |
| JetBrains | `"draft" -> isDraft = true` ([Porcelain.kt:241](../../../jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Porcelain.kt)) | ninguno |
| Visual Studio | `case "draft": isDraft = true` ([Porcelain.cs:264](../../../visualstudio-extension/src/GitReview.Domain/Porcelain.cs)) | ninguno |

Ninguno valida la aridad de ese registro, y los tres declaran ignorar campos
extra al final de un registro conocido. Es lo contrario del registro `state`,
que los tres parsean **por posición** y por eso 011 no lo ensanchó.

El path va **último**, que es la regla de texto libre del contrato: es el único
campo que podría contener un tab.

### Salida legible

**No cambia.** La línea de modo sigue siendo `mode    walk (draft)  [3/12] on
…`. El campo existe para que ningún cliente derive la ruta (SC-008); un usuario
de terminal ya sabe dónde está su borrador porque el verbo que lo creó se lo
dijo.

---

## 2. `list --porcelain`: registro `branch-draft`

```text
branch-draft<TAB><branch>
```

| Campo | Valor |
| --- | --- |
| `<branch>` | El nombre de la rama de review, verbatim, tal como salió en su registro `branch` (`review/feature/x`, `review-saved/feature/x`) |

**Cuándo se emite**: cero o una vez por cada fila `branch`, cuando esa review
carga un borrador — la **misma** condición que hoy decide el sufijo `(draft)` de
la salida legible ([list:114-130](../../../bin/git-review-verbs/list)):

- el nombre sale de `walk_review_draft_src` (no del `reviewsource`: para un
  `compare` de una rama de tracking no son el mismo string);
- para una fila `review-saved/*` se mira el namespace archivado **y** además
  `walk_saved_draft_filed`, porque dos reviews pausadas de una misma rama
  comparten el nombre del archivado y sólo una lo escribió;
- la condición es la de **custodia** (el archivo existe), no la de «en vigor»:
  es la fila que le entrega ese archivo a `forget --saved`.

**Posición exacta**: inmediatamente después de su fila `branch` y **antes** del
registro `finish` que `describe_porcelain` ya puede emitir para esa misma review.
No es cosmético: `tests/porcelain-bytes.bats` compara la salida byte a byte, así
que sin fijarlo el orden queda a merced de cómo se escriba el `if`, y dos
implementaciones igual de correctas dan suites distintas.

**En todos los modos**, no sólo en walk: el borrador viaja con la review también
en `step` y `whole`, y marcar sólo walk dejaría prosa que ninguna superficie
llegó a mostrar antes de que `forget --saved` se la llevara. Es la misma regla
que la salida legible ya aplica.

**Una sola casa para la condición.** Hoy la regla del `(draft)` vive en
`describe()` y el registro nuevo iría en `describe_porcelain()`: dos funciones
distintas, la misma decisión. Se extrae a un helper único al que llaman las dos.
Duplicarla y confiar en un test de paridad es exactamente el patrón que este
proyecto evita en el resto del código de walk — la condición tiene tres partes
(`walk_review_draft_src`, el namespace archivado, `walk_saved_draft_filed`), y
una copia que se olvida de la tercera pasa el ojo y no el caso.

### Por qué un registro y no un campo

El registro `branch` termina en **dos campos opcionales que se omiten juntos**:

```text
branch	<name>	<saved>	<current>	<orphan>	<mode>	<position>	<total>
branch	<name>	<saved>	<current>	<orphan>	<mode>
branch	<name>	<saved>	<current>	1
```

Un campo más al final sería ambiguo — un consumidor no puede decidir si el sexto
campo es la marca o `position`. Un registro propio no puede desalinear nada, y
un cliente que no lo conoce lo ignora. Es la misma decisión que 011 tomó para
`draft` en `status`, por el mismo motivo, y no se contradice con la enmienda 1
de este documento: ahí el registro no tiene campos opcionales.

### Salida legible

**No cambia.** El sufijo `(draft)` ya está desde 011; esto le da a los clientes
lo que ya se le muestra a una persona (FR-023).

---

## Compatibilidad

Las dos son aditivas. Un repositorio sin borradores emite exactamente la salida
de hoy, byte por byte, en los dos verbos.

## Tests

`tests/status-porcelain.bats` y `tests/list.bats` (casos nuevos).

| Caso | Afirma |
| --- | --- |
| `status --porcelain` en walk sobre borrador | El registro `draft` trae un segundo campo, absoluto, y `[ -f ]` sobre él es verdadero |
| `status --porcelain` en walk sobre el sidecar del autor | **No** hay registro `draft`; la salida es idéntica a la de antes |
| `status --porcelain` en `whole` / `step` con borrador en custodia | Sin registro `draft` (la condición no cambió) |
| `compare` de una rama de tracking | La ruta apunta al borrador de la **rama**, no al del ref con el que se nombró |
| Salida legible de `status` | Byte por byte idéntica a la de antes del cambio |
| `list --porcelain` con review activa y borrador | Un `branch-draft` justo después de su `branch` |
| `list --porcelain`, review pausada que archivó su borrador | `branch-draft` presente |
| `list --porcelain`, segunda review pausada de la misma rama que **no** archivó | **Sin** `branch-draft` (`walk_saved_draft_filed`) |
| `list --porcelain` en modo `whole` / `step` con borrador | `branch-draft` presente |
| Sin borradores | Ningún `branch-draft`; salida idéntica a la de antes |
| Paridad legible/porcelain | Toda fila con `(draft)` en la salida legible tiene su `branch-draft`, y viceversa |
