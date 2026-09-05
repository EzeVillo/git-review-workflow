# Awaitable Panel Message Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminar el trabajo asíncrono residual entre specs haciendo esperable de punta a punta el despacho de mensajes del panel.

**Architecture:** `handlePanelMessage` será la única frontera de despacho y devolverá la promesa de la operación elegida. El webview consumirá esa promesa sin bloquear su listener; la API de integración la expondrá para que cada test espere comando, lock y refresco completos.

**Tech Stack:** TypeScript, VS Code Extension API, Mocha, Node.js, Git CLI.

## Global Constraints

- Trabajar directamente sobre `main`, como pidió el usuario.
- No agregar retries ni sleeps para ocultar la carrera.
- Mantener cerrado y exhaustivo el conjunto `PanelMessage`.
- No cambiar comportamiento, copy ni argv del producto.
- Cubrir los jobs de VS Code de Ubuntu, macOS y Windows mediante el mismo código compartido.

---

### Task 1: Contrato esperable y despacho completo

**Files:**
- Modify: `vscode-extension/test/integration/fixes-panel.spec.ts`
- Modify: `vscode-extension/src/extension.ts`
- Modify: `vscode-extension/src/views/walkthroughViewProvider.ts`

**Interfaces:**
- Consumes: `PanelMessage`, las funciones directas del panel y `vscode.commands.executeCommand`.
- Produces: `GitReviewTestApi.sendPanelMessage(message, extra?): Promise<void>` y un callback de provider `(message, extra?) => Promise<void>`.

- [ ] **Step 1: Escribir la prueba fallida**

En el escenario confirmado de `discardFixes`, capturar el retorno antes de esperarlo y exigir una promesa real:

```ts
const completion: unknown = api.sendPanelMessage("discardFixes", index);
assert.ok(completion instanceof Promise, "el despacho expone su finalización");
await completion;
assert.strictEqual(branchExists(repo.dir, `review-fixes/${BRANCH}`), false);
```

- [ ] **Step 2: Ejecutar el rojo**

Run: `$env:MOCHA_FILE='fixes-panel'; npm run test:integration`

Expected: FAIL en `completion instanceof Promise`, porque hoy `sendPanelMessage` devuelve `undefined`.

- [ ] **Step 3: Implementar el mínimo**

Cambiar la interfaz y el despachador:

```ts
sendPanelMessage(message: PanelMessage, extra?: unknown): Promise<void>;

async function handlePanelMessage(message: PanelMessage, extra?: unknown): Promise<void> {
    // cada rama: await operación; return
    await vscode.commands.executeCommand(commands[message], extra);
}
```

En `WalkthroughViewProvider`, aceptar `Promise<void>` y consumirla explícitamente desde el evento real:

```ts
constructor(private readonly onMessage: (message: PanelMessage, extra?: unknown) => Promise<void>) {}

void this.onMessage(type, extra);
```

Todas las ramas directas (`open/copy/start/discard` de draft, guide,
walkthrough y fixes) y todas las ramas de `executeCommand` deben esperar su
resultado antes de resolver.

- [ ] **Step 4: Ejecutar el verde**

Run: `$env:MOCHA_FILE='fixes-panel'; npm run test:integration`

Expected: `2 passing`, sin sondeos de finalización.

- [ ] **Step 5: Confirmar typecheck y tests unitarios**

Run: `npm run pretest && npm run test:unit`

Expected: typecheck verde y todos los unit tests verdes.

- [ ] **Step 6: Commit**

```bash
git add vscode-extension/src/extension.ts vscode-extension/src/views/walkthroughViewProvider.ts vscode-extension/test/integration/fixes-panel.spec.ts
git commit -m "fix(vscode): await panel message completion"
```

### Task 2: Migrar todas las specs consumidoras

**Files:**
- Modify: `vscode-extension/test/integration/draft-panel.spec.ts`
- Modify: `vscode-extension/test/integration/guide-panel.spec.ts`
- Modify: `vscode-extension/test/integration/fixes-panel.spec.ts`

**Interfaces:**
- Consumes: `GitReviewTestApi.sendPanelMessage(...): Promise<void>` de Task 1.
- Produces: specs sin operaciones mutantes fire-and-forget ni polling de su efecto final.

- [ ] **Step 1: Hacer que typecheck enumere consumidores pendientes**

Buscar cada llamada:

```powershell
rg --pcre2 -n "(?<!await )api\.sendPanelMessage" vscode-extension/test/integration
```

Expected: las llamadas actuales de draft, guide y fixes.

- [ ] **Step 2: Esperar todas las llamadas**

Cambiar cada uso a:

```ts
await api.sendPanelMessage(message, extra);
```

Mantener polling sólo cuando la prueba afirma un estado intermedio mientras una
confirmación sigue abierta. Para efectos finales, afirmar directamente después
del `await` y eliminar sleeps/loops que ya no cumplen una función semántica.

- [ ] **Step 3: Ejecutar las tres specs afectadas**

Run, una por vez:

```powershell
$env:MOCHA_FILE='fixes-panel'; npm run test:integration
$env:MOCHA_FILE='guide-panel'; npm run test:integration
$env:MOCHA_FILE='draft-panel'; npm run test:integration
```

Expected: todas verdes; ninguna promesa mutante queda sin esperar.

- [ ] **Step 4: Verificar estructuralmente la migración**

Run:

```powershell
rg --pcre2 -n "(?<!await )api\.sendPanelMessage" vscode-extension/test/integration
```

Expected: ninguna coincidencia.

- [ ] **Step 5: Commit**

```bash
git add vscode-extension/test/integration/draft-panel.spec.ts vscode-extension/test/integration/guide-panel.spec.ts vscode-extension/test/integration/fixes-panel.spec.ts
git commit -m "test(vscode): await panel actions before cleanup"
```

### Task 3: Regresión original y verificación transversal

**Files:**
- Verify: `vscode-extension/test/integration/finish-review.spec.ts`
- Verify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: la suite completa con un único fixture compartido.
- Produces: evidencia fresca de que no hay cruces entre specs en el pipeline de VS Code.

- [ ] **Step 1: Ejecutar la regresión original completa**

Run: `$env:MOCHA_FILE='finish-review'; npm run test:integration`

Expected: los 13 escenarios pasan, incluido el fixture T056 que observó `HEAD` en `main`.

- [ ] **Step 2: Ejecutar integración completa en Windows**

Run: `Remove-Item Env:MOCHA_FILE,Env:MOCHA_GREP -ErrorAction SilentlyContinue; npm run test:integration`

Expected: todas las specs verdes, incluida T056.

- [ ] **Step 3: Ejecutar gates rápidos del módulo**

Run: `npm run pretest && npm run test:unit`

Expected: compile, typecheck y unit tests verdes.

- [ ] **Step 4: Revisar el diff y el árbol**

Run: `git diff --check; git status --short; git log -3 --oneline`

Expected: sin whitespace errors; sólo cambios previstos; commits sobre `main`.
