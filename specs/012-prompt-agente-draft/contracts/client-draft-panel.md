# Contrato: el borrador en el panel, y el asistente que termina

**Feature**: `012-prompt-agente-draft`

Normativo para los **tres** clientes. Paridad de producto: mismo bloque, mismos
controles, mismas etiquetas, mismas decisiones. El vehículo de interfaz es
propio de cada plataforma.

Reemplaza el bucle de espera de
[`011-.../contracts/client-draft-flow.md`](../../011-walkthrough-draft-revisor/contracts/client-draft-flow.md)
por un estado persistente del panel. Lo que sobrevive de aquel contrato: los
metadatos de las ofertas (con la copy reescrita, abajo), las prohibiciones, y
que el cliente guarda el borrador antes de validarlo.

---

## 1. El bloque `draft_block`

### Dónde va

**Como primer bloque de la situación `no-review`**, con `when: has_drafts`. El
cuerpo de siempre —inventario de reviews, *No active review on this branch*,
**Start a review**, y el pie con *Other actions* / *Settings* / *Support*—
**sigue entero debajo** (FR-025, decisión Q4 de la spec).

No es una sub-disposición que reemplace, como `no-review-setup`: sin base
configurada no hay nada más que hacer en ese panel, con un borrador a medio
escribir sí. Por eso se declara como bloque condicional dentro de `no-review` y
no como una clave nueva de `panel_layout` — que además obligaría a duplicar toda
la lista de bloques del cuerpo en el canónico.

### Qué dibuja

```text
Reading orders you started            ← heading, sólo si hay ≥1

  feature/telemetry        3/9         ← una fila por registro `draft`
  [Open] [Copy for agent] [Validate and start] [Discard]

  feature/pagos            0/5
  [Open] [Copy for agent] [Validate and start] [Discard]
```

| Parte | Contenido |
| --- | --- |
| Nombre | `<src>` del registro, verbatim |
| Progreso | `<annotated>/<total>` tal como lo reporta la CLI. **Ningún cliente lo deriva** (FR-027, SC-008) |
| Controles | Los cuatro, siempre los cuatro, sobre **esa** fila (FR-026) |

Una acción sobre una fila no afecta a las demás: cada control lleva el índice de
su fila, igual que los de `InventoryRows`.

### Los cuatro controles

| id (wire) | Rótulo | Énfasis | Confirma | Qué hace |
| --- | --- | --- | --- | --- |
| `openDraft` | `Open` | secondary | no | Abre `<path>` para editar |
| `copyDraftPrompt` | `Copy for agent` | secondary | no | Pone el texto del § 2 en el portapapeles |
| `startFromDraft` | `Validate and start` | primary | sí | `draft --build`, y en verde el `start` |
| `discardDraft` | `Discard` | secondary | **sí** | `forget --draft -- <src>` |

**No son acciones nuevas del producto.** Son controles del cuerpo del panel,
como `copyCliInstall`, `outOfRangeHelp` y `openSupport`: sin la fila que los
dibuja no tienen sujeto. La matriz de `actions:` sigue teniendo **27 entradas**,
`contributes.commands` sigue teniendo 27, el menú **Tools → git review** de
Visual Studio y el de JetBrains no cambian, y el conteo fijo del verificador no
se toca.

Se declaran en el canónico en un mapa `draft_controls:` paralelo a
`inventory_controls:`, y `collectCanonicalControls()` de
`scripts/check-client-product-surface.mjs` se extiende para leerlo —la misma
extensión que ya existe para el otro mapa—. Del lado de la extensión, los cuatro
ids se suman a `PANEL_MESSAGES`.

### Comportamiento de cada control

**`openDraft`** — abre el archivo en `<path>`, la ruta que reportó la CLI. El
cliente **no** la arma. Abrirlo es mostrarlo, no leerlo: no se interpreta un
byte.

**`copyDraftPrompt`** — ver § 2. No abre ninguna conexión, no invoca ningún
modelo, no se integra con ningún asistente (FR-028).

**`startFromDraft`** (FR-029, FR-030):

```text
1. guardar el documento del borrador si está abierto y sucio (y sólo ése)
2. git review walkthrough draft --build <flags> -- <src>
     ├─ rojo  → mostrar el stderr aplanado; el panel queda EXACTAMENTE igual
     │          y el borrador intacto. Fin.
     └─ verde → 3
3. git review config --porcelain <flags> -- <src>
     ├─ hay `keys` → preguntar recorrido completo vs sólo esenciales
     └─ no hay     → seguir sin preguntar
4. confirmación y git review start <flags>, como cualquier otra forma de lectura
```

El paso 1 es el requisito 6 de 011 y sigue vigente por el mismo motivo: VS Code
no autoguarda por defecto e IntelliJ guarda al perder el foco, que es justo lo
que no ocurre mientras el panel conduce.

**`<flags>` no son los default: salen de la fila.** Los campos `<source>` y
`<range>` del registro `draft` se traducen a `--local` / `--offline` / nada y
`--delta` / nada, y se pasan **iguales en los tres pasos**.

Usar los default sería un botón que **falla siempre** sobre cualquier borrador
hecho con `--delta`, `--local` u `--offline`: esos flags cambian el rango, el
rango cambia el conjunto de paths, y `--build` muere por deriva sin que el panel
tenga nada que ofrecer. No es un caso raro —los tres flags están soportados y
`--delta` es el camino recomendado para revisar lo nuevo de un PR ya revisado—
y el revisor no tiene forma de saber por qué falla. Replicar los flags cuesta
leer dos campos que ya vienen en el registro.

**Si `<source>` o `<range>` valen `unknown`** (el bloque de instrucciones se
borró a mano, cosa permitida), la fila **no ofrece** `startFromDraft`: se muestra
sin ese control, con el resto disponible. Adivinar los flags acá sería exactamente
el fallo silencioso que estamos sacando, sólo que del lado del cliente.

**`discardDraft`** (FR-031) — confirmación explícita antes de borrar prosa
escrita a mano, y recién entonces `git review forget --draft -- <src>`. El
diálogo nombra el verbo real que se va a correr, como ya hace `discardInventory`.

### Cuándo NO aparece

- Con cualquier situación distinta de `no-review`. Una review en curso es
  siempre lo más importante que el panel tiene para decir, y el borrador de otra
  rama no le compite el cuerpo.
- Con `no-review` en modo setup (sin base): esa sub-disposición reemplaza el
  cuerpo entero y sigue haciéndolo.
- Con cero registros `draft`.
- **Sobre un borrador de una review pausada**: no hace falta filtrar, la CLI no
  lo reporta (su archivo está en el namespace archivado). SC-012 se cumple
  aguas arriba.

---

## 2. La instrucción para el agente

Lo que `copyDraftPrompt` pone en el portapapeles. **Es un puntero, no un
prompt**: la consigna vive en el archivo.

```text
Fill in the reading order at <path>. The instructions are inside the file, in
the comment at the top. Do not change the file list or the numbering rules.
```

| Regla | Motivo |
| --- | --- |
| Incluye `<path>` — el de **esa** fila, absoluto | FR-028: tiene que bastar para que el agente encuentre el archivo |
| Es idéntico en los tres clientes, byte por byte | US5 escenario 2 |
| Es corto y no repite la consigna | La consigna está en el archivo (asunción de la spec, no se re-litiga) |
| No nombra ningún modelo, servicio ni asistente | FR-028, y la frontera que 011 ya trazó |

Vive en un solo lugar por cliente y el verificador lo compara contra el canónico
como un string más de `strings:`. Los tres archivos, nombrados, porque el
verificador necesita una ruta concreta y **en la extensión no existía ningún
módulo equivalente**:

| Cliente | Archivo |
| --- | --- |
| VS Code | `vscode-extension/src/review/userCopy.ts` — **nuevo**; es el `UserCopy` que le faltaba a este cliente |
| JetBrains | `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/UserCopy.kt` |
| Visual Studio | `visualstudio-extension/src/GitReview.Domain/UserCopy.cs` |

Crear el módulo en la extensión en vez de dejar el string suelto en el comando no
es simetría por simetría: el verificador compara los tres contra el mismo
canónico, y un string incrustado en un archivo de comando obliga a que el check
lo busque con una expresión sobre código en vez de sobre una constante — que es
frágil justo cuando el texto cambia, que es lo único que este check existe para
detectar.

---

## 3. El asistente deja de esperar

### Qué se retira

El aviso no bloqueante de 011 (`wait` / `dismiss` / `Continue` / `Cancel`, la
notificación de VS Code y el `DraftWaitDialog` de IntelliJ) **desaparece**
(FR-032, SC-010).

### Qué queda

Al elegir la oferta `draft` o `draft-resume` en el paso de forma de lectura:

```text
1. crear (sólo con id `draft`) ──► git review walkthrough draft [flags] -- <branch>
      ├─ falla ──► mostrar el stderr y VOLVER al paso de forma de lectura,
      │            sin rehacer la elección de rama (US4 escenario 3)
      └─ ok    ──► 2
2. el asistente TERMINA. No queda ninguna espera abierta.
```

**El asistente no abre el borrador**, y por eso no necesita su ruta. Es lo que
cierra el único hueco que quedaba en la prohibición de derivarla: en el instante
posterior a crear todavía no hay registro `draft` que la traiga, así que abrir
ahí habría exigido o re-invocar `config --porcelain` sólo para eso, o volver a
armar la ruta — que es justo lo que la feature retira.

No es una renuncia: el refresco que sigue a toda mutación ya invoca
`config --porcelain`, así que el bloque del § 1 aparece con la fila y su `<path>`
un instante después, y *Open draft* abre desde ahí con la ruta que dio la CLI.
Se eliminó un paso en vez de agregar uno.

Y es coherente con el resto: el asistente abría el archivo **porque se iba a
quedar esperando sobre él**. Sacada la espera, abrir era el último resto del
bucle modal.

El revisor aterriza en el estado del panel del § 1, donde su borrador está
visible con sus cuatro controles. La continuación vive ahí.

`draft-resume` salta el paso 1: el archivo ya existe y volver a crearlo pisaría
lo escrito.

`DraftFlowState` / `DraftFlowEvent` se reducen a esos tres pasos en los tres
dominios; los casos `wait`, `dismiss`, `build`, `reload` y `pickKeys` se retiran
del bucle del asistente. Lo que hacían `build`/`reload`/`pickKeys` es ahora
`startFromDraft`, en el panel.

### La copy de la oferta (FR-033, SC-011)

Tiene que decir qué se obtiene y cuál es la alternativa, sin jerga interna. En
particular, sin la palabra *walkthrough* como si fuera un término conocido.

| id | label | description |
| --- | --- | --- |
| `draft` | `Build a reading order first` | `nobody wrote one for this PR; otherwise you read the whole diff` |
| `draft-resume` | `Finish the reading order you started` | `pick up the one you left half-written` |
| `draft-update` | `Update the reading order you wrote` | `the PR moved on; keeps the whys whose files are still in range` |

Las tres son excluyentes y **cuál llega la decide la CLI**, que es la única que
puede: la pregunta que separa `draft-resume` de `draft-update` es si el orden
sigue cubriendo el rango, y contestarla necesita el tip contra el que se escribió
el borrador *y* el de hoy. El campo `state` del registro `draft` **no** sirve de
sustituto — contesta otra pregunta ("¿ya se leyó este orden?"), a propósito, así
que una rama que avanzó después de su review sigue diciendo `reviewed`.

Ningún cliente pregunta cuál de las dos corresponde. Hubo un modal que lo hacía
—*Update* / *Start over* sobre cualquier borrador ya usado— y se retiró junto con
el paso `START_OVER` de `DraftStep`: sobre un rango que no se había movido,
*Update* era un no-op que dejaba al revisor en una fila `reviewed`, o sea sin
*Copy for agent* ni *Validate and start*. Empezar de cero sigue existiendo como
acto deliberado (Discard en la fila, o `walkthrough draft --force`), que es donde
corresponde: del lado del revisor el archivo no está en git y no hay vuelta atrás.

Byte por byte iguales en los tres `OFFER_META`
([layoutOffers.ts](../../../vscode-extension/src/review/layoutOffers.ts),
[LayoutOffers.kt](../../../jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/LayoutOffers.kt),
[LayoutOffers.cs](../../../visualstudio-extension/src/GitReview.Domain/LayoutOffers.cs)),
y sus tests unitarios se mueven con ellas. `OFFER_ORDER` no cambia.

---

## Prohibiciones

- Ningún cliente lee, parsea, valida ni escribe el archivo del borrador.
- Ningún cliente **arma** la ruta del borrador. `gitdirFromLink` y el
  `path.join(gitdir, "review-walkthrough", …)` de
  [`startReview.ts`](../../../vscode-extension/src/commands/startReview.ts) se
  retiran: la ruta llega por porcelain (SC-008).
- Ningún cliente deriva la existencia de un borrador ni su progreso.
- Ninguna llamada a un servicio de IA, ni sugerencia de una.
- Ninguna acción nueva en `actions:`, en `contributes.commands`, en el menú de
  JetBrains ni en el `.vsct` de Visual Studio.

## Verificación

| Punta | Qué |
| --- | --- |
| `scripts/check-client-product-surface.mjs` | `draft_controls` × rótulo × énfasis contra `panelHtml.ts`; los cuatro ids en `PANEL_MESSAGES`; el texto del portapapeles como string del canónico; `min_cli_version` contra las tres constantes |
| `PanelLayoutContractTest` (Kotlin, `./gradlew test`) | `panelLayout(fixture)` con drafts, estructura completa |
| `PanelLayoutContractTests` (xUnit, `dotnet test`) | Ídem |
| `dotnet run --project src/GitReview.VS -- --verify` | Render real; los botones deshabilitados siguen saliendo del chrome |
| `npm run test:unit` | Parseo del registro, `PanelDraft`, argv de los cuatro controles, texto del portapapeles |
| `./vscode-extension/test/run-docker.sh` | El bloque se dibuja con N filas; el cuerpo de siempre sigue debajo; cada control invoca lo suyo; el asistente cierra sin dejar aviso |
| `npm run preview` | El estado nuevo entra en `preview/fixtures.ts` |
