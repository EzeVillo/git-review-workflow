# Quickstart: validar la extensión de VS Code

Cómo correr la extensión y comprobar que hace lo que el spec pide. No es una
guía de implementación: los detalles de forma están en `contracts/` y en
`data-model.md`.

## Prerrequisitos

- Node.js ≥ 18 y VS Code ≥ 1.75.
- La CLI de este repositorio disponible como `git review`. Alcanza con el
  checkout local:

```bash
./install.sh
```

- Verificá que git la descubre y que trae el contrato (Decisión 1: hace falta
  ≥ `0.3.0`):

```bash
git review --version
```

- `reviewworkflow.base` configurado en el repositorio de prueba — sin él, una
  review completa falla:

```bash
git config reviewworkflow.base main
```

## Correr la extensión

```bash
npm install --prefix vscode-extension
```

Abrí la carpeta `vscode-extension/` en VS Code y lanzá el *Extension
Development Host* (F5). Se abre una segunda ventana con la extensión cargada;
en ésa abrís el repositorio de prueba.

Para instalarla de verdad (fuera del host de desarrollo), empaquetala y
instalá el `.vsix`:

```bash
npx --prefix vscode-extension vsce package
```

## Escenarios de validación

Cada uno se prepara desde la terminal, con la CLI, y se verifica en el panel.
Los números remiten a las historias del [spec](./spec.md).

### 1. El panel muestra el recorrido (US1, US2 — P1)

**Preparar**: un repositorio con un PR que traiga `.review/walkthrough.md`
committeado, con varias entradas y al menos una marcada con `> key`, y algún
archivo del rango sin entrada.

```bash
git review start <rama-del-pr>
```

**Verificar en el panel**:

- Lista las entradas en el orden del walkthrough, no alfabético.
- La primera aparece como actual; la marcada con `> key` se distingue.
- El subtítulo de la vista muestra `1/N`.
- Los archivos sin entrada aparecen agrupados aparte.
- Un clic en una entrada abre el archivo con los cambios del PR, y editarlo
  modifica el working tree.

**Contrastar con la CLI** — el panel no puede decir otra cosa que esto:

```bash
git review status --porcelain
```

### 2. El porqué (US3 — P2)

Con el panel poblado: apuntar (hover) a una entrada muestra su explicación;
la acción *Ver el porqué* la abre completa, con sus saltos de línea. Una entrada
sin cuerpo lo dice, y eso no es un error.

**Contrastar**:

```bash
git review status --why <path-de-la-entrada>
```

### 3. Navegar, y que la posición sea la misma que la de la CLI (US4 — P2)

Avanzar desde el panel; verificar que abre el archivo de la entrada siguiente y
que la posición registrada coincide:

```bash
git review status --porcelain | head -1
```

Después, al revés: correr `git review next` **en la terminal** con el panel
abierto y verificar que el panel se actualiza solo, sin reabrirlo (FR-019).

Intentar avanzar más allá de la última entrada: la respuesta tiene que ser la
misma que da la CLI, y el panel no puede quedar inconsistente.

### 4. Los estados sin review (US5 — P2)

Cinco preparaciones, cinco pantallas distinguibles:

| Estado                | Cómo preparalo                                      |
|-----------------------|-----------------------------------------------------|
| Sin review            | abrir un repositorio limpio (o `git review finish`) |
| Sin CLI               | `./uninstall.sh`, o vaciar el `PATH` del editor     |
| CLI vieja             | instalar una versión < `0.3.0`                      |
| Cursor fuera de rango | en una review walk, `git commit` sobre la base      |
| Error                 | crear una rama `review/x` a mano, sin metadata      |

Cada uno tiene que explicarse por sí solo, y los cuatro primeros ofrecer la
acción que corresponde. "Sin review" **no** puede presentarse como falla.

### 5. Sin walkthrough y walkthrough degradado (US1 — escenarios 3 y 4)

- `git review start --whole <rama>` → el panel dice que no hay walkthrough, sin
  listar entradas y sin error.
- Una review cuyo walkthrough no intersecta el rango → el panel informa que
  degradó y por qué, y la review sigue usable.

### 6. Commit por commit (US6 — P3)

```bash
git review start --step <rama>
```

El panel lista los commits en orden, marca el actual y distingue los que tienen
ediciones guardadas.

### 7. Paths raros (US2 — escenario 2)

Un walkthrough con entradas cuyos paths tengan espacios y caracteres no ASCII.
Los ítems tienen que mostrarse legibles —sin comillas ni escapes crudos— y el
clic tiene que abrir el archivo correcto. Es la prueba end-to-end de
`PathRef` (`data-model.md`).

## Suites automatizadas

```bash
npm test --prefix vscode-extension
```

Corre las dos suites descritas en la Decisión 11 de `research.md`: los
unitarios de las funciones puras (parser porcelain, des-citado de paths,
comparación de versiones, mapeo de exit codes) y los de integración con un VS
Code real sobre repos fixture construidos con la CLI. En Linux, la integración
necesita `xvfb-run`.

## Revisión manual obligatoria (SC-005)

SC-005 no se puede ejecutar: es una propiedad estructural. Antes de dar la
feature por terminada, revisar el código contra la lista de prohibiciones de
[`contracts/cli-invocation.md`](./contracts/cli-invocation.md) y confirmar que
no hay ninguna otra invocación ni ninguna lectura de config, refs o ramas para
derivar estado de review.
