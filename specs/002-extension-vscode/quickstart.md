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

- Muestra la primera entrada como actual, con su path legible y su *why* debajo,
  sin haber hecho nada más.
- La barra superior dice `walk`, la rama, y `1/N`.
- Si esa entrada está marcada con `> key`, el panel lo dice con texto, no sólo
  con color.
- *Ir a entrada…* abre un selector con las N entradas **en el orden del
  walkthrough**, no alfabético, con la actual marcada y preseleccionada.
- *Sin cobertura* es un acceso aparte, con la cuenta correcta, y no aparece
  mezclado con la secuencia.
- Abrir una entrada muestra el archivo con los cambios del PR, y editarlo
  modifica el working tree.

**Contrastar con la CLI** — el panel no puede decir otra cosa que esto:

```bash
git review status --porcelain
```

### 2. El porqué (US3 — P2)

Con el panel poblado: el *why* de la entrada actual ya está a la vista, con sus
saltos de línea, sin pedirlo. *Ver el porqué* lo abre como documento aparte, con
el mismo texto. Una entrada sin cuerpo lo dice, y eso no es un error; si la
invocación falla, se ve distinto de "no tiene explicación".

Al avanzar, el *why* tiene que ser el de la entrada nueva — no el anterior
quedado, ni uno en blanco permanente.

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

En la última entrada, el botón *Siguiente* tiene que verse deshabilitado (y el
de *Anterior* en la primera): un control sin destino no se ofrece. Invocar
igual el comando desde la paleta ahí tiene que mostrar el aviso de la CLI (`no
more entries — run git review finish`), nunca no hacer nada, y el panel no
puede quedar inconsistente.

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

- `git review start --no-walk <rama>` → el panel dice que no hay walkthrough, sin
  ofrecer secuencia ni navegación, y sin error.
- Una review cuyo walkthrough no intersecta el rango → el panel informa que
  degradó y por qué, y la review sigue usable.

### 6. Commit por commit (US6 — P3)

```bash
git review start --step <rama>
```

El panel muestra el commit actual con su posición; *Ir a una entrada* lista los
commits en orden y distingue los que tienen ediciones guardadas. No hay *why* en
este modo, y el panel no deja un hueco donde iría.

### 7. Paths raros (US2 — escenario 2)

Un walkthrough con entradas cuyos paths tengan espacios y caracteres no ASCII.
El panel y el selector tienen que mostrarlos legibles —sin comillas ni escapes
crudos— y abrirlos tiene que llevar al archivo correcto. Es la prueba end-to-end
de `PathRef` (`data-model.md`).

### 8. Tema y teclado (US1 — escenario 5, FR-031/SC-010)

Con el panel poblado, cambiar de tema (*Preferences: Color Theme*) a uno claro,
uno oscuro y **uno de alto contraste**: el panel tiene que seguir legible en los
tres, sin colores que se pierdan contra el fondo.

Después, sin tocar el mouse: `Tab` tiene que recorrer los botones del panel en
orden y `Enter`/`Espacio` activarlos. Y toda marca (`key`, ediciones guardadas)
tiene que ser legible como texto, no sólo como color.

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
