# Quickstart: validar la paridad CLI ↔ panel

Cómo comprobar, a mano y de punta a punta, que la feature hace lo que el spec
pide. Los detalles del formato están en
[`contracts/status-porcelain-v2.md`](./contracts/status-porcelain-v2.md) y la
forma de los datos en [`data-model.md`](./data-model.md); acá sólo está qué
correr y qué esperar.

## Prerrequisitos

- El checkout instalado (`./install.sh`), porque tanto la extensión como los
  tests de integración invocan el `git review` del `PATH`.
- Docker, para la suite de bats — **no** correr bats bajo Git Bash en Windows.
- `vscode-extension/` con dependencias instaladas (`npm install`).

## 1. La CLI emite los tres registros

Armá un repositorio de juguete con un asunto y un autor conocidos:

```sh
./tests/sandbox.sh
```

Entrá al repo de trabajo que imprime el script y arrancá una review commit por
commit:

```sh
git review start --step feature/checkout
```

Pedí el estado en formato porcelain:

```sh
git review status --porcelain
```

**Esperado**: además de los registros `state` y `entry` que ya emitía, una línea
`subject` y una línea `author` por cada posición de la secuencia, con la misma
posición que su `entry`. El asunto de la posición actual coincide con el que
imprime `git review status` sin flags.

Para el registro `base`, la review sin walkthrough:

```sh
git review abort
git review start feature/telemetry
git review status --porcelain
```

**Esperado**: una línea `base` con la rama de integración configurada. Si el
repositorio no tiene `reviewworkflow.base`, la línea **no aparece** — no aparece
vacía.

## 2. Un consumidor viejo no se rompe

Es la prueba de FR-002 y SC-004, y se hace sin instalar nada viejo: leyendo sólo
los registros que el contrato anterior conocía.

```sh
git review status --porcelain | grep -E '^(state|entry)'
```

**Esperado**: exactamente la misma salida, byte a byte, que producía antes de
esta feature. Los registros existentes no cambiaron de aridad ni de contenido.

## 3. Los bytes hostiles no desplazan nada

Es la validación central de la feature y la que protege FR-011. Creá un commit
con un tab en el asunto y otro en el nombre del autor:

```sh
git -c user.name="$(printf 'no\tmbre')" commit --allow-empty -m "$(printf 'con\ttab')"
```

Arrancá una review commit por commit que lo incluya y pedí el porcelain.

**Esperado**, y esto es lo que hay que mirar de verdad:

- el registro `subject` de esa posición contiene el tab literal;
- **el registro siguiente no se desplazó**: sigue siendo una línea `subject` o
  `author` con su etiqueta en el primer campo y su posición en el segundo.

La aserción que importa no es que el texto "se vea bien" — es que ningún otro
dato cambió de lugar. Un tab de más no rompe nada a la vista: corre el campo
siguiente, en silencio.

Probá también un asunto vacío y uno con acentos y emojis, y verificá que el
asunto vacío produce un **campo vacío** y no la ausencia del registro.

## 4. El panel muestra lo mismo que la terminal

Con el sandbox armado y una review commit por commit activa, abrí `<sandbox>/work`
en un Extension Development Host (F5 desde `vscode-extension/`, o instalá el
checkout y usá tu VS Code normal).

**Esperado en el panel**, comparándolo con `git review status` en una terminal
al lado:

- el asunto del commit como elemento principal de la entrada;
- el identificador corto y el autor en la línea de metadatos, junto a la
  posición;
- en la barra, el origen de la review y el tip abreviado;
- al abrir el selector de la secuencia, cada commit identificado por su asunto.

Avanzá con el botón de siguiente y comprobá que el asunto y el autor cambian al
commit nuevo — que no quedó mostrando los anteriores.

Con una review sin walkthrough, el panel indica la base contra la que se armó el
rango.

## 5. Con una CLI vieja el panel queda como estaba

La degradación de FR-003 se prueba apuntando la extensión a un `git review` que
no emita los registros nuevos: `gitReview.path` a un checkout anterior, o un
script envoltorio que filtre las etiquetas nuevas.

```sh
git review status --porcelain | grep -vE '^(subject|author|base)'
```

**Esperado**: el panel dibuja exactamente lo que dibujaba antes de esta feature
— el identificador corto, la posición, las marcas — sin huecos, sin campos
vacíos y sin ningún mensaje de error.

## 6. Una review grande no se siente lenta

```sh
git review start --step <una rama con decenas de commits>
```

**Esperado**: `git review status --porcelain` responde tan rápido como antes de
la feature, y navegar por el panel no introduce una demora perceptible. El
número de procesos git empleados en producir los asuntos no depende de la
cantidad de commits (SC-008); si al crecer la secuencia la respuesta se degrada
de forma visible, la implementación cayó en el bucle por commit que la
Decisión 2 del research descarta.

## Suites automatizadas

```sh
shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh tests/sandbox.sh
```

```sh
./tests/run-docker.sh
```

```sh
cd vscode-extension && npm test
```

```sh
cd vscode-extension && npm run preview
```

El preview renderiza los estados del panel lado a lado; los estados nuevos
(entrada de step con asunto y autor, whole con base, step con CLI vieja) se
agregan a `preview/fixtures.ts` como salida porcelain de ejemplo, así que
siguen al código real y no se mantienen aparte.
