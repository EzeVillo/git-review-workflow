# Research: El borrador del revisor, escrito por un agente

**Feature**: `012-prompt-agente-draft` | **Fase**: 0 | **Fecha**: 2026-08-19

Decisiones de diseño previas a la implementación. Cada una registra qué se
eligió, por qué, y qué alternativas se descartaron. Las tres primeras salen de
verificar contra el código afirmaciones de la spec: dos la encarecen y una la
abarata.

---

## Hallazgo 0 — La forma de dos argumentos es obligatoria, por dos motivos independientes

**Corrige una medición anterior.** Las fases previas afirmaron, primero, que
`git diff <tree>..<tip>` es «inválido», y después que «no falla: sale exit 0 con
stdout vacío». **Las dos son falsas**, y la segunda salió de un caso de prueba
mal armado (`HEAD^{tree}..HEAD` — el árbol *de* HEAD contra HEAD: el diff está
vacío porque no hay diferencia, no porque la sintaxis mienta). Re-medido con
git 2.52.0 en Linux y en Windows, en repositorios recién creados:

| Comando | Linux | Windows |
| --- | --- | --- |
| `git diff --name-only <tree> <commit>` | 0, lista correcta | 0, lista correcta |
| `git diff --name-only <tree>..<commit>` | 0, lista correcta | **fatal 128** si el cwd es profundo |
| `git diff --name-only <commit>..<commit>` | 0, lista correcta | **fatal 128** si el cwd es profundo |
| `git log --oneline <tree>..<commit>` | **historia entera, exit 0** | **historia entera, exit 0** |

De ahí salen dos motivos **separados**, y conviene no confundirlos porque cubren
casos distintos:

**Motivo 1 — `git log` / `rev-list` con un `lower` que es tree mienten en
silencio.** Es el único fallo específico del tree OID, y es el peligroso:
imprimen la historia completa del repositorio con exit 0, sin una queja. Un
agente al que se le diga «mirá los commits de `<lower>..<tip>`» anota el
repositorio entero creyendo que anota el PR. `resolve_lower_bound` devuelve un
tree OID cuando la base fue mergeada dentro del PR
([git-review-lib.sh:387](../../bin/git-review-lib.sh)), así que el caso es
ordinario, no exótico.

**Motivo 2 — `git diff <a>..<b>` con dos SHAs completos y sin `--` es frágil en
Windows.** Nada que ver con el tree: pasa igual con dos commits. git hace
`stat()` del argumento para desambiguarlo como pathspec, y `cwd + 81 caracteres`
se pasa de `MAX_PATH`, con lo que sale `fatal: failed to stat '<a>..<b>':
Filename too long` y **exit 128**. Desaparece con un cwd corto, con SHAs
abreviados o agregando `--`. Verificado con el control decisivo: mismo comando,
mismo git, cwd de 40 caracteres → funciona; cwd de ~200 → fatal. Este repositorio
trata a Windows como runner de primera clase y no controla dónde clona el
revisor, así que es un fallo real, no teórico.

**Decisión**: el bloque de instrucciones **nunca** contiene `..` ni `...` entre
los dos extremos, y **nunca** nombra `git log`, `git rev-list`, `git shortlog` ni
`git range-diff`. Todo lo que nombre el rango usa la forma de dos argumentos de
`git diff`; todo lo que nombre contenido usa `<rev>:<path>`, que acepta cualquier
tree-ish (`git show <tree>:<path>` verificado).

**Lo que cambia respecto de la versión anterior de este hallazgo**: la regla ya
no es una excepción para el caso tree, es la forma **única** en los dos lados. El
motivo 2 vale también para `init`, donde el `lower` es siempre un commit y la
justificación anterior no aplicaba. Una regla sin caso especial es más barata de
sostener y más difícil de aflojar: un implementador que probara `..` en Linux lo
vería funcionar y, con el fundamento viejo, habría concluido que la prohibición
era exagerada.

**Consecuencia de test**: dos aserciones, no una. (a) Con la base mergeada dentro
del PR —el caso en que `lower` es tree—, ninguna línea del bloque contiene `..`
entre los dos extremos resueltos ni nombra un comando de la lista prohibida.
(b) La misma aserción con `lower` commit, para que la regla no se relaje ahí.
Un test que sólo compruebe «el bloque nombra un SHA» pasa igual con la forma
rota.

**Riesgo asumido, documentado**: el tree OID de `merge-tree --write-tree` **no
está referenciado**, así que un `git gc` agresivo lo puede podar (por defecto
`gc.pruneExpire` lo protege dos semanas). Un borrador viejo entonces da un error
de git ruidoso al intentar ver el cambio, que es el comportamiento que el edge
case de la spec pide (error, no respuesta vacía). No se materializa un commit ni
se crea una ref para evitarlo: `resolve_lower_bound` existe justamente para no
dejar objetos colgando en cada sondeo, y revertir eso por el borrador cambiaría
el coste de `config --porcelain`, que corre en cada refresco del panel.

---

## Hallazgo 1 — «Preservar al escribir» y «filtrar al leer» ya están casi separados (abarata)

La spec (y la nota de `/speckit-clarify`) dice que la prosa previa a la primera
entrada «se filtra de comentarios **dos veces** —al reescribir el archivo y al
mostrársela al revisor— con el mismo filtro», y que FR-013a «obliga a separar
esos dos comportamientos, que hoy son uno».

Verificado: `walk_preamble` tiene **tres** llamadores, no dos, y ya están
repartidos:

| Llamador | Qué hace | Qué necesita esta feature |
| --- | --- | --- |
| [`walkthrough:698`](../../bin/git-review-verbs/walkthrough) | reescritura canónica | **preservar** el bloque |
| [`start:519`](../../bin/git-review-verbs/start) | imprime el heads-up al entrar | filtrar (ya lo hace) |
| [`compare:299`](../../bin/git-review-verbs/compare) | ídem | filtrar (ya lo hace) |

**Decisión**: `walk_preamble` **no se toca**. La mitad «filtrar al leer» de
FR-013a cuesta cero líneas: la función ya descarta todo comentario y sus dos
llamadores de lectura son los únicos que le muestran algo al revisor. Lo único
nuevo es un helper aparte, `walk_prompt_block`, que la reescritura llama
**además** de `walk_preamble` y emite entre el encabezado y el preámbulo.

Esto es más barato y más seguro que la alternativa: separar las dos ramas
*dentro* de `walk_preamble` (con un flag o una variante) crearía una función que
se comporta distinto según el llamador, que es la clase de cosa que este
proyecto ya pagó cara con `walk_is_draft` / `walk_has_draft_file`.

**Alternativa descartada**: guardar el bloque fuera del archivo (una clave de
config, un sidecar). Rompe FR-019 y SC-014 —«el archivo instalado basta por sí
solo»— y agrega un estado que puede desincronizarse con el archivo que sí viaja.

---

## Hallazgo 2 — La situación del árbol se detecta mal si se usa `from_review` (encarece)

FR-004 pide distinguir «generado desde la rama base» de «generado desde adentro
de una review activa». El verbo ya tiene una variable que parece servir,
`from_review` ([walkthrough:220-229](../../bin/git-review-verbs/walkthrough)),
pero **sólo se pone en 1 cuando el revisor omitió la rama**: si está parado
dentro de `review/feature/x` y escribe `git review walkthrough draft
feature/x`, `from_review` vale 0 y el archivo le diría que su árbol no tiene el
PR — cuando sí lo tiene. Es literalmente el desacuerdo que SC-002 prohíbe.

**Decisión**: la situación se decide con una pregunta propia —¿`HEAD` es una
rama `review/*`?— resuelta una vez, antes del parseo de la rama, y usada sólo
para elegir la frase. `from_review` sigue existiendo para lo suyo (derivar el
nombre de la rama), sin mezclarse.

**Segunda corrección al enunciado de la spec**: FR-004 describe el caso de review
activa como «el árbol sí lo tiene, más las ediciones del revisor». Eso es cierto
en `whole` y en `walk`, donde `start` deja el PR entero staged; en `step` el
árbol tiene el PR **sólo hasta el commit del cursor**. Escribir la frase optimista
sería falso en el tercer modo. Resolución: la frase nombra la situación («estás
dentro de una review; tu árbol de trabajo tiene contenido del PR y tus
ediciones») y remite a los comandos, que son la respuesta correcta en los tres
modos y en la base. Es también lo que ya pide FR-006, así que no hay que elegir
entre los dos requisitos: el bloque dice *no te fíes del árbol* siempre, y la
frase de situación sólo explica por qué el árbol se ve como se ve.

---

## Decisión 3 — Qué contiene el bloque, y por qué es un comentario HTML

**Decisión**: un único comentario HTML, en el preámbulo, abierto con un
centinela propio en su primera línea:

```markdown
<!-- git-review-range: what this reading order covers, and how to see it.
     Kept by build; never shown to the reviewer, never rendered on the PR.
     ...
-->
```

Cuatro propiedades, y las cuatro las da esta forma sin maquinaria:

1. **No se renderiza en la plataforma de revisión** (FR-007, SC-015): un
   comentario HTML es invisible en el Markdown que GitHub muestra del sidecar
   commiteado del autor.
2. **No se le muestra al revisor** (FR-013a, SC-015): `walk_preamble` descarta
   todo comentario, y es el único filtro que hay.
3. **No cambia ninguna regla de validación** (FR-013a): las dos reglas que
   miran comentarios están ancladas a `^<!-- why` y `^<!-- heads-up`, y la
   detección de prosa de `walk_preamble` no cuenta comentarios, así que un
   preámbulo que sólo tenga este bloque sigue imprimiéndose vacío.
4. **Se reconoce sin ambigüedad**: el centinela `git-review-range:` distingue
   este bloque del andamiaje del esqueleto —que `build` debe seguir
   descartando— con un `index($0, ...) == 1` en awk. Cero procesos nuevos.

**Contenido** (el contrato lo fija byte a byte):
el rango resuelto (los dos extremos), la relación del árbol de trabajo con el
PR, y los comandos para ver el cambio y el contenido resultante de un archivo.
Todo descriptivo: el producto no ejecuta nada (FR-008).

**Alternativas descartadas**:

- *Un bloque `> ` reservado, como `> key` / `> at:`*: se renderiza como cita en
  GitHub, que es exactamente lo que FR-007 prohíbe para el sidecar del autor.
- *Una sección `## Prompt`*: sería un encabezado visible en el PR, y además
  `walk_preamble` lo imprimiría como parte del heads-up.
- *Regenerarlo en cada `build` a partir del rango del momento*: contradice la
  suposición «el rango se resuelve una vez» y convierte una deriva detectable en
  una foto que se auto-actualiza sin que nadie se entere.

---

## Decisión 4 — Un bloque, dos lados, un solo generador

El esqueleto ya es una función compartida entre `init` (autor) y `draft`
(revisor), con dos pasajes conmutados inline
([walkthrough:392-471](../../bin/git-review-verbs/walkthrough)). **Decisión**: el
bloque se escribe en ese mismo lugar, con los mismos dos parámetros que ya se
conmutan (la frase de situación y el comando de validación) y con los extremos
del rango tomados de las variables que cada rama ya resolvió: `tip` y `lower`
existen en las dos.

Lo que difiere:

| | `init` (autor) | `draft` (revisor) |
| --- | --- | --- |
| Extremo superior | `HEAD` | el SHA de `refs/remotes/<remote>/<branch>` (o local) |
| Extremo inferior | `fold_lower(...)` — un commit (a veces sintético) | `resolve_lower_bound(...)` — commit **o tree OID** |
| Situación del árbol | «estás parado en el PR» | «estás en la base» o «estás dentro de una review» |

**Decisión sobre qué literal se escribe como extremo**: los SHA resueltos, no
los nombres de refs. Es lo que hace FR-001 verificable («referencias que git
puede resolver», no «palabras genéricas») y lo que hace que el bloque sea una
foto del rango y no una promesa sobre el futuro.

**Alternativa descartada**: nombres simbólicos (`origin/feature/x`, `HEAD`).
Sobreviven al `gc` pero no son una foto: un `--build` semanas después
compararía contra otro rango sin que nada lo dijera, que es lo contrario de lo
que la spec asume.

### El bloque se regenera al construir, no se arrastra

**Corrige una contradicción del contrato**, que decía «se preserva verbatim» y
doce líneas después justificaba el SHA commiteado con «`build` lo reescribe con
el rango del momento». Son incompatibles y hay que elegir una.

**Decisión: la reescritura lo regenera**, llamando al mismo generador que usan
`init` y `draft` — un generador, tres llamadores en vez de dos.

Por qué es mejor que preservarlo verbatim, que era lo que el contrato pedía:

- **Un bloque arrastrado envejece y miente.** `build` ya resolvió el rango
  actual, porque lo necesita para el chequeo de deriva. Preservar el bloque deja
  en el archivo una línea que dice «el rango es X» dentro de un archivo que
  `build` acaba de validar contra Y. La deriva sólo salta si cambió el *conjunto
  de paths*; commits nuevos sobre los mismos archivos la dejan pasar, y el bloque
  queda nombrando un rango viejo sin que nada lo diga. Es exactamente el fallo
  silencioso que la feature existe para eliminar, reintroducido por la puerta de
  atrás.
- **Cuesta menos código, no más.** Preservar exige detectar el bloque en el
  contenido entrante, extraerlo y reinyectarlo intacto en el orden correcto —
  una excepción nueva en el reescritor. Regenerar es una llamada más al
  generador que ya existe, como el `# Walkthrough` del encabezado, que tampoco se
  arrastra: se reemite.
- **Mantiene sincronizados el bloque y los flags que lo generaron** (ver
  Decisión 13): un `--build` con otros flags de rango, o falla por deriva, o
  reemite el bloque con los flags reales. No puede quedar diciendo `--delta` un
  bloque que se validó completo.

**Esto refina la respuesta a Q1, no la contradice.** Lo que Q1 eligió es que las
instrucciones **sobrevivan a la construcción** —para que reanotar un borrador ya
instalado no obligue a reconciliar dos archivos a mano— y su costo declarado era
«que las instrucciones envejezcan con el rango si el PR se mueve». Regenerar
entrega el beneficio íntegro y **elimina ese costo**. Lo único que se pierde es
una edición a mano del propio bloque, que no es un uso soportado: el andamiaje lo
escribe la máquina, y lo que el revisor escribe —los *whys* y el `## Heads-up`—
se preserva como siempre.

**Alternativa descartada**: preservar verbatim y aceptar el rango viejo. Es la
letra del contrato original y la descarto por lo de arriba. **También
descartada**: preservar verbatim y agregar un aviso de «este bloque puede estar
viejo». Un archivo que advierte que puede mentir es peor que uno que no miente.

---

## Decisión 5 — La superficie de entrada/salida

**Decisión**:

```sh
git review walkthrough draft [--local|--offline] [--delta] [--force] [--stdout] [--] [<branch>]
git review walkthrough draft --build [--from <file>|-] [--local|--offline] [--delta] [--force] [--] [<branch>]
```

- **`--stdout`** es el nombre que git usa para «emití a la salida estándar en
  vez de escribir archivos» (`git format-patch --stdout`, `git mailinfo`). No
  escribe nada, ni siquiera cuando la rama ya tiene borrador: imprimir no
  destruye, así que no pide `--force` (edge case explícito de la spec).
- **`--from <file>`** espeja `git commit -F` / `git notes -F` / `git tag -F`, y
  `-` es la convención universal de git para la entrada estándar. Exige
  `--build`: el esqueleto no toma entrada, así que `--from` sin `--build` es
  error de uso y no un modo implícito.
- **`--force` con `--build --from`** recupera sentido, porque ahí sí se
  reemplaza prosa por otra prosa (FR-016). Sin `--from`, `--build --force` sigue
  siendo error de uso, exactamente como hoy: reescribir canónicamente tu propio
  archivo no destruye nada.

**Por qué no un subcomando nuevo** (`walkthrough install`, `walkthrough
apply`): validar e instalar es lo que `--build` ya significa; lo único que
cambia es de dónde sale el contenido. Un subcomando nuevo duplicaría la matriz
de flags de origen y rango, que tienen que ser los mismos para que se valide
contra el rango correcto.

**FR-017 (TTY)**: `[ -t 0 ]` es POSIX y es builtin del shell — cero procesos.
`--from -` con la entrada estándar en una terminal muere con una explicación en
vez de quedarse esperando.

**FR-014 (atomicidad): ya está dada.** El `build` actual sólo escribe al final
([walkthrough:700-759](../../bin/git-review-verbs/walkthrough)): lee todo a
`$content`, corre las ocho reglas (§ *Las ocho reglas*, abajo), y recién
entonces `mv`. Con `--from` el
único cambio es de dónde sale `$content`. Lo que sí hay que agregar es el
`mkdir -p` del namespace y la guarda de nombre de archivo reservado (`nul`,
`aux`, `com1`), que hoy viven sólo en la rama del esqueleto.

---

## Decisión 6 — Dónde reporta la CLI los borradores sueltos, y a qué coste

**Decisión**: un registro `draft` por borrador en `config --porcelain`, emitido
**siempre** (con rama y sin ella).

**Rationale**: `status --porcelain` sale con **exit 2 y stdout vacío** fuera de
una rama `review/*` —la guarda corre antes de todo el bloque porcelain
([status:69-75](../../bin/git-review-verbs/status))— y los tres clientes derivan
`no-review` de ese exit code, así que ahí no hay dónde poner el dato. `config
--porcelain` es la única superficie que el panel ya consulta sin review y sin
nombrar rama.

**Por qué se emite siempre, con rama y sin ella.** No porque la salida sea
simétrica —**no lo es**: `delta` y `offer` viven dentro de `if [ -n "$branch" ]`
([config:250-276](../../bin/git-review-verbs/config)), así que el conjunto de
registros ya depende de si se nombró una rama—, sino porque **un borrador no es
de la rama consultada**. Los borradores son del working tree: el revisor está
parado en la base y `walk_draft_list` enumera el namespace entero. Condicionar su
emisión al argumento `<branch>` haría que el mismo repositorio reportara
distintos borradores según qué rama se preguntó, que es una relación que no
existe. Se emiten siempre porque son un hecho del repositorio, no de la consulta.

**Coste, que es la parte no obvia.** `config --porcelain` corre en cada refresco
del panel sin review, y este proyecto ya tuvo regresiones de segundos bajo Git
Bash por agregar procesos ahí. Presupuesto:

| Pieza | Procesos |
| --- | --- |
| Enumerar los borradores (`walk_draft_list`) | **0** — es recursión sobre globs, puro builtin |
| Progreso de **todos** los borradores | **1** — un solo `awk` con varios archivos, `FNR==1` para cerrar el anterior |
| Gitdir absoluto | **1**, y sólo si hay al menos un borrador |

Un `awk` por borrador habría sido lo natural y es lo que hay que evitar: es la
misma regla que produjo `walk_entry_fields`. `ENDFILE` **no** se puede usar (es
extensión de gawk; CI corre mawk y BSD awk): el cierre por archivo se hace con
`FNR == 1` más el `END`.

**Dos trampas de ese único `awk`, las dos verificadas y las dos con la misma
raíz: `awk` no ve los archivos, ve sus contenidos.**

1. **Cero borradores ⇒ no se invoca.** `awk` sin argumentos de archivo **lee la
   entrada estándar y se cuelga**. `config --porcelain` corre en cada refresco
   del panel y también a mano en una terminal, así que un cuelgue indefinido en
   el caso más común de todos —un repositorio sin borradores— es inaceptable, y
   viola SC-005 directamente. La enumeración decide: sin borradores no se llama
   ni a `awk` ni a la resolución del gitdir absoluto, y no se emite ningún
   registro. **Presupuesto real: 0 procesos cuando no hay borradores**, que es
   mejor que la tabla de arriba.
2. **Un borrador de cero bytes no produce ninguna línea.** `awk` no ejecuta
   ninguna regla para un archivo vacío, ni le asigna `FILENAME`: `FNR == 1` nunca
   dispara y el archivo no deja rastro. Pero un borrador vacío **tiene que
   aparecer igual**, con `0` de `0`: es custodia —hay que poder abrirlo y
   descartarlo— y es justo el estado en que queda uno recién creado. **La
   enumeración manda, no `awk`**: la lista de borradores sale de
   `walk_draft_list`, y lo que `awk` no reportó cae a `0 0`. Correlacionar en ese
   sentido —lista primero, conteos después— es lo que hace que el caso vacío no
   necesite ninguna regla especial.

**FR-024 sale gratis.** Un borrador de una review pausada vive en
`review-saved-walkthrough/`, y `walk_draft_list` sólo recorre el namespace
activo — así que jamás aparece en estos registros. No hace falta ninguna regla:
la separación de namespaces que 011 construyó ya lo garantiza, y hay un test que
lo fija para que nadie la deshaga.

**Exclusión deliberada**: los registros **no** dicen si una review activa ya
lee ese borrador. Contestarlo cuesta un `for-each-ref` más un `git config` por
review en el camino caliente, y ningún requisito lo pide: el panel dibuja el
bloque sólo con `no-review`, y descartar el borrador de una review viva ya es
una operación permitida desde 011 (degrada esa review a whole, que es lo que
`git review forget --draft` documenta). Si alguna vez hace falta, es un campo
más al final del mismo registro.

---

## Decisión 7 — La ruta viaja como campo, nunca como registro nuevo

**Decisión**: `status --porcelain` le agrega **un campo** al registro `draft`
que ya emite; `list --porcelain` gana un **registro de presencia** nuevo
(`branch-draft <branch>`), no un campo.

Parece incoherente y no lo es: son dos formas distintas de registro.

- El registro `draft` de `status` es de **presencia sin campos**, y los tres
  parsers publicados lo tratan con un `case` que no mira nada más
  ([porcelain.ts:334](../../vscode-extension/src/cli/porcelain.ts),
  [Porcelain.kt:241](../../jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Porcelain.kt),
  [Porcelain.cs:264](../../visualstudio-extension/src/GitReview.Domain/Porcelain.cs)).
  Agregarle un campo al final es aditivo puro y **verificado contra los tres**:
  ninguno valida la aridad de ese registro. La ruta va última, que es la regla
  de texto libre del contrato porcelain v1.
- El registro `branch` de `list` termina en **dos campos opcionales**
  (`position`, `total`) que se omiten juntos
  ([list:172-176](../../bin/git-review-verbs/list)). Un campo más al final sería
  ambiguo: un consumidor no puede saber si el sexto campo es `mode` + marca o
  `position`. Por eso va como registro aparte, emitido inmediatamente después de
  su fila — la misma decisión que 011 tomó para `draft` en `status`, y por el
  mismo motivo.

---

## Decisión 8 — Los cuatro controles del panel NO son acciones nuevas

**Decisión**: abrir, copiar la instrucción, validar y arrancar, y descartar son
**controles del cuerpo del panel**, declarados en `panel_layout` y en un mapa
`draft_controls:` del canónico, y **no** entradas de `actions:`. La matriz
sigue teniendo 27 acciones.

**Rationale**: el proyecto ya tiene esa categoría —`copyCliInstall`,
`outOfRangeHelp`, `openSupport` son controles del cuerpo que no son acciones—, y
el criterio que los separa es el que aplica acá: **un control que sin la fila
que lo dibuja no tiene sujeto**. «Descartar el borrador» desde la paleta no
sabría cuál.

El ahorro es concreto y verificable, y corrige lo que la checklist de
`/speckit-specify` dio por seguro. Ser una acción obliga a mover, a la vez:

- el conteo fijo `27` en **dos** puntos de
  [`check-client-product-surface.mjs:47,79`](../../scripts/check-client-product-surface.mjs);
- `contributes.commands` de la extensión (con título de paleta cada uno);
- `ActionArgv.kt` y el menú **Tools → git review** de JetBrains;
- `ActionArgv.cs` **más** un `IDSymbol` en el `.vsct` y una entrada en
  `MenuCommands` de `GitReviewPackage` por cada una — el verificador exige
  paridad exacta entre las tres.

Ser un control del cuerpo cuesta, en cambio: cuatro ids en `PANEL_MESSAGES`
([walkthroughViewProvider.ts:10](../../vscode-extension/src/views/walkthroughViewProvider.ts)),
cuatro `ControlId` en los dos dominios portados, y extender
`collectCanonicalControls()` con el mapa nuevo — la misma extensión que ya
existe para `inventory_controls`.

---

## Decisión 9 — El bloque del panel se suma, no reemplaza

**Decisión**: en el canónico, `no-review` gana `{block: draft_block, when:
has_drafts}` como **primer** bloque de su lista, y un mapa `draft_controls:`
paralelo a `inventory_controls:`. **No** se crea una situación
`no-review-drafts` al estilo de `no-review-setup`.

**Rationale**: `no-review-setup` es una clave aparte porque *reemplaza* el
cuerpo entero; acá el cuerpo sigue entero debajo (FR-025, decisión Q4 de la
spec). El esquema ya soporta `when:` en un bloque (`{block: heading, …, when:
has_reviews}`), así que expresarlo como bloque condicional evita duplicar la
lista completa de bloques de `no-review` en el YAML — que es lo que se
desincronizaría en el próximo cambio del panel.

---

## Decisión 10 — Los clientes dejan de derivar la ruta

**Decisión**: `openDraft` de la extensión deja de armar la ruta y usa la que
reporta la CLI; `gitdirFromLink` desaparece de `draftFlow.ts`.

**Rationale**: hoy la extensión hace `path.join(gitdir, "review-walkthrough",
branch + ".md")` resolviendo el gitdir a mano —incluido el caso de `.git` como
archivo, para worktrees y submódulos—
([startReview.ts:260-290](../../vscode-extension/src/commands/startReview.ts)).
Eso es exactamente lo que SC-008 prohíbe, es la causa del caso «no se pudo
abrir» que `draftWaitMessage` tiene que explicar, y deja de hacer falta en
cuanto la CLI reporta la ruta absoluta. Retirar esa derivación es parte del
valor de la Fase 3-4, no un extra.

---

## Decisión 11 — Qué cuenta como entrada anotada

**Decisión** (Q5 de la spec, FR-022, SC-013): una entrada cuenta cuando tiene
**las dos** marcas resueltas:

1. **posición** — el encabezado es `## N. <path>` con `N` numérico, no `## ?.`;
2. **why** — su cuerpo tiene al menos una línea no vacía que no sea un marcador
   reservado (`> key`, `> at: `) y **no** tiene ninguna línea `^<!-- why`.

Denominador: **todos** los encabezados de entrada del archivo, numerados o no.

**Rationale**: son las dos marcas que el esqueleto deja, una por entrada, y son
las mismas dos que `build` verifica como «sin completar» —así que el progreso y
la validación hablan del mismo hecho sin compartir código ni prometer lo mismo.
El progreso se cuenta **sobre el archivo, sin cruzarlo con el rango** (FR-022):
informar avance no es validar, y cruzarlo obligaría a resolver el rango de cada
rama con borrador en cada `config --porcelain` — N resoluciones de rango en el
camino caliente, por un número que igual no promete nada.

**Alternativa descartada**: contar sólo el *why*. Un borrador con todos los
whys y sin números no es legible en ningún orden, y el progreso diría 100 %.

---

## Decisión 13 — El bloque registra con qué flags se generó

**Problema encontrado tarde**: *Validate and start* del panel invoca `start` con
los flags por defecto (remoto, rango completo). Un borrador generado con
`--delta`, `--local` u `--offline` —los tres soportados, y `--delta` además hace
que el bloque anuncie un rango incremental (FR-005)— cubre otro conjunto de
paths, así que ese botón **falla siempre** con error de deriva, y el panel no
tiene salida: no puede ni reintentar bien ni explicar por qué. Era una trampa
garantizada para un caso ordinario.

**Decisión**: el bloque registra el origen y el rango con los que se generó, y
esa es la **única** casa de ese dato:

```text
     Generated with: --local --delta      (o "Generated with: (defaults)")
```

El registro `draft` de `config --porcelain` lo emite como dos campos más, y
*Validate and start* los replica al invocar `draft --build` y `start`.

**Por qué dentro del bloque y no en una clave de config.** La alternativa
natural en este proyecto sería `reviewworkflowdraft.<src>.source`, siguiendo el
idiom de `reviewworkflow.<src>.reviewed`. Se descarta porque **le daría al
borrador dos casas que se pueden desincronizar**: borrar el archivo a mano
—cosa que 011 permite explícitamente, y que `forget --draft --all` existe para
limpiar— dejaría una clave huérfana, y toda superficie de custodia tendría que
aprender a limpiarla. Dentro del bloque el dato nace y muere con el archivo, sin
un solo camino de limpieza nuevo.

**Y cuesta cero leerlo.** El reporte de progreso ya abre todos los borradores en
un único `awk`; extraer una línea más del mismo pase no agrega ni un proceso.

**Consistencia garantizada por la regeneración** (Decisión 4): un `--build` con
flags distintos de los del bloque, o falla por deriva, o reemite el bloque con
los flags reales. No puede quedar un bloque diciendo `--delta` sobre un archivo
validado completo.

---

## Decisión 14 — El asistente no abre el borrador, y por eso no necesita su ruta

**Problema encontrado tarde**: el contrato le prohíbe al cliente construir la
ruta del borrador (SC-008) y le prohíbe parsear stdout, pero el asistente
acortado tenía que **abrir el borrador recién creado** — y en ese instante no
existe todavía ningún registro porcelain que traiga la ruta. Quedaba un hueco
donde dos implementadores razonables producen cosas distintas, y uno de los dos
deja puesta la derivación que la feature vino a sacar.

**Decisión**: el asistente **no abre nada**. Crea el borrador y termina; el
refresco que sigue a toda mutación trae el registro `draft` con su ruta, el
bloque del panel aparece con su fila, y el revisor abre desde ahí con *Open
draft* — un control que ya recibe la ruta por el camino normal.

Por qué es la mejor y no un rodeo:

- **Cero invocaciones nuevas.** No hace falta re-invocar `config --porcelain`
  después de crear: el refresco post-mutación ya existe y ya lo llama.
- **Cero derivación**, que era el requisito.
- **Es coherente con el resto de la feature.** El asistente abría el archivo
  *porque se iba a quedar esperando sobre él*. Sacada la espera, abrir dejó de
  tener motivo: era el último resto del bucle modal. Mantenerlo habría sido
  conservar la mitad de un mecanismo que decidimos retirar.
- **Elimina un paso**, en vez de agregar uno para tapar el hueco.

**Alternativa descartada**: re-invocar `config --porcelain` justo después de
crear, sólo para conseguir la ruta y abrir. Funciona, pero paga un proceso en el
camino caliente para adelantar medio segundo un archivo que el revisor abre a un
clic — y deja al asistente sabiendo cosas que no necesita saber.

---

## Decisión 12 — Qué NO se toca

- **Ni la ubicación del borrador ni su ciclo de vida.** `save`, `continue`,
  `clean`, `forget`, el guard de metadata de `finish` y `walk_read` quedan
  literalmente iguales. Separar de dónde viene el contenido no es moverlo.
- **Ni una regla de validación.** `--from` reusa el mismo cuerpo, con las mismas
  **ocho** reglas, ni una de más ni de menos (FR-013). Ver § *Las ocho reglas*.
- **Ni `walk_preamble`.** Ver Hallazgo 1.
- **Ni la landing.** El demo muestra el formato del walkthrough, y el bloque
  nuevo es la única pieza del formato que nunca se muestra: el demo sigue siendo
  fiel. Se verifica, no se edita.
- **Ni el conteo de 27 acciones.** Ver Decisión 8.
- **Ni el registro `offer`.** `draft` / `draft-resume` siguen exactamente como
  los dejó 011; lo único que cambia es la **copy** con la que el cliente los
  presenta (FR-033), que no vive en el canónico sino en los tres `OFFER_META`.

---

## Las ocho reglas de validación

«Las mismas reglas, ni una de más ni de menos» no es verificable contra un número
que nadie fijó. Las que corre `build` hoy, contadas sobre
[walkthrough:556-660](../../bin/git-review-verbs/walkthrough), son **ocho** —no
siete, como decían las versiones anteriores de este documento y de los contratos:

| # | Regla | Cómo muere |
| --- | --- | --- |
| 1 | Entradas sin numerar (`## ?.` sin reemplazar) | `die` |
| 2 | Comentarios `<!-- why` sin reemplazar | `die` |
| 3 | Placeholder de `## Heads-up` sin reemplazar | `die` |
| 4 | `> key` con un valor al lado | `die` |
| 5 | Encabezado de entrada fuera de la forma `## N. <path>` | `die` |
| 6 | Sin ninguna entrada | `die` (dos mensajes: uno para `draft`, otro para `init`) |
| 7 | Paths duplicados | `die` |
| 8 | Deriva contra el rango real (falta o sobra un path) | `echo` a stderr + exit ≠ 0 |

La 6 tiene dos mensajes distintos pero es una sola regla; la 8 es la única que no
usa `die`, porque emite las dos listas por separado antes de salir. **Esta tabla
es la referencia**: cualquier documento o tarea que diga «las N reglas» apunta
acá en vez de repetir un número.
