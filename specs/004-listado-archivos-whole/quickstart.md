# Quickstart — validación de la feature

Cómo comprobar, de punta a punta, que
[el listado de archivos en modo whole](./spec.md) hace lo que la spec dice. Los
detalles de formato están en
[contracts/consolidacion-porcelain.md](./contracts/consolidacion-porcelain.md) y
[data-model.md](./data-model.md); acá sólo está qué correr y qué esperar.

## Prerrequisitos

- El checkout instalado (`./install.sh`), para que `git review` resuelva desde el
  `PATH`. Para el panel alcanza además con apuntar la setting `gitReview.path` a
  `bin/git-review`.
- Docker, para la suite de `bats`. En Windows **no** corras `bats` bajo Git Bash:
  son minutos por archivo.
- Un sandbox descartable:

```bash
./tests/sandbox.sh
```

Reconstruye desde cero en cada corrida y arma, entre otras cosas, un PR con
walkthrough commiteado y paths con espacios y acentos, más ramas para los estados
que ese PR no puede mostrar. El comando imprime cómo entrar.

---

## 1. El listado en la CLI (US1)

Arrancá una review sin walkthrough sobre el PR de juguete:

```bash
git review start --no-walk feature/checkout
```

**Esperado en `git review status`**: bajo la línea de `mode whole`, una línea por
archivo del PR con su posición 1-based, incluidos los paths con espacio y con
acento, sin comillas ni escapes. Ninguno truncado.

**Contraste que hace la prueba honesta** — el conjunto tiene que coincidir con el
que reporta git por su cuenta:

```bash
git diff --name-only HEAD "$(git config branch.review/feature/checkout.reviewtip)"
```

**Esperado en `git review status --porcelain`**: un registro `entry` por archivo,
con la posición y el path, y **nada** después del path. El registro `state` sigue
teniendo sus seis campos: si aparecen `position`/`total`, la lista se convirtió en
un cursor y eso es un fallo (FR-004).

**Verificá también que sigue sin haber navegación**:

```bash
git review next
```

Tiene que fallar igual que antes de la feature.

## 2. El rango vacío

Sobre la rama del sandbox cuyo rango no toca archivos: cero registros `entry`, exit
`0`, y la salida humana diciendo con palabras que no hay archivos. Una lista en
blanco sin explicación es un fallo (FR-007).

## 3. El sidecar en el orden de lectura (US4)

Entrá en modo walk sobre el PR que commitea un walkthrough:

```bash
git review start feature/checkout
```

**Esperado**: el total del orden de lectura incluye `.review/walkthrough.md`, que
aparece **al final**, marcado como no anotado (`uncovered`). Avanzando con
`git review next` hasta el final, el último alto es ese archivo, y recién después
llega el aviso de que no hay más entradas.

**Y lo que NO debe pasar** — el generador sigue sin proponerlo (FR-022):

```bash
git review walkthrough build
```

El archivo resultante no puede tener una entrada para `.review/walkthrough.md`.

## 4. Compatibilidad de una review walk en curso (FR-023)

El caso que sólo se ve cruzando versiones: una review `walk` abierta **antes** del
cambio tiene un `reviewwalkcount` que no contaba el sidecar. Al retomarla con la
versión nueva, el total derivado es mayor que el registrado.

**Esperado**: ni la CLI ni el panel reportan nada. Sin error, sin "la base se
movió". Se simula bajando a mano el valor registrado:

```bash
git config branch.review/feature/checkout.reviewwalkcount 3
git review status
```

## 5. El panel (US2)

El panel sólo tiene algo que mostrar dentro de un repo con review activa. Con el
sandbox en modo `whole`, abrí `<sandbox>/work` en el Extension Development Host
(F5 desde `vscode-extension/`, config *Run Extension*).

**Esperado**: donde antes decía *"This review has no walkthrough…"* ahora está la
lista de archivos con su conteo. Un clic abre el archivo, editable; en un archivo
que el PR elimina, abre el diff. No hay `[k/N]` ni controles de anterior/siguiente.

Para ver los nueve estados del panel lado a lado sin levantar un editor:

```bash
npm run preview --prefix vscode-extension
```

El preview usa el `panelHtml()` real y salida `--porcelain` de ejemplo pasada por el
parser real, así que el estado de `whole` tiene que mostrar la lista sin que haya
que mantenerlo aparte. Lo que el preview **no** puede afirmar: los botones no tienen
extensión del otro lado. Para comportamiento, F5.

## 6. La consolidación del contrato (US3)

```bash
grep -ri "porcelain[- ]v2\|status-porcelain-v2" .
```

**Esperado**: sin resultados. Y el contrato de
`specs/001-contrato-porcelain/contracts/status-porcelain.md` se lee completo — con
`subject`, `author`, `base` y la regla del texto libre adentro — sin remitir a otro
archivo (SC-005).

## 7. Las suites

```bash
./tests/run-docker.sh
```

```bash
npm test --prefix vscode-extension
```

Y el lint que corre CI, que en este checkout va por Docker porque `shellcheck` no
está instalado local:

```bash
shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh tests/sandbox.sh
```

**Ojo con dos cosas al leer lo rojo**: los tests del instalador de PowerShell
(`*-ps1.bats`) no corren en el contenedor porque no hay `pwsh`, y dos specs de
integración que abren tabs son flaky en Windows por el host de test. Ante un *"no
se abrió ningún tab"*, medí el baseline en un checkout sin tocar antes de buscar la
causa en el cambio.
