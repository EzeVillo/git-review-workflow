# Contrato: `git review config`

Formato porcelain v1 — el mismo de
[`001-contrato-porcelain`](../../001-contrato-porcelain/contracts/status-porcelain.md),
que sigue siendo la fuente normativa: texto plano, una línea por registro, campos
separados por tab, primer campo = etiqueta. Un consumidor **debe** ignorar los
campos extra al final de un registro que conoce y las líneas cuya etiqueta no
reconoce.

Este verbo es nuevo. Existe porque el contrato de `001` acota `status
--porcelain` a **dentro de una review activa** ("no hay modo vista previa fuera
de una review"), y lo que hace falta para *iniciar* una es exactamente lo
contrario: qué hay disponible **antes** de que la review exista.

## Invocación

```sh
git review config                    # toda la configuración efectiva, para leer
git review config --porcelain        # lo mismo, legible por máquina, + ramas candidatas
git review config <clave>            # el valor efectivo de una clave
git review config <clave> <valor>    # fija la clave
git review config --unset <clave>    # la borra
```

La gramática espeja `git config` a propósito (research.md, Decisión 2): clave
sola para leer, clave + valor para escribir. Válido en cualquier repositorio git,
con o sin review activa. Las formas de lectura no mutan nada.

**`--` termina el parseo de opciones**, igual que en `start` y que en cualquier
verbo de git: `git review config base -- -foo` fija la base en una rama llamada
`-foo`. No es hipotético — es un nombre de rama legal, y el consumidor pasa el
valor verbatim desde el listado de candidatas, sin inspeccionarlo. Vale también
para `--porcelain -- <rama>`.

### Claves

Las del producto, **no** las claves crudas de git. La traducción es interna y
puede cambiar sin romper a nadie, que es todo el punto (FR-008).

| Clave | Qué es | Sin configurar |
|-------|--------|----------------|
| `base` | La rama contra la que se arma el rango de una review completa | Ausente. Un review completo falla pidiéndola. |
| `remote` | El remoto del que sale la copia revisada | `origin` |

Una clave desconocida es un error de uso (exit `1`), no un valor vacío: escribir
`git review config bese main` tiene que decirlo, no guardar silenciosamente algo
que nadie va a leer.

### Exit codes

| Code | Significado |
|------|-------------|
| `0` | Éxito. En la forma de lectura de una clave sin valor configurado y sin default, no se imprime nada y el código sigue siendo `0`. |
| `1` | Error: no es un repositorio git, clave desconocida, uso inválido, o el valor no se pudo escribir. |

No hay exit `2`: este verbo no depende de que haya una review, así que "no hay
review" no es una condición que pueda observar.

---

## Registro `config` (cero o más, uno por clave con valor efectivo)

```text
config<TAB>clave<TAB>valor
```

- `clave`: `base` | `remote`. Va inmediatamente después de la etiqueta, siguiendo
  la regla de `001` (el identificador nunca al final, para que lo que se agregue
  después sea siempre aditivo).
- `valor`: el valor efectivo, incluidos los defaults del producto. `remote`
  siempre tiene uno; `base` puede no tenerlo.
- **Una clave sin valor efectivo omite su registro entero.** No se emite con el
  valor vacío. Es cómo el consumidor distingue "configurado" de "ausente"
  (FR-008).

Ejemplo, repositorio configurado:

```text
config	base	main
config	remote	origin
```

Ejemplo, repositorio recién clonado sin configurar (es un estado normal, exit `0`):

```text
config	remote	origin
```

---

## Registro `candidate` (cero o más, una por rama elegible)

```text
candidate<TAB>name<TAB>origin<TAB>current
```

- `name`: nombre de rama **sin prefijo de namespace** (`feature/checkout`, no
  `refs/remotes/origin/feature/checkout`). Es el valor que vuelve a la CLI como
  argumento de `start` o de `config base`.
- `origin`: `remote` | `local`. De qué namespace salió. `remote` significa el
  remoto efectivo que reporta el registro `config`, no `origin` literal.
- `current`: `1` si es la rama que `HEAD` tiene ahora, `0` si no. A lo sumo una
  fila lo tiene en `1`; con `HEAD` desacoplado, ninguna.

**Exclusiones**: nunca se emiten ramas de los tres namespaces del producto
(`review/*`, `review-saved/*`, `review-fixes/*`), ni la pseudo-rama
`<remote>/HEAD`. Son exactamente las que `start` rechaza
(`bin/git-review-verbs/start:151-153`), y ofrecerlas sería ofrecer un fallo.

**Duplicados esperados**: una rama que existe local y remotamente aparece **dos
veces**, una por origen. No es un defecto: es el dato que hace significativa la
elección de origen.

**Orden**: el de `git for-each-ref`, que es lexicográfico por refname. Estable
entre invocaciones, y el consumidor no debe depender de ningún otro criterio.

**Bytes**: un nombre de rama no puede contener tabs, espacios ni caracteres de
control — git los prohíbe —, así que el campo es el nombre byte por byte y
**no** aplica el des-citado de paths de la Decisión 8 de `002`. Los caracteres no
ASCII salen literales.

Ejemplo:

```text
candidate	feature/checkout	remote	0
candidate	feature/checkout	local	1
candidate	main	remote	0
candidate	main	local	0
```

---

## Registro `delta` (cero o una, sólo cuando se pregunta por una rama)

```text
delta<TAB>name<TAB>tip
```

Emitido sólo cuando la invocación nombra una rama:

```sh
git review config --porcelain <rama>
```

- `name`: la rama por la que se preguntó.
- `tip`: el SHA completo del último tip revisado de esa rama.

**Ausente cuando esa rama nunca se revisó**, que es la forma en que el consumidor
sabe que no puede ofrecer el rango incremental (FR-015): sin este registro, la
opción no se ofrece. Ausente también cuando la invocación no nombra ninguna rama
— el reporte general no lo incluye, porque emitirlo para todas las ramas
convertiría un costo constante en uno por rama.

---

## Costo

La forma `--porcelain` completa cuesta un **número constante de procesos**, no uno
por rama: una invocación de `git for-each-ref` con `--format` sobre los dos
namespaces, más las lecturas de config. Es la misma regla que `001` y `003`
aplicaron a `status` y por el mismo motivo medido: bajo Git Bash en Windows,
donde `fork()` está emulado, un proceso por ítem es lo que hace inusable a un
repositorio grande.

---

## Salida humana

Sin `--porcelain`, el verbo imprime la configuración en la forma de las demás
salidas humanas del producto (dos columnas alineadas, un renglón por clave) y
**no** lista ramas candidatas: para una persona, `git branch` ya existe y es
mejor. Las ramas son un dato para el consumidor programático, que no tiene otra
forma de obtenerlas sin cruzar la frontera de `002`.
