# Contrato (enmienda): registro `guide` en `config --porcelain`

**Feature**: `013-guias-de-autoria`

Enmienda aditiva a
[`012-prompt-agente-draft/contracts/config-porcelain-drafts.md`](../../012-prompt-agente-draft/contracts/config-porcelain-drafts.md).
Describe el delta; la invocación, los flags y la gramática porcelain v1 no
cambian. **Los registros `config`, `candidate`, `remote-candidate`, `delta`,
`offer` y `draft` no cambian en nada.**

## Qué es una guía de autoría

Prosa sobre el **contenido** del walkthrough —qué entradas merecen `> key`, cómo
se escribe un porqué, qué va en el heads-up—, nunca sobre su formato. La CLI no
lee, parsea ni valida una sola línea: la detecta y la nombra, y quien la lee es
el agente que completa el walkthrough. Ese contrato mínimo es lo que deja a
`build` como único dueño del formato.

Son **dos**, y contestan preguntas distintas:

| `kind` | Quién                                            | Dónde                                          |
| ------ | ------------------------------------------------ | ---------------------------------------------- |
| `team` | cómo **este proyecto** quiere que se anoten sus PRs | `<toplevel>/.review/walkthrough-guide.md`, committeada |
| `own`  | cómo **vos** anotás                              | `<git-common-dir>/review-walkthrough-guide.md`, fuera del árbol |

## Registro `guide` (exactamente dos veces, `team` primero)

```text
guide<TAB><kind><TAB><path><TAB><state>
```

| Campo    | Valor                                                                     |
| -------- | ------------------------------------------------------------------------- |
| `kind`   | `team` \| `own`                                                            |
| `path`   | ruta **absoluta**, resuelta por la CLI. Existe en disco sólo si `state != absent` |
| `state`  | `in-force` \| `empty` \| `absent`                                          |

### Siempre las dos filas, exista o no el archivo

Es la única diferencia de forma con los registros `draft`, que se emiten sólo
para los borradores que existen. **La ausencia se reporta; no se implica con el
silencio**: sin la fila, un cliente no puede ofrecer *crear* la guía que falta
sin rearmar su ruta de su lado, que es exactamente lo que la regla del path
reportado existe para impedir.

### `empty` no se pliega en `absent`

Las dos significan «no hay convenciones aplicándose», pero son dos ofertas
distintas: con el archivo ahí lo que se ofrece es **abrirlo**, no crearlo, y
descartarlo es posible donde descartar uno que no existe no lo es.

La regla de «en vigor» es la de `walk_draft_body` —un archivo vacío o de puro
whitespace no es un conjunto de convenciones— pero implementada con **cero
procesos**: un `read` builtin que corta en la primera línea no vacía, que para
una guía real es la línea 1.

### `status --porcelain` NO lo emite

Lo emitió mientras el panel dibujó las dos guías adentro de una review: ahí lee
ese verbo y ningún otro, así que sin los registros las filas habrían costado una
invocación entera de `config --porcelain` por refresco. Esa sección no existe
más —todo lo que cuelga de `walkthrough` es del autor parado en su propio PR, y
adentro de una review estás parado en el de otro—, y con nada que dibujar el
registro pasó a ser un dato que nadie pide en el camino que tiene que salir
barato. El emisor sigue siendo uno solo, `emit_guide_records`, con un único
llamador.

### Se emite con y sin argumento de rama

Una guía es un hecho del **repositorio**, no de la rama consultada — el mismo
motivo por el que los registros `draft` se emiten en las dos formas.

## Costo

Un solo proceso: `git rev-parse --show-toplevel --absolute-git-dir` contesta las
dos preguntas en una llamada. El gitdir **común** se deriva sacándole
`/worktrees/<name>` al absoluto, y no se pide con `--git-common-dir`, que
contesta relativo al *cwd*: en Windows prefijarlo con `$PWD` mezcla estilos de
path adentro de un mismo registro (`C:/Users/…` de rev-parse contra `/tmp/…` de
Git Bash) y el cliente no puede abrir el resultado. `--path-format=absolute`
sería la vía directa y es git 2.31; este proyecto soporta 2.23.

El estado de cada guía son tests de archivo más, para una que tenga bytes, la
lectura builtin de arriba. Importa porque este verbo corre en **cada refresco
del panel**.

## Degradación

Una CLI que no conoce el registro no emite ninguna fila. Los clientes tratan eso
como lista vacía y el bloque entero desaparece del panel — la misma degradación
que ya tienen los registros `draft`, y el motivo por el que ninguno de los tres
completa una fila que no llegó.

## Superficie de mutación

`git review walkthrough guide [--team] [--delete]`. Crea el archivo **vacío** a
propósito: no hay `build` que rechace un esqueleto a medio llenar, así que unas
instrucciones que quedaran adentro las leería el próximo agente como si fueran
las convenciones. `--delete` es sólo para la propia; la compartida es un archivo
trackeado, o sea `git rm` más un commit, y `--delete --team` se niega diciéndolo.
Crear la compartida adentro de una review también se niega: la extracción de
`finish` es `git add -A`, así que el archivo se iría en el `review-fixes/` de
otra persona.
