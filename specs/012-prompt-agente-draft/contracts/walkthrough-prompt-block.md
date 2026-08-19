# Contrato: el bloque de instrucciones del esqueleto

**Feature**: `012-prompt-agente-draft`

Define la única pieza nueva del formato de walkthrough, su contenido, y las tres
propiedades que la hacen sobrevivir sin verse nunca. Rige para los **dos** lados:
`git review walkthrough init` (el sidecar commiteado del autor) y
`git review walkthrough draft` (el borrador del revisor).

## La pieza

Un comentario HTML en el preámbulo, abierto con un centinela fijo:

```text
<!-- git-review-range: ...
     ...
-->
```

| Propiedad | Regla |
| --- | --- |
| Reconocimiento | La línea de apertura empieza **exactamente** con `<!-- git-review-range:` (comparación de prefijo, no regex). |
| Cantidad | Cero o uno. Si hay más de uno, se conserva el primero y los demás se tratan como andamiaje. |
| Región | El preámbulo (antes del primer `## N. ` / `## ?. `). Fuera de ahí no se reconoce. |
| Al reescribir | **Se regenera** desde el rango que la reescritura acaba de validar, entre `# Walkthrough` y el preámbulo. |
| Al leer | **Se descarta.** `walk_preamble` ya filtra todo comentario y no cambia. |
| En la validación | **Neutro.** No participa de ninguna de las ocho reglas. |
| En el PR | Invisible: es un comentario HTML. |

**Regenerar, no arrastrar.** El bloque que sale de una reescritura no es el que
entró: es uno nuevo, emitido por el mismo generador que usan `init` y `draft`,
con el rango que esa misma corrida resolvió para el chequeo de deriva. El
centinela de reconocimiento existe para que un bloque entrante **no se duplique
ni se cuele al preámbulo**, no para copiarlo.

Motivo, en corto (largo en `research.md` § Decisión 4): un bloque arrastrado
sobrevive al cambio del rango y queda diciendo «el rango es X» dentro de un
archivo validado contra Y — la deriva sólo salta si cambió el *conjunto de
paths*, así que commits nuevos sobre los mismos archivos la dejan pasar. Además
regenerar es menos código: no hay que extraer y reinyectar nada.

Esto **refina** la decisión Q1 sin contradecirla: lo que Q1 pidió es que las
instrucciones sobrevivan a la construcción, y sobreviven; lo que se elimina es el
costo que Q1 había aceptado («que las instrucciones envejezcan con el rango»).

### Implementación mínima

- `walk_prompt_block` (nuevo, en `bin/git-review-lib.sh`; stdin: contenido del
  walkthrough): **detecta** el bloque reconocido y lo consume, para que la
  reescritura no lo arrastre al preámbulo ni lo duplique. Un `awk`, sin procesos
  por entrada.
- `walk_emit_prompt_block` (nuevo): **genera** el bloque a partir de `tip`,
  `lower`, la etiqueta, la situación del árbol y los flags de origen/rango.
  Único generador; lo llaman los tres sitios (`init`, `draft`, la reescritura).
- `bin/git-review-verbs/walkthrough`, reescritura canónica: emite
  `walk_emit_prompt_block` justo después del encabezado y antes del preámbulo.
  Con `--check` no se emite nada, porque `--check` no escribe.
- **`walk_preamble` no se toca.** La mitad «filtrar al leer» de FR-013a ya está
  hecha: sus tres llamadores son la reescritura (que ahora suma la llamada
  nueva) y `start`/`compare`, que son los que le muestran el heads-up al
  revisor.

## Contenido

Cuatro secciones, en este orden. Los `<...>` son sustituciones del generador.

### 1. Encabezado y alcance

```text
<!-- git-review-range: what this reading order covers, and how to see it.
     This block is for whoever fills the walkthrough in (usually an agent).
     It is kept when the file is rebuilt, it is never shown to the reviewer,
     and it does not render on the PR. Nothing here is run for you.
```

### 2. El rango, con los dos extremos resueltos

```text
     Range under review, resolved when this skeleton was written:
       tip   <tip-sha>       (<tip-label>)
       base  <lower-oid>     (<lower-kind>)
```

- `<tip-sha>` — SHA completo. Para `draft`, el de
  `refs/remotes/<remote>/<branch>` (o `refs/heads/<branch>` con
  `--local`/`--offline`); para `init`, el de `HEAD`.
- `<tip-label>` — la etiqueta legible que el verbo ya calcula (`$srclabel` para
  `draft`, `HEAD` para `init`).
- `<lower-oid>` — el objeto que devolvió `resolve_lower_bound` / `fold_lower`.
- `<lower-kind>` — `commit` o `tree`. Se decide con
  `git cat-file -t "$lower"`, un solo proceso, sólo al generar el esqueleto.
  Existe para que quien anota entienda por qué las instrucciones son como son.

**Prohibido**: escribir `<lower>..<tip>` o `<lower>...<tip>` en cualquier parte
del bloque. Los dos extremos van **siempre** como dos argumentos separados. Dos
motivos independientes, los dos medidos (`research.md` § Hallazgo 0):

1. `git diff <a>..<b>` con dos SHAs completos y sin `--` muere en **Windows**
   cuando el cwd es profundo (`fatal: failed to stat '<a>..<b>': Filename too
   long`, exit 128): git hace `stat()` del argumento para desambiguarlo como
   pathspec y se pasa de `MAX_PATH`. **No depende del tipo del extremo**: pasa
   igual con dos commits, así que la regla vale también para `init`.
2. Con un `lower` que es tree OID, los comandos de historia mienten en silencio
   (abajo).

**Prohibido también**: `git log`, `git rev-list`, `git shortlog` y
`git range-diff`. Con un `lower` de tipo tree, `git log <lower>..<tip>` imprime
**la historia entera del repositorio con exit 0**, sin una queja — quien anota
cree estar viendo los commits del PR y está viendo todos. Es el único fallo
específico del tree OID y es el peligroso, porque no hay forma de escribir esos
comandos que funcione.

**No prohibido, y conviene saberlo**: `git diff <lower> <tip>` (dos argumentos) y
`git show <rev>:<path>` funcionan con un `lower` de cualquier tipo, en los dos
sistemas operativos. Versiones anteriores de este contrato afirmaban que
`git diff <tree>..<tip>` «sale 0 con salida vacía»; **es falso** —esa medición
comparaba un árbol contra sí mismo— y se corrigió para que nadie afloje la regla
al comprobar que en Linux el comando anda.

### 2b. Con qué flags se generó

Una línea, siempre presente, con los flags de origen y rango normalizados en
orden fijo (`--local` | `--offline`, después `--delta`), o el literal
`(defaults)`:

```text
     Generated with: --local --delta
```

No es decorativa y no es para quien anota: es el **único** lugar donde vive ese
dato. El registro `draft` de `config --porcelain` lo emite como campos, y
*Validate and start* del panel lo replica al invocar `draft --build` y `start`.
Sin esto, un borrador hecho con `--delta` o `--local` cubre un conjunto de paths
distinto del que el panel pediría por defecto, y ese botón falla **siempre** con
error de deriva, sin salida dentro del panel (`research.md` § Decisión 13).

Vive en el bloque y no en una clave de config para que el dato nazca y muera con
el archivo: borrar un borrador a mano está permitido desde 011, y una clave
aparte quedaría huérfana con cada borrado.

Como el bloque se regenera al construir, la línea no puede quedar desfasada: un
`--build` con otros flags o falla por deriva, o reemite el bloque con los reales.

**Con `--delta`**, `<lower-oid>` es el marcador del review anterior y el bloque
lo dice explícitamente, para que un esqueleto incremental no invite a anotar el
PR entero (FR-005):

```text
     This is an incremental range: it covers only what was added since your
     previous review of <branch>, not the whole PR.
```

### 3. La situación del árbol de trabajo

Exactamente una de las tres frases, elegida al generar:

| Caso | Cómo se detecta | Frase |
| --- | --- | --- |
| `init` (autor) | `sub = init` | `You are standing on the PR branch: your working tree has the PR, plus anything you have not committed. This walkthrough covers committed history only.` |
| `draft` desde la base | `sub = draft` y `HEAD` **no** es `review/*` | `You are standing on the base branch: the files listed below exist in your working tree with their PRE-PR content. Reading them there gives you the old code.` |
| `draft` dentro de una review | `sub = draft` y `HEAD` **es** `review/*` | `You are inside an active review: your working tree carries PR content plus the reviewer's own edits, and how much of the PR depends on the review mode.` |

**La detección va por `HEAD`, no por `from_review`.** `from_review` sólo vale 1
cuando el revisor omitió la rama
([walkthrough:220-229](../../../bin/git-review-verbs/walkthrough)): parado dentro
de `review/feature/x` y escribiendo `git review walkthrough draft feature/x`,
vale 0 y el archivo diría la frase equivocada — que es literalmente lo que
SC-002 prohíbe.

**La tercera frase no promete que el árbol tenga el PR completo**, porque en modo
`step` sólo lo tiene hasta el commit del cursor. Nombra la situación y remite a
los comandos, que son correctos en los tres modos.

Y en los tres casos, la regla que cierra la sección (FR-006):

```text
     Write the reading order over the range above, not over what your working
     tree happens to contain. Use the commands below to see the real content.
```

### 4. Los comandos

```text
     For any file <path> listed below:
       the change the PR makes to it
         git diff <lower-oid> <tip-sha> -- <path>
       its content after the PR
         git show <tip-sha>:<path>
       its content before the PR
         git show <lower-oid>:<path>
       every file in the range, again
         git diff --name-only <lower-oid> <tip-sha>
     A file the PR deletes has no "after" content: git show will fail on it,
     and that failure is the answer.
-->
```

`git show <tree-oid>:<path>` funciona: la sintaxis `<rev>:<path>` acepta
cualquier tree-ish (verificado). `git diff <a> <b>` con `<a>` tree y `<b>`
commit también.

## Autor vs revisor: qué difiere

Un solo generador, con los mismos dos pasajes conmutados que el esqueleto ya
conmuta hoy ([walkthrough:459-471](../../../bin/git-review-verbs/walkthrough)):
la frase de situación (sección 3) y el comando de validación que ya se imprime
al pie del andamiaje. Todo lo demás es idéntico, y **es la misma cadena**: dos
copias del texto derivarían y la deriva sería invisible hasta que alguien leyera
la equivocada (FR-007).

Que el bloque se commitee con el sidecar del autor es aceptable porque no se
renderiza en el PR y porque la reescritura lo regenera: cada `build` del autor lo
reemite con el rango de ese momento, así que el sidecar nunca lleva commiteado un
rango que ya no corresponde.

## Invariantes

- **No se ejecuta nada** (FR-008): el bloque describe comandos, el producto no
  los corre ni antes ni después.
- **Ninguna escritura fuera de lo de siempre**: `git status` antes y después de
  `walkthrough draft` sigue siendo idéntico.
- **Idempotencia de la reescritura**: `draft --build` dos veces seguidas produce
  el mismo archivo byte por byte, con un solo bloque. Con el rango quieto,
  regenerar y preservar son indistinguibles desde afuera; la diferencia sólo se
  ve cuando el rango se movió, que es cuando importa.
- **Reanotar no reconstruye nada** (FR-019, SC-014): el archivo instalado ya
  trae el bloque, con los *whys* ya escritos adentro.
- **El bloque nunca queda viejo**: después de cualquier `--build` que haya
  escrito, los extremos del bloque son los que esa corrida validó.

## Tests (bats — `tests/walkthrough-prompt-block.bats`)

Todos con asserts fuertes: status esperado *y* efecto real.

| Caso | Afirma |
| --- | --- |
| El esqueleto de `draft` nombra objetos resolubles | `git cat-file -e` sobre los dos extremos extraídos del archivo, exit 0 |
| El esqueleto **no** contiene `..` entre extremos | `grep` negativo sobre el bloque, en los cuatro orígenes (remoto, `--local`, `--offline`, `--delta`) |
| Base mergeada dentro del PR (lower = tree) | El bloque se genera igual, dice `tree`, y sus comandos devuelven el contenido posterior al PR |
| Seguir el comando devuelve el contenido del PR | `git show <tip>:<path>` del archivo ≠ el del árbol de trabajo, sobre un archivo **modificado** (no agregado) |
| El esqueleto **no** contiene `..` con `lower` **commit** | `grep` negativo, para que la regla no se relaje donde el motivo del tree no aplica |
| El esqueleto no nombra ningún comando de historia | `grep` negativo de `git log`, `rev-list`, `shortlog`, `range-diff` sobre el bloque |
| La regla de cierre está (FR-006) | El bloque contiene la frase que manda anotar sobre el rango y no sobre el árbol |
| `--delta` | El bloque nombra el rango incremental y lo dice; el `lower` es **igual** a `reviewworkflow.<branch>.reviewed` |
| Línea `Generated with:` en los cinco orígenes | `(defaults)`, `--local`, `--offline`, `--delta`, `--local --delta`, en ese orden normalizado |
| Situación desde la base | La frase de base, no la de review |
| Situación dentro de una review, con la rama nombrada explícitamente | La frase de review (el caso que `from_review` erraría) |
| `init` | La frase de autor, y el mismo cuerpo de comandos |
| El bloque sobrevive a `--build` | Presente, una sola vez, después de reescribir |
| El bloque sobrevive a **dos** `--build` | Idéntico byte por byte, sin duplicarse |
| **La reescritura lo regenera** | Con el tip movido (commit nuevo que toca los mismos paths, sin deriva), `--build` deja los extremos **nuevos**, no los viejos |
| Un bloque entrante no se cuela al preámbulo | Un archivo con bloque escrito a mano sale con **un** bloque y sin rastro de él en el heads-up |
| `--check` no escribe | `draft --build --check` deja el archivo byte por byte igual, bloque incluido |
| El bloque no se le muestra al revisor | `git review start` no imprime ninguna línea del bloque; `status --why` tampoco |
| El bloque es neutro para la validación | Un borrador válido sigue validando con y sin bloque; los mensajes de las **ocho** reglas no cambian |
| Borrarlo a mano no invalida nada | `--build` sale 0 y `start` entra en walk igual |
| El heads-up sigue funcionando | Un preámbulo con bloque **y** heads-up imprime sólo el heads-up |
| Un preámbulo con **sólo** el bloque | `start` no imprime preámbulo vacío |
