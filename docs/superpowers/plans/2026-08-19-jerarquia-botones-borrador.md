# Jerarquía de botones de la fila del borrador — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** que la fila del bloque *Reading orders you started* tenga un solo control enfático, que ese control siga al progreso del borrador, y que el destructivo deje de ser vecino del de compromiso — en los tres clientes.

**Architecture:** el contrato canónico (`contracts/client-product-surface.yaml`) gana dos claves opcionales en `draft_controls` (`emphasis_unfilled`, `separated`) y `openDraft` pasa a control de icono. Los tres clientes proyectan eso desde su dominio (JetBrains y Visual Studio con `Control`/`Emphasis`; VS Code decidiendo la clase CSS en `renderDraft`). Los tres verificadores anti-drift leen las claves nuevas.

**Tech Stack:** TypeScript + esbuild (VS Code), Kotlin + Gradle (JetBrains), C# .NET 8 + xUnit (Visual Studio), Node (el checker del contrato), YAML (el canónico).

## Global Constraints

- **El orden de los controles no cambia con el estado.** Sólo el énfasis. Orden final en los tres: `copyDraftPrompt`, `startFromDraft`, `openDraft`, `discardDraft`.
- **`startFromDraft` nunca se deshabilita por progreso**, sólo por `busy`. El conteo sale del disco y el editor puede tener cambios sin guardar.
- **"Completo" es `annotated >= total`**, no `==`: un conteo raro de la CLI no debe dejar la fila sin primary.
- **Etiquetas visibles sin cambios:** `"Copy for agent"`, `"Validate and start"`, `"Discard"`. El accessible name nuevo de `openDraft` es `"Open the reading order"` y su tooltip sigue siendo `"Open the reading order for editing"`.
- **El conteo fijo de 27 acciones no se toca**: los cuatro siguen siendo controles del cuerpo, fuera de `actions:` y de `contributes.commands`.
- **Los README de la raíz no se tocan.** Es superficie de cliente, no de CLI.
- Spec: `docs/superpowers/specs/2026-08-19-jerarquia-botones-borrador-design.md`.

---

## File Structure

| archivo | responsabilidad en este cambio |
|---|---|
| `contracts/client-product-surface.yaml` | declara los cuatro controles con el énfasis condicional y `separated` |
| `scripts/check-client-product-surface.mjs` | parsea las claves nuevas y acepta un className ternario en `panelHtml.ts` |
| `vscode-extension/src/views/panelHtml.ts` | `renderDraft`, `iconButton` con índice, CSS `.sep` |
| `vscode-extension/preview/fixtures.ts` | una tercera fila completa (`1/1`) |
| `vscode-extension/test/unit/panelHtml.spec.ts` | los asserts sobre el HTML generado |
| `jetbrains-plugin/.../domain/PanelLayout.kt` | `Control.separated`, `ctrl(...)`, `draftRows(...)` |
| `jetbrains-plugin/.../ui/PanelRenderer.kt` | icono de `OPEN_DRAFT`, strut del control separado |
| `jetbrains-plugin/fixtures/.../PanelFixtures.kt` | la tercera fila |
| `jetbrains-plugin/src/test/.../PanelLayoutContractTest.kt` | orden, énfasis en los dos modos, separated |
| `visualstudio-extension/src/GitReview.Domain/PanelLayout.cs` | `Control.Separated`, `Ctrl(...)`, `DraftRows(...)` |
| `visualstudio-extension/src/GitReview.VS/ToolWindows/PanelView.cs` | glifo de `OpenDraft`, hueco del control separado |
| `visualstudio-extension/fixtures/PanelFixtures.cs` | la tercera fila |
| `visualstudio-extension/tests/.../PanelLayoutContractTests.cs` | lo mismo que el de JetBrains |
| `vscode-extension/README.md` + 3 `CHANGELOG.md` | la copy de producto |

---

## Task 1: El contrato y sus tres lectores

Deja el canónico en su forma final y enseña a los tres verificadores a leerlo. **Al terminar esta tarea los tres verificadores fallan a propósito**: describen la fila nueva y los clientes todavía dibujan la vieja. Las tareas 2-4 los ponen en verde de a uno.

**Files:**
- Modify: `contracts/client-product-surface.yaml:349-354`
- Modify: `scripts/check-client-product-surface.mjs:332-345` (parser de `draft_controls`), `:358-364` (`emphasisFromClassArg`), `:374-382` (regex de `iconButton`)
- Modify: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutContractTest.kt:150-193`
- Modify: `visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutContractTests.cs:207-279`

**Interfaces:**
- Produces: las claves `emphasis_unfilled` (opcional, el énfasis con `annotated < total`; `emphasis` es el del borrador completo) y `separated: true` (hueco mayor antes del control). `openDraft` pasa a `label: null` + `accessible_name`.

- [ ] **Step 1: Reescribir el bloque `draft_controls` del canónico**

En `contracts/client-product-surface.yaml`, reemplazar las cuatro líneas de `draft_controls:` por:

```yaml
draft_controls:
  # El énfasis sigue al progreso y el ORDEN no se mueve: mientras falten
  # entradas el paso siguiente es llenar el borrador, y recién con el orden
  # completo lo es arrancar la review. `emphasis:` es el valor con el borrador
  # completo; `emphasis_unfilled:` el de `annotated < total`. Sin la segunda
  # clave el énfasis no depende del progreso.
  copyDraftPrompt: {label: "Copy for agent", emphasis: secondary, emphasis_unfilled: primary, confirms: false}
  # NUNCA disabled por progreso, sólo por busy: el conteo sale del disco y el
  # revisor puede tener el borrador abierto con cambios sin guardar.
  startFromDraft: {label: "Validate and start", emphasis: primary, emphasis_unfilled: secondary, confirms: true}
  # Icono: el archivo vive fuera del árbol versionado y este control es la
  # única superficie que lo abre, pero su etiqueta era la que forzaba el wrap.
  openDraft: {label: null, accessible_name: "Open the reading order", emphasis: icon, confirms: false}
  # `separated`: un hueco mayor que el gap entre controles. Es el único
  # irreversible de la fila y no comparte vecindad con el de compromiso.
  discardDraft: {label: "Discard", emphasis: secondary, confirms: true, separated: true}
```

- [ ] **Step 2: Extender el parser de `draft_controls` del checker de Node**

En `scripts/check-client-product-surface.mjs`, reemplazar el `draftRe` y su bucle por:

```js
  const draftRe =
    /^ {2}([A-Za-z][A-Za-z0-9]*):\s*\{label:\s*(null|"[^"]*")\s*,\s*(?:accessible_name:\s*"([^"]*)"\s*,\s*)?emphasis:\s*(primary|secondary|link|icon)\s*(?:,\s*emphasis_unfilled:\s*(primary|secondary))?\s*,\s*confirms:\s*(true|false)(?:\s*,\s*separated:\s*(true|false))?\}/gm;
  let dm;
  while ((dm = draftRe.exec(draftBlock)) !== null) {
    // Un control con emphasis_unfilled tiene DOS enfasis validos: el cliente
    // elige con el progreso, asi que lo que se compara es el conjunto.
    const emphases = dm[5] ? [dm[4], dm[5]] : [dm[4]];
    controls.push({
      id: dm[1],
      label: dm[2] === "null" ? null : dm[2].slice(1, -1),
      accessible: dm[3] || null,
      emphasis: dm[4],
      emphases,
      raw: false,
      confirms: dm[6] === "true",
      separated: dm[7] === "true",
    });
  }
```

- [ ] **Step 3: Enseñarle a `emphasisFromClassArg` el className ternario**

Mismo archivo. `renderDraft` va a pasar `filled ? null : "primary"` como tercer argumento de `button()`, que hoy caería en el default `secondary` sin que nadie lo note. Reemplazar la función por:

```js
// Map emphasis className in button() third arg. Un ternario entre null y
// "primary" es un enfasis condicional: devuelve los DOS valores, que es lo que
// el canonico declara con emphasis_unfilled.
function emphasisFromClassArg(classArg) {
  if (classArg === "null" || classArg === undefined) return "secondary";
  if (classArg === '"primary"' || classArg === "'primary'") return "primary";
  if (classArg === '"link"' || classArg === "'link'") return "link";
  if (classArg === '"file-row"' || classArg === "'file-row'") return "secondary";
  const cond = /^[A-Za-z_$][\w$]*\s*\?\s*(null|"primary")\s*:\s*(null|"primary")$/.exec(classArg);
  if (cond) {
    return [cond[1], cond[2]].map((v) => (v === "null" ? "secondary" : "primary")).join("|");
  }
  return "secondary";
}
```

Y donde el check compara el emphasis de una llamada contra el canónico, aceptar el conjunto: un control con `emphases.length === 2` matchea si el className produjo los mismos dos valores en cualquier orden. Localizar la comparación (cerca de la línea 465, donde se usa `c.emphasis`) y hacerla pasar por:

```js
function emphasisMatches(canonical, actual) {
  if (!Array.isArray(canonical.emphases) || canonical.emphases.length < 2) {
    return actual === canonical.emphasis;
  }
  const want = [...canonical.emphases].sort().join("|");
  const got = String(actual).split("|").sort().join("|");
  return want === got;
}
```

- [ ] **Step 4: Aceptar el índice en el regex de `iconButton`**

Mismo archivo, el `iconRe` de `extractPanelCalls`:

```js
    const iconRe = /iconButton\(\s*"([^"]*)"\s*,\s*"([A-Za-z][A-Za-z0-9]*)"\s*,\s*"([^"]*)"\s*(?:,\s*[A-Za-z_$][\w$]*\s*)?\)/g;
```

- [ ] **Step 5: Correr el checker y confirmar que falla por el motivo correcto**

```bash
node scripts/check-client-product-surface.mjs
```

Esperado: FALLA nombrando `openDraft` (el canónico lo quiere icon y `panelHtml.ts` lo dibuja con label) y/o el emphasis de `startFromDraft`. Si falla por un error de sintaxis del propio script, arreglarlo antes de seguir.

- [ ] **Step 6: Actualizar el test de contrato de JetBrains**

En `PanelLayoutContractTest.kt`, reemplazar el test `draft rows carry the four canonical controls...` por:

```kotlin
    @Test
    fun `draft rows carry the four canonical controls, with their labels and emphasis`() {
        val yaml = loadCanonical()
        @Suppress("UNCHECKED_CAST")
        val canonical = yaml["draft_controls"] as? Map<String, Any?>
            ?: error("canonical missing draft_controls")
        assertEquals(
            setOf("openDraft", "copyDraftPrompt", "startFromDraft", "discardDraft"),
            canonical.keys,
        )

        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertEquals(3, rows.size)

        // El orden es fijo en las tres filas: mover el objetivo del click segun
        // el progreso seria hostil. Lo que se mueve es el enfasis.
        assertEquals(
            listOf("copyDraftPrompt", "startFromDraft", "openDraft", "discardDraft"),
            rows[0].controls.map { it.id.wire },
        )
        // La segunda fila no ofrece startFromDraft: su bloque de instrucciones
        // se borro a mano y la CLI reporta unknown, asi que los flags no se
        // pueden replicar y adivinarlos fallaria por deriva siempre.
        assertEquals(
            listOf("copyDraftPrompt", "openDraft", "discardDraft"),
            rows[1].controls.map { it.id.wire },
        )

        for (control in rows[0].controls) {
            @Suppress("UNCHECKED_CAST")
            val spec = canonical[control.id.wire] as Map<String, Any?>
            assertEquals(spec["label"], control.label, "label of ${control.id.wire}")
            // rows[0] es 3/9: incompleto, asi que rige emphasis_unfilled cuando existe.
            val want = spec["emphasis_unfilled"] ?: spec["emphasis"]
            assertEquals(want, control.emphasis.id, "emphasis of ${control.id.wire}")
            assertEquals(
                spec["confirms"] as? Boolean ?: false,
                requiresConfirmation(control.id),
                "confirms of ${control.id.wire}",
            )
            assertEquals(
                spec["separated"] as? Boolean ?: false,
                control.separated,
                "separated of ${control.id.wire}",
            )
            // Cada control lleva el indice de SU fila: una accion sobre una
            // fila no puede tocar las demas.
            assertEquals(0, control.index, "index of ${control.id.wire}")
        }
        assertTrue(rows[1].controls.all { it.index == 1 }, "second row carries index 1")

        // Y la tercera fila esta completa (1/1): ahi rige `emphasis` a secas.
        for (control in rows[2].controls) {
            @Suppress("UNCHECKED_CAST")
            val spec = canonical[control.id.wire] as Map<String, Any?>
            assertEquals(spec["emphasis"], control.emphasis.id, "emphasis of ${control.id.wire} (filled)")
        }
    }
```

- [ ] **Step 7: Actualizar el test de contrato de Visual Studio**

En `PanelLayoutContractTests.cs`, reemplazar `DraftControlSpecs()` por una versión que lea las claves nuevas:

```csharp
    private sealed record DraftSpec(
        string? Label, string? AccessibleName, string Emphasis, string? EmphasisUnfilled,
        bool Confirms, bool Separated);

    private static Dictionary<string, DraftSpec> DraftControlSpecs()
    {
        var root = (YamlMappingNode)LoadCanonical().Documents[0].RootNode;
        var map = (YamlMappingNode)root.Children[new YamlScalarNode("draft_controls")];
        var specs = new Dictionary<string, DraftSpec>(StringComparer.Ordinal);
        foreach (var pair in map.Children)
        {
            var id = ((YamlScalarNode)pair.Key).Value!;
            var node = (YamlMappingNode)pair.Value;
            string? Scalar(string key) =>
                node.Children.TryGetValue(new YamlScalarNode(key), out var v)
                    ? ((YamlScalarNode)v).Value
                    : null;
            var label = Scalar("label");
            specs[id] = new DraftSpec(
                label == "null" ? null : label,
                Scalar("accessible_name"),
                Scalar("emphasis")!,
                Scalar("emphasis_unfilled"),
                Scalar("confirms") == "true",
                Scalar("separated") == "true");
        }
        return specs;
    }
```

Y el test `Draft_rows_carry_the_four_canonical_controls` por:

```csharp
    [Fact]
    public void Draft_rows_carry_the_four_canonical_controls()
    {
        var canonical = DraftControlSpecs();
        Assert.Equal(
            new[] { "copyDraftPrompt", "discardDraft", "openDraft", "startFromDraft" },
            canonical.Keys.OrderBy(k => k, StringComparer.Ordinal).ToArray());

        var rows = layoutDraftRows();
        Assert.Equal(3, rows.Count);

        Assert.Equal(
            new[] { "copyDraftPrompt", "startFromDraft", "openDraft", "discardDraft" },
            rows[0].Controls.Select(c => c.Id.Wire()).ToArray());
        Assert.Equal(
            new[] { "copyDraftPrompt", "openDraft", "discardDraft" },
            rows[1].Controls.Select(c => c.Id.Wire()).ToArray());

        foreach (var control in rows[0].Controls)
        {
            var spec = canonical[control.Id.Wire()];
            Assert.Equal(spec.Label, control.Label);
            // rows[0] es 3/9: incompleto, rige EmphasisUnfilled cuando existe.
            Assert.Equal(spec.EmphasisUnfilled ?? spec.Emphasis, control.Emphasis.Id());
            Assert.Equal(spec.Confirms, PanelLayoutBuilder.RequiresConfirmation(control.Id));
            Assert.Equal(spec.Separated, control.Separated);
            Assert.Equal(0, control.Index);
        }
        Assert.All(rows[1].Controls, c => Assert.Equal(1, c.Index));

        // La tercera fila esta completa (1/1): rige Emphasis a secas.
        foreach (var control in rows[2].Controls)
        {
            Assert.Equal(canonical[control.Id.Wire()].Emphasis, control.Emphasis.Id());
        }
    }
```

- [ ] **Step 8: Commit**

```bash
git add contracts/client-product-surface.yaml scripts/check-client-product-surface.mjs jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutContractTest.kt visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutContractTests.cs
git commit -m "contract: enfasis condicional y control separado en la fila del borrador"
```

---

## Task 2: VS Code

**Files:**
- Modify: `vscode-extension/src/views/panelHtml.ts` (CSS `.rev-actions button.sep`, `iconButton`, `renderDraft`)
- Modify: `vscode-extension/preview/fixtures.ts:407-418`
- Test: `vscode-extension/test/unit/panelHtml.spec.ts`

**Interfaces:**
- Consumes: `PanelDraft` de `panelModel.ts` (`branch`, `path`, `annotated`, `total`, `startable`) — sin cambios.
- Produces: `iconButton(iconName, message, label, index)` — el cuarto parámetro es opcional y se pasa tal cual a `button()`.

- [ ] **Step 1: Escribir los tests que fallan**

En `vscode-extension/test/unit/panelHtml.spec.ts`, agregar al final del `describe("panelHtml", ...)`:

```typescript
    it("el enfasis de la fila del borrador sigue al progreso, con el orden fijo", () => {
        // Mientras falten entradas el paso siguiente es llenar el borrador;
        // recien con el orden completo lo es arrancar la review. El ORDEN no
        // se mueve: reordenar los botones bajo el cursor es hostil.
        assert.ok(
            /const filled = draft\.annotated >= draft\.total/.test(html),
            "el progreso decide el enfasis"
        );
        assert.ok(
            /button\("Copy for agent", "copyDraftPrompt", filled \? null : "primary", null, index\)/.test(html),
            "Copy for agent es el primary mientras el borrador este incompleto"
        );
        assert.ok(
            /button\("Validate and start", "startFromDraft", filled \? "primary" : null, null, index\)/.test(html),
            "Validate and start toma el primary recien con el orden completo"
        );
    });

    it("Validate and start nunca se deshabilita por progreso, solo por busy", () => {
        // El conteo sale del disco y el revisor puede tener el borrador abierto
        // con cambios sin guardar: saveOpenDraft guarda antes de validar, asi
        // que grisarlo mentiria justo al terminar de escribir.
        const draftFn = html.slice(html.indexOf("function renderDraft("), html.indexOf("function renderDrafts("));
        assert.ok(draftFn.includes("go.disabled = model.busy;"), "solo busy");
        assert.ok(
            !/go\.disabled = [^;]*(annotated|total|filled)/.test(draftFn),
            "el progreso no puede deshabilitar el control"
        );
    });

    it("Open es un icono con nombre accesible y el indice de su fila", () => {
        // El borrador vive fuera del arbol versionado y este control es la
        // unica superficie que lo abre: baja de peso, no desaparece.
        assert.ok(
            /iconButton\("file", "openDraft", "Open the reading order", index\)/.test(html),
            "icono file, con label accesible e indice"
        );
        assert.ok(
            /function iconButton\(iconName, message, label, index\)/.test(html),
            "el helper acepta el indice de la fila"
        );
    });

    it("Discard es el ultimo de la fila y no comparte vecindad con el primary", () => {
        const draftFn = html.slice(html.indexOf("function renderDraft("), html.indexOf("function renderDrafts("));
        assert.ok(
            /button\("Discard", "discardDraft", "sep", null, index\)/.test(draftFn),
            "el destructivo lleva la clase que lo separa"
        );
        assert.ok(
            draftFn.lastIndexOf("discardDraft") > draftFn.lastIndexOf("startFromDraft"),
            "va despues del control de compromiso"
        );
        assert.ok(
            /\.rev-actions button\.sep \{ margin-left: [^}]+\}/.test(html),
            "un hueco mayor que el gap entre controles"
        );
    });
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

```bash
cd vscode-extension && npm run test:unit
```

Esperado: los cuatro `it` nuevos FALLAN (`renderDraft` todavía dibuja la fila vieja).

- [ ] **Step 3: Agregar la regla CSS del control separado**

En `panelHtml.ts`, después del bloque `.rev-actions button { ... }`:

```css
  /* El unico control irreversible de la fila no comparte vecindad con el de
     compromiso: un hueco mayor que el gap rompe la adyacencia sin sacarlo de
     su fila. El canonico lo marca `separated`. */
  .rev-actions button.sep { margin-left: .8em; }
```

- [ ] **Step 4: Dar índice a `iconButton`**

```js
  function iconButton(iconName, message, label, index) {
    const node = button(null, message, null, iconName, index);
    node.setAttribute("aria-label", label);
    node.title = label;
    return node;
  }
```

- [ ] **Step 5: Reescribir el cuerpo de `renderDraft`**

Reemplazar desde `const actions = el("div", "rev-actions");` hasta antes de `box.appendChild(actions);` por:

```js
    const actions = el("div", "rev-actions");
    // Un solo control enfatico por fila, y el progreso decide cual: mientras
    // falten entradas el paso siguiente es llenar el borrador, y recien con el
    // orden completo lo es arrancar la review. El ORDEN es fijo — mover el
    // objetivo del click segun el estado corre el boton bajo el cursor.
    const filled = draft.annotated >= draft.total;

    const copy = button("Copy for agent", "copyDraftPrompt", filled ? null : "primary", null, index);
    copy.title = "Copy an instruction naming this file";
    actions.appendChild(copy);

    if (draft.startable) {
      // Nunca disabled por progreso: el conteo sale del disco y el borrador
      // puede estar abierto con cambios sin guardar (saveOpenDraft los guarda
      // antes de validar), asi que grisarlo mentiria al terminar de escribir.
      const go = button("Validate and start", "startFromDraft", filled ? "primary" : null, null, index);
      go.disabled = model.busy;
      go.title = "git review walkthrough draft --build, then start";
      actions.appendChild(go);
    }

    // Icono: el archivo vive en el gitdir, fuera del arbol versionado, y este
    // es el unico control de toda la extension que lo abre. Su etiqueta era la
    // que forzaba el wrap de la fila; la accion no sobra.
    const open = iconButton("file", "openDraft", "Open the reading order", index);
    open.title = "Open the reading order for editing";
    actions.appendChild(open);

    const discard = button("Discard", "discardDraft", "sep", null, index);
    discard.disabled = model.busy;
    discard.title = "git review forget --draft (with confirmation)";
    actions.appendChild(discard);
```

Actualizar también el comentario de arriba de la función: donde dice «los cuatro controles sobre ESA fila», agregar que el énfasis sigue al progreso y el orden no.

- [ ] **Step 6: Agregar la fila completa a la fixture del preview**

En `vscode-extension/preview/fixtures.ts`, en el estado `no-review-drafts`, agregar una tercera línea `draft` después de la de `feature/pagos`:

```typescript
                ["draft", "feature/legacy", "/repo/.git/review-walkthrough/feature/legacy.md", "1", "1", "remote", "full"],
```

y ampliar el comentario de arriba: la tercera fila está completa (`1/1`), que es donde el primary pasa a *Validate and start*.

- [ ] **Step 7: Correr los tests unitarios y el checker**

```bash
cd vscode-extension && npm run test:unit
```

Esperado: PASS, incluidos los cuatro nuevos.

```bash
node scripts/check-client-product-surface.mjs
```

Esperado: PASS (desde la raíz del repo).

- [ ] **Step 8: Mirar el panel**

```bash
cd vscode-extension && npm run preview
```

Abrir la URL `file://` que imprime y revisar el pane `no-review-drafts`: tres filas, la de `0/5` con *Copy for agent* en azul, la de `1/1` con *Validate and start* en azul, el icono de archivo y *Discard* separado al final.

- [ ] **Step 9: Commit**

```bash
git add vscode-extension/src/views/panelHtml.ts vscode-extension/preview/fixtures.ts vscode-extension/test/unit/panelHtml.spec.ts
git commit -m "feat(vscode): el enfasis de la fila del borrador sigue al progreso"
```

---

## Task 3: JetBrains

**Files:**
- Modify: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt` (`Control`, `ctrl`, `draftRows`)
- Modify: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/PanelRenderer.kt` (`renderControl`, `renderDrafts`)
- Modify: `jetbrains-plugin/fixtures/com/ezevillo/gitreview/fixtures/PanelFixtures.kt:101-115`
- Test: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutContractTest.kt`

**Interfaces:**
- Consumes: `Emphasis.ICON`, `Control(label = null, accessibleName = ...)` y su invariante, ya existentes.
- Produces: `Control.separated: Boolean` (default `false`) y el parámetro homónimo de `ctrl(...)`.

Shell: en Git Bash usar `./gradlew`; en PowerShell `.\gradlew.bat`. Todos los comandos van desde `jetbrains-plugin/`.

- [ ] **Step 1: Escribir los tests que fallan**

En `PanelLayoutContractTest.kt`, agregar después del test de contrato actualizado en la Task 1:

```kotlin
    @Test
    fun `the emphasis follows the progress and the order never moves`() {
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows

        // 3/9: falta llenarlo, asi que el paso siguiente es Copy for agent.
        val incomplete = rows[0].controls.associateBy { it.id }
        assertEquals(Emphasis.PRIMARY, incomplete[ControlId.COPY_DRAFT_PROMPT]?.emphasis)
        assertEquals(Emphasis.SECONDARY, incomplete[ControlId.START_FROM_DRAFT]?.emphasis)

        // 1/1: el orden esta escrito, el paso siguiente es arrancar la review.
        val filled = rows[2].controls.associateBy { it.id }
        assertEquals(Emphasis.SECONDARY, filled[ControlId.COPY_DRAFT_PROMPT]?.emphasis)
        assertEquals(Emphasis.PRIMARY, filled[ControlId.START_FROM_DRAFT]?.emphasis)

        // Y el orden es el mismo en las dos.
        assertEquals(
            rows[0].controls.map { it.id },
            rows[2].controls.map { it.id },
            "el objetivo del click no se mueve con el progreso",
        )
    }

    @Test
    fun `validate and start is never disabled by progress, only by busy`() {
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        // 3/9 y no busy: habilitado. El conteo sale del disco y el borrador
        // puede estar abierto con cambios sin guardar.
        assertTrue(rows[0].controls.first { it.id == ControlId.START_FROM_DRAFT }.enabled)

        val busy = (panelLayout(PanelFixtures.noReviewDraftsBusy()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertTrue(!busy[0].controls.first { it.id == ControlId.START_FROM_DRAFT }.enabled)
    }

    @Test
    fun `open draft is an icon control with a name to read out`() {
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        val open = rows[0].controls.first { it.id == ControlId.OPEN_DRAFT }
        assertEquals(null, open.label)
        assertEquals(Emphasis.ICON, open.emphasis)
        assertEquals("Open the reading order", open.accessibleName)
        assertEquals(0, open.index)
    }

    @Test
    fun `only the irreversible control is separated`() {
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertEquals(
            listOf(ControlId.DISCARD_DRAFT),
            rows[0].controls.filter { it.separated }.map { it.id },
        )
        assertEquals(ControlId.DISCARD_DRAFT, rows[0].controls.last().id)
    }
```

- [ ] **Step 2: Agregar la fixture busy y la fila completa**

En `PanelFixtures.kt`, `noReviewDrafts()` queda:

```kotlin
    fun noReviewDrafts(busy: Boolean = false): PanelModel {
        val cfg = """
            draft	feature/telemetry	/repo/.git/review-walkthrough/feature/telemetry.md	3	9	local	delta
            draft	feature/pagos	/repo/.git/review-walkthrough/feature/pagos.md	0	5	unknown	unknown
            draft	feature/legacy	/repo/.git/review-walkthrough/feature/legacy.md	1	1	remote	full
        """.trimIndent()
        return buildPanelModel(
            ReviewState(
                situation = Situation.NO_REVIEW,
                config = EffectiveConfig(base = "main", remote = "origin"),
                branches = parseListPorcelain("branch	review-saved/feature	1	0	0	walk	2	5"),
                drafts = parseConfigPorcelain(cfg).drafts,
            ),
            PanelInputs(busy = busy),
        )
    }

    /** El mismo estado con una mutacion en curso: lo unico que deshabilita la fila. */
    fun noReviewDraftsBusy(): PanelModel = noReviewDrafts(busy = true)
```

Los separadores entre campos son TABs literales — después de editar, confirmar con `grep -P 'feature/legacy\t' jetbrains-plugin/fixtures/com/ezevillo/gitreview/fixtures/PanelFixtures.kt` que sobrevivieron.

- [ ] **Step 3: Correr los tests y verificar que fallan**

```bash
./gradlew test --tests '*PanelLayoutContractTest*'
```

Esperado: FALLA — `separated` no existe todavía en `Control` (error de compilación del test).

- [ ] **Step 4: Agregar `separated` al dominio**

En `PanelLayout.kt`, en `data class Control`, después de `supportLinkId`:

```kotlin
    /**
     * Un hueco mayor que el gap entre controles, antes de este. Lo lleva el
     * unico control irreversible de una fila para que no comparta vecindad con
     * el de compromiso; el canonico lo declara con `separated: true`.
     */
    val separated: Boolean = false,
```

Y `ctrl(...)` gana `separated: Boolean = false` como último parámetro, pasándolo al `Control(...)`.

- [ ] **Step 5: Reescribir `draftRows`**

Reemplazar el cuerpo del `mapIndexed` por:

```kotlin
    val rows = model.drafts.mapIndexed { index, d ->
        // Un solo control enfatico por fila, y el progreso decide cual: con
        // entradas sin llenar el paso siguiente es escribir el orden, y recien
        // con el completo lo es arrancar la review. El ORDEN es fijo: mover el
        // objetivo del click segun el estado lo corre bajo el cursor.
        val filled = d.annotated >= d.total
        val controls = ArrayList<Control>()
        controls.add(
            ctrl(
                ControlId.COPY_DRAFT_PROMPT,
                "Copy for agent",
                if (filled) Emphasis.SECONDARY else Emphasis.PRIMARY,
                enabled = true,
                tooltip = "Copy an instruction naming this file",
                index = index,
            ),
        )
        // Absent when the CLI does not know the origin and range the draft was
        // generated with: invoking with the defaults would fail with a drift
        // error every time, and one control fewer beats one that guesses.
        if (d.startable) {
            controls.add(
                ctrl(
                    ControlId.START_FROM_DRAFT,
                    "Validate and start",
                    if (filled) Emphasis.PRIMARY else Emphasis.SECONDARY,
                    // Nunca deshabilitado por el progreso: el conteo sale del
                    // disco y el borrador puede estar abierto con cambios sin
                    // guardar, que el cliente guarda antes de validar.
                    enabled = enabled,
                    tooltip = "git review walkthrough draft --build, then start",
                    index = index,
                ),
            )
        }
        // Icono: el borrador vive fuera del arbol versionado y este control es
        // la unica superficie que lo abre, pero su etiqueta forzaba el wrap.
        controls.add(
            ctrl(
                ControlId.OPEN_DRAFT,
                null,
                Emphasis.ICON,
                enabled = true,
                accessibleName = "Open the reading order",
                tooltip = "Open the reading order for editing",
                index = index,
            ),
        )
        controls.add(
            ctrl(
                ControlId.DISCARD_DRAFT,
                "Discard",
                Emphasis.SECONDARY,
                enabled = enabled,
                tooltip = "git review forget --draft (with confirmation)",
                index = index,
                separated = true,
            ),
        )
        DraftRow(name = d.branch, meta = "${d.annotated}/${d.total}", controls = controls)
    }
```

- [ ] **Step 6: Correr los tests del dominio**

```bash
./gradlew test
```

Esperado: PASS, incluidos los cuatro nuevos y el de contrato de la Task 1.

- [ ] **Step 7: Dibujar el icono y el hueco**

En `PanelRenderer.kt`, en el `when (c.id)` del branch `Emphasis.ICON`, agregar antes del `else`:

```kotlin
                    ControlId.OPEN_DRAFT -> chrome.iconFile()
```

Y en `renderDrafts`, el bucle de controles:

```kotlin
            for (c in r.controls) {
                // El unico irreversible de la fila no toca al de compromiso.
                if (c.separated) actions.add(Box.createHorizontalStrut(12))
                actions.add(renderControl(c))
            }
```

- [ ] **Step 8: Mirar el panel**

```bash
./gradlew runPanelPreview
```

Revisar la situación `no-review drafts`: tres filas, el primary cambiando de mano entre la de `0/5` y la de `1/1`, el icono de archivo y el hueco antes de *Discard*.

- [ ] **Step 9: Commit**

```bash
git add jetbrains-plugin/
git commit -m "feat(jetbrains): el enfasis de la fila del borrador sigue al progreso"
```

---

## Task 4: Visual Studio

**Files:**
- Modify: `visualstudio-extension/src/GitReview.Domain/PanelLayout.cs` (`Control`, `Ctrl`, `DraftRows`)
- Modify: `visualstudio-extension/src/GitReview.VS/ToolWindows/PanelView.cs` (`RenderControl`, `RenderDrafts`)
- Modify: `visualstudio-extension/fixtures/PanelFixtures.cs:66-80`
- Test: `visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutContractTests.cs`

**Interfaces:**
- Consumes: `Emphasis.Icon` y el invariante del record `Control` (label nulo ⟹ Icon ⟹ accessibleName no vacío).
- Produces: `Control.Separated` (bool, default `false`) y el parámetro `separated` de `Ctrl(...)`.

Todos los comandos desde `visualstudio-extension/`.

- [ ] **Step 1: Escribir los tests que fallan**

En `PanelLayoutContractTests.cs`, agregar:

```csharp
    [Fact]
    public void The_emphasis_follows_the_progress_and_the_order_never_moves()
    {
        var rows = layoutDraftRows();

        // 3/9: falta llenarlo, el paso siguiente es Copy for agent.
        var incomplete = rows[0].Controls.ToDictionary(c => c.Id);
        Assert.Equal(Emphasis.Primary, incomplete[ControlId.CopyDraftPrompt].Emphasis);
        Assert.Equal(Emphasis.Secondary, incomplete[ControlId.StartFromDraft].Emphasis);

        // 1/1: el orden esta escrito, el paso siguiente es arrancar la review.
        var filled = rows[2].Controls.ToDictionary(c => c.Id);
        Assert.Equal(Emphasis.Secondary, filled[ControlId.CopyDraftPrompt].Emphasis);
        Assert.Equal(Emphasis.Primary, filled[ControlId.StartFromDraft].Emphasis);

        Assert.Equal(
            rows[0].Controls.Select(c => c.Id).ToArray(),
            rows[2].Controls.Select(c => c.Id).ToArray());
    }

    [Fact]
    public void Validate_and_start_is_never_disabled_by_progress_only_by_busy()
    {
        var rows = layoutDraftRows();
        Assert.True(rows[0].Controls.First(c => c.Id == ControlId.StartFromDraft).Enabled);

        var busy = PanelLayoutBuilder.PanelLayout(PanelFixtures.NoReviewDraftsBusy())
            .Blocks.OfType<Block.DraftRows>().Single().Rows;
        Assert.False(busy[0].Controls.First(c => c.Id == ControlId.StartFromDraft).Enabled);
    }

    [Fact]
    public void Open_draft_is_an_icon_control_with_a_name_to_read_out()
    {
        var open = layoutDraftRows()[0].Controls.First(c => c.Id == ControlId.OpenDraft);
        Assert.Null(open.Label);
        Assert.Equal(Emphasis.Icon, open.Emphasis);
        Assert.Equal("Open the reading order", open.AccessibleName);
        Assert.Equal(0, open.Index);
    }

    [Fact]
    public void Only_the_irreversible_control_is_separated()
    {
        var controls = layoutDraftRows()[0].Controls;
        Assert.Equal(
            new[] { ControlId.DiscardDraft },
            controls.Where(c => c.Separated).Select(c => c.Id).ToArray());
        Assert.Equal(ControlId.DiscardDraft, controls[controls.Count - 1].Id);
    }
```

- [ ] **Step 2: Agregar la fixture busy y la fila completa**

En `fixtures/PanelFixtures.cs`:

```csharp
    public static PanelModel NoReviewDrafts(bool busy = false)
    {
        var cfg =
            "draft\tfeature/telemetry\t/repo/.git/review-walkthrough/feature/telemetry.md\t3\t9\tlocal\tdelta\n" +
            "draft\tfeature/pagos\t/repo/.git/review-walkthrough/feature/pagos.md\t0\t5\tunknown\tunknown\n" +
            "draft\tfeature/legacy\t/repo/.git/review-walkthrough/feature/legacy.md\t1\t1\tremote\tfull\n";
```

El resto del cuerpo queda igual, pasando `busy` a `PanelInputs`. Y al lado:

```csharp
    /// <summary>El mismo estado con una mutacion en curso: lo unico que deshabilita la fila.</summary>
    public static PanelModel NoReviewDraftsBusy() => NoReviewDrafts(busy: true);
```

- [ ] **Step 3: Correr los tests y verificar que fallan**

```bash
dotnet test tests/GitReview.Domain.Tests
```

Esperado: FALLA — `Control.Separated` no existe (error de compilación).

- [ ] **Step 4: Agregar `Separated` al dominio**

En `PanelLayout.cs`, el constructor de `Control` gana `bool separated = false` como último parámetro, la asignación `Separated = separated;` y la propiedad:

```csharp
    /// <summary>
    /// Un hueco mayor que el gap entre controles, antes de este. Lo lleva el
    /// unico control irreversible de una fila para que no comparta vecindad con
    /// el de compromiso; el canonico lo declara con <c>separated: true</c>.
    /// </summary>
    public bool Separated { get; init; }
```

`Ctrl(...)` gana el mismo parámetro opcional y lo pasa.

- [ ] **Step 5: Reescribir `DraftRows`**

```csharp
        var rows = model.DraftsList.Select((d, index) =>
        {
            // Un solo control enfatico por fila, y el progreso decide cual. El
            // ORDEN es fijo: mover el objetivo del click segun el estado lo
            // corre bajo el cursor.
            var filled = d.Annotated >= d.Total;
            var controls = new List<Control>
            {
                Ctrl(
                    ControlId.CopyDraftPrompt, "Copy for agent",
                    filled ? Emphasis.Secondary : Emphasis.Primary,
                    enabled: true, tooltip: "Copy an instruction naming this file", index: index),
            };
            // Absent when the CLI does not know the origin and range the draft
            // was generated with: invoking with the defaults would fail with a
            // drift error every time, and one control fewer beats one that guesses.
            if (d.Startable)
            {
                // Nunca deshabilitado por el progreso: el conteo sale del disco
                // y el borrador puede estar abierto con cambios sin guardar.
                controls.Add(Ctrl(
                    ControlId.StartFromDraft, "Validate and start",
                    filled ? Emphasis.Primary : Emphasis.Secondary,
                    enabled: enabled,
                    tooltip: "git review walkthrough draft --build, then start",
                    index: index));
            }
            // Icono: el borrador vive fuera del arbol versionado y este control
            // es la unica superficie que lo abre, pero su etiqueta forzaba el wrap.
            controls.Add(Ctrl(
                ControlId.OpenDraft, null, Emphasis.Icon,
                enabled: true,
                accessibleName: "Open the reading order",
                tooltip: "Open the reading order for editing",
                index: index));
            controls.Add(Ctrl(
                ControlId.DiscardDraft, "Discard", Emphasis.Secondary,
                enabled: enabled,
                tooltip: "git review forget --draft (with confirmation)",
                index: index,
                separated: true));
            return new DraftRow(d.Branch, $"{d.Annotated}/{d.Total}", controls);
        }).ToList();
```

- [ ] **Step 6: Correr las dos suites**

```bash
dotnet test GitReview.sln
```

Esperado: PASS.

- [ ] **Step 7: Dibujar el glifo y el hueco**

En `PanelView.cs`, `RenderControl`, el branch de `Emphasis.Icon`:

```csharp
            // Este host dibuja los controles de icono con glifos de texto (no
            // hay Image Catalog fuera del VSIX): BMP, para que ninguna fuente
            // del tema los deje en tofu.
            var icon = c.Id == ControlId.Prev ? "◀"
                : c.Id == ControlId.OpenDraft ? "▤"
                : "▶";
```

Y `RenderDrafts`, el bucle de controles:

```csharp
            foreach (var c in r.Controls)
            {
                // El unico irreversible de la fila no toca al de compromiso.
                if (c.Separated) actions.Children.Add(new Border { Width = 12 });
                actions.Children.Add(RenderControl(c));
                actions.Children.Add(new Border { Width = 4 });
            }
```

- [ ] **Step 8: Verificar el render y mirarlo**

```bash
dotnet run --project src/GitReview.VS -- --verify
```

Esperado: PASS (ninguna comprobación de chrome cambia).

```bash
dotnet run --project src/GitReview.VS -- --preview
```

Revisar la situación `no-review drafts`.

- [ ] **Step 9: Commit**

```bash
git add visualstudio-extension/
git commit -m "feat(visualstudio): el enfasis de la fila del borrador sigue al progreso"
```

---

## Task 5: La copy de producto y la verificación final

**Files:**
- Modify: `vscode-extension/README.md:38-48` (los bullets) y `:117` (la fila de la tabla)
- Modify: `vscode-extension/CHANGELOG.md`, `jetbrains-plugin/CHANGELOG.md`, `visualstudio-extension/CHANGELOG.md`

- [ ] **Step 1: Actualizar los bullets del README de la extensión**

Reemplazar «and four buttons on its row» y la lista de cuatro por:

```markdown
started**, with how far along it is (`3/9`, counted by the CLI) and the controls
that act on that row. Which one is highlighted follows the progress: while
entries are still unfilled the next step is writing them, and only once the
order is complete is it starting the review.

- **Copy for agent** — puts a one-line instruction naming that file on the
  clipboard, for whatever you want to hand it to. Copying is copying: no
  service is contacted and no assistant is invoked. Highlighted while the
  order is unfinished.
- **Validate and start** — validates it (on the CLI, so a rejection tells you
  exactly what to fix, in the CLI's own words) and, when it passes, starts the
  review on your order. Highlighted once every entry is written. It never
  greys out because of the count: the draft can be open with unsaved edits,
  and those are saved before it validates.
- **the file icon** — opens the reading order for editing, at the path the CLI
  reported. The draft lives outside the working tree, so this is the one way
  to it from the editor.
- **Discard** — deletes it, after a confirmation that names the command. It
  sits apart from the rest: it is the only one you cannot undo.
```

- [ ] **Step 2: Actualizar la fila de la tabla de acciones del README**

```markdown
| **Copy for agent / Validate and start / Open / Discard** | A row of *Reading orders you started*, in the empty state | `git review walkthrough draft --build`, `git review start`, `git review forget --draft` |
```

- [ ] **Step 3: Escribir la entrada de CHANGELOG de los tres clientes**

Bajo `## [Unreleased]` en los tres (creando la sección si no está), con la voz de cada archivo:

```markdown
### Changed

- The draft row now highlights the step that is actually next: *Copy for agent*
  while the reading order is unfinished, *Validate and start* once it is
  complete. The order of the controls never changes. *Open* became the file
  icon and *Discard*, the only irreversible one, sits apart from the rest.
```

- [ ] **Step 4: Verificación completa**

Desde la raíz:

```bash
node scripts/check-client-product-surface.mjs
```

```bash
cd vscode-extension && npm run test:unit
```

```bash
./vscode-extension/test/run-docker.sh draft-panel
```

```bash
cd jetbrains-plugin && ./gradlew test
```

```bash
cd visualstudio-extension && dotnet test GitReview.sln
```

Los cinco tienen que dar verde. Si `draft-panel` falla, mirar si el test afirma el orden de los controles del panel — es el único lugar donde el orden viejo podría estar hardcodeado fuera de los tests de contrato.

- [ ] **Step 5: Commit**

```bash
git add vscode-extension/README.md vscode-extension/CHANGELOG.md jetbrains-plugin/CHANGELOG.md visualstudio-extension/CHANGELOG.md
git commit -m "docs: la jerarquia nueva de la fila del borrador en los tres clientes"
```
