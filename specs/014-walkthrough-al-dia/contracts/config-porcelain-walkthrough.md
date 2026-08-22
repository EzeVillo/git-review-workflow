# Contrato (enmienda): registro `walkthrough` en `config --porcelain`

**Feature**: `014-walkthrough-al-dia`

Enmienda aditiva a
[`013-guias-de-autoria/contracts/config-porcelain-guide.md`](../../013-guias-de-autoria/contracts/config-porcelain-guide.md).
Describe el delta; la invocación, los flags y la gramática porcelain v1 no
cambian. **Los registros `config`, `candidate`, `remote-candidate`, `delta`,
`offer`, `draft` y `guide` no cambian en nada.**

## Qué contesta

Un walkthrough se escribe **cuando el PR está terminado**, y después el PR sigue
moviéndose: vuelven los comentarios del review, cambian tres archivos, y el
momento en que eso pasa es exactamente aquel en el que nadie está pensando en el
walkthrough. El verbo que lo diría es `walkthrough build`, y correrlo hay que
acordárselo.

Este registro es lo que le permite al panel decirlo solo, y contesta **la mitad
barata** de la pregunta —«¿conviene mirar?»— a propósito. La respuesta exacta
(qué archivos entraron, cuáles salieron, qué porqués envejecieron) es de `build`,
que es lo que corre el control de la fila.

## Registro `walkthrough` (exactamente una vez)

```text
walkthrough<TAB><state><TAB><path><TAB><annotated><TAB><total>
```

| Campo       | Valor                                                                            |
| ----------- | -------------------------------------------------------------------------------- |
| `state`     | `in-sync` \| `stale` \| `superseded` \| `unknown` \| `absent`                      |
| `path`      | ruta **absoluta** de `.review/walkthrough.md`, exista o no el archivo             |
| `annotated` | entradas con posición **y** *why* resuelto, más el heads-up                       |
| `total`     | todo lo que `build` exige completar: una unidad por entrada más el heads-up       |

El par `annotated`/`total` es **el mismo que reportan los registros `draft`**, del
mismo `awk`, para que «cuánto está escrito» signifique una sola cosa a los dos
lados de la review.

### Siempre la fila, exista o no el archivo

Como los registros `guide` y al revés que los `draft`: **la ausencia se reporta,
no se implica con el silencio**. Sin la fila un cliente no puede ofrecer *crear*
un walkthrough del que nunca le hablaron, y rearmar la ruta de su lado es lo que
la regla del path reportado existe para impedir.

Se emite **con y sin argumento de rama**, por el mismo motivo que los `draft`: es
un hecho del working tree, no de la rama consultada.

### Los cuatro estados

| `state`      | Qué significa                                                                     |
| ------------ | --------------------------------------------------------------------------------- |
| `absent`     | no hay `.review/walkthrough.md` en el working tree                                 |
| `in-sync`    | el rango no cambió fuera de `.review/` desde que el archivo se escribió o construyó |
| `stale`      | sí cambió: entraron o salieron archivos, o uno que el walkthrough ya anota se movió |
| `superseded` | es el walkthrough de un PR **ya mergeado** a la base: viajó con el merge            |
| `unknown`    | sin bloque de instrucciones (borrarlo a mano es legal), o su tip ya no es un objeto de este clone |

### `superseded` NO se pliega en `stale`

Tu PR se mergea, el sidecar viaja a la base con él, arrancás la rama siguiente y
tocás uno de los mismos archivos. La entrada de ese archivo sigue ahí, con un
*why* que describe un cambio que **ya salió** — y reconciliar contra eso conserva
prosa que no es de este PR y que se commitearía con él.

No es que haya quedado atrás: **no falló nada**, pertenece a un rango que cerró.
Son dos ofertas distintas y por eso son dos estados: sobre `stale` lo que se
ofrece es actualizar, sobre `superseded` empezar de cero.

Se decide con **un solo proceso**: `git merge-base --is-ancestor <tip> <baseref>`,
o sea "¿los commits que escribieron esto ya están en la base?". El límite es la
base y no el merge-base, porque la pregunta es «¿aterrizó?» y el merge-base se
mueve con cada rebase. Se pregunta **sólo cuando el diff ya dijo `stale`**: un
walkthrough que todavía coincide con su rango no puede ser de otro PR, así que
sus dos procesos quedan fuera del camino común.

Y «no se puede saber» nunca se lee como «no»: sin tip registrado, o con un objeto
que este clone ya no tiene, el estado es `unknown` — si no, un clone fresco
volvería a reconciliar contra un PR mergeado sin decir nada.

### `unknown` NO se pliega en `stale`

Sin el bloque la pregunta **no tiene respuesta**, y contestar la peor de las dos
manda a rehacer un orden de lectura que puede estar perfecto. Es la misma regla
por la que `empty` no se pliega en `absent` del lado de las guías: dos estados que
suenan parecido habilitan ofertas distintas.

### `stale` no es un veredicto

El badge que los tres clientes dibujan dice **«may be out of date»**, no «out of
date». Lo que se compara acá es barato —un `git diff` entre el tip que registró el
bloque de instrucciones y `HEAD`— y corre en cada refresco del panel; afirmar de
más sobre un archivo que puede estar perfecto es peor que sugerir mirarlo.

## Cómo se decide, y qué cuesta

1. **El tip contra el que se validó** sale del bloque `<!-- git-review-range: -->`
   del propio archivo (`tip <sha>`), que `init` y `build` regeneran en cada
   escritura. Se lee con un `read` builtin que corta en el fin del bloque, en la
   primera entrada o a las 80 líneas: **cero procesos**.
2. **La comparación** es `git diff --quiet <tip> HEAD -- . ':(exclude).review'`.
   Dos revisiones como **dos argumentos**, nunca `A..B` (en Windows con cwd
   profundo git hace `stat()` del rango escrito como un argumento y muere con
   *Filename too long*).
3. **El par de progreso**, un `awk`, el mismo de los borradores.

### Por qué se excluye `.review/`

Committear el propio walkthrough mueve `HEAD`. Sin la exclusión, el flujo
ordinario del autor —`init`, `build`, `git commit`— terminaba en un panel que
decía que el archivo recién escrito ya estaba desactualizado.

### Validación del SHA

El valor leído del bloque se valida como **40 caracteres hexadecimales** antes de
usarse: está por convertirse en un argumento de git, y un `tip` que resultara ser
prosa de alguien no puede llegar ahí.

## Degradación

Una CLI anterior no emite el registro. El cliente no dibuja el bloque y no pasa
nada más — la misma degradación que tienen los `draft` y los `guide`.
