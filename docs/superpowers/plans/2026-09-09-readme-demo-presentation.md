# README Demo Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar movimiento inmediatamente en el README principal, completar la muestra de VS Code y retirar de las superficies de marketing el video antiguo de terminal.

**Architecture:** Los GIF versionados en `docs/media/` serán la vista previa compatible con Markdown; los MP4 completos seguirán servidos por el reproductor propio de la landing. El verificador de marketing existente comprobará la reproducción y el layout; el diff y una búsqueda acotada comprobarán la presentación documental sin agregar tests que sólo congelen texto de prosa.

**Tech Stack:** Markdown, HTML/CSS/JavaScript estático, Docker y el verificador de marketing existente.

## Global Constraints

- Mantener `README.md` y `README.es.md` como traducciones espejo.
- Mantener URLs absolutas en `vscode-extension/README.md` porque se empaqueta para Marketplace.
- No modificar los MP4, GIF, pósteres de IDE ni scripts de captura y composición.
- Mantener los tres MP4 en la landing, sin autoplay y con sus pósteres estáticos.
- Retirar solamente la promoción del video de terminal; la documentación funcional de CLI y TUI queda intacta.
- Ejecutar las verificaciones dentro del contenedor del proyecto.

---

### Task 1: Línea de base de marketing

**Files:**
- Inspect: `README.md`
- Inspect: `README.es.md`
- Inspect: `vscode-extension/README.md`
- Test: `scripts/marketing/verify.cjs` mediante `scripts/marketing/run.sh --verify`

**Interfaces:**
- Consumes: los assets y `docs/index.html` montados bajo `/src`.
- Produces: evidencia de que la campaña parte de una landing y assets válidos.

- [x] **Step 1: Comprobar la línea de base antes de editar**

Run: `sh scripts/marketing/run.sh --verify`

Expected: PASS con las tres películas, los nueve GIF, ambos idiomas, los deep
links y los tres anchos responsive actuales.

- [x] **Step 2: Registrar el problema documental que se corrige**

Run: `rg -n "vscode-poster-en.png|vscode-reading-order.gif|vscode-edit-and-test.gif|vscode-finish-review.gif|LsSQtNFnjRQ" README.md README.es.md vscode-extension/README.md docs/index.html`

Expected: los README raíz muestran primero `vscode-poster-en.png`, el README de
VS Code sólo contiene `vscode-reading-order.gif` y las superficies raíz todavía
contienen `LsSQtNFnjRQ`.

### Task 2: Presentación animada en los README

**Files:**
- Modify: `README.md:22-39`
- Modify: `README.es.md:23-40`
- Modify: `vscode-extension/README.md:18-24`

**Interfaces:**
- Consumes: los nueve GIF bajo `docs/media/` y los deep links `#demo-*` de la landing.
- Produces: una muestra animada inmediata en los README raíz y un bloque de tres pasos en el README de VS Code.

- [x] **Step 1: Reemplazar el hero de ambos README raíz**

Usar `docs/media/vscode-reading-order.gif` como imagen del enlace existente a
la landing, con alt text equivalente en inglés y español. Eliminar el párrafo
que enlaza al recorrido de terminal.

- [x] **Step 2: Evitar la repetición dentro del desplegable raíz**

Renombrar el resumen a `See the workflow in each IDE` / `Mirá el flujo en cada
IDE`. Reemplazar solamente la muestra de VS Code dentro del desplegable por
`vscode-edit-and-test.gif`; conservar las muestras actuales de JetBrains y
Visual Studio.

- [x] **Step 3: Completar el README propio de VS Code**

Conservar el póster clickeable y el CTA al MP4. Reemplazar el GIF suelto por un
`<details>` equivalente a los otros dos clientes, con tres secciones:
`vscode-reading-order.gif`, `vscode-edit-and-test.gif` y
`vscode-finish-review.gif`. Usar URLs de `raw.githubusercontent.com` y textos
que describan seguir el orden, corregir/probar y extraer la corrección.

- [x] **Step 4: Ejecutar una comprobación rápida de simetría**

Run: `git diff -- README.md README.es.md vscode-extension/README.md`

Expected: los README raíz cambian en paralelo y el README de VS Code adopta el
mismo patrón de tres momentos que JetBrains y Visual Studio.

### Task 3: Landing enfocada en los IDE

**Files:**
- Modify: `docs/index.html:350-360`
- Modify: `docs/index.html:994-997`
- Modify: `docs/index.html:1326-1332`
- Modify: `CONTRIBUTING.md:311-315`
- Modify: `decisiones.md:891-897`
- Delete: `demo-poster.png`

**Interfaces:**
- Consumes: el selector y reproductor de demos existente.
- Produces: el mismo reproductor de tres clientes, sin salida promocional al video antiguo de terminal.

- [x] **Step 1: Retirar el enlace de terminal y su traducción**

Eliminar el `<a>` con `data-i18n="filmterminal"` y eliminar la entrada
`filmterminal` del diccionario español. Mantener `filmcaption` y la transcripción.

- [x] **Step 2: Limpiar CSS que sólo servía al enlace eliminado**

Quitar `.film-links a { flex-shrink: 0; }`, retirar `justify-content:
space-between` de `.film-links` y dejar el bloque de caption con su margen y
tamaño actuales. No cambiar el reproductor, sus controles ni el selector.

- [x] **Step 3: Actualizar la guía de mantenimiento y retirar el póster antiguo**

Actualizar `CONTRIBUTING.md` para describir el hero animado, los tres GIF por
cliente y la retirada del recorrido de terminal. Actualizar `decisiones.md`
para registrar el fin de la doble función histórica del póster. Eliminar
`demo-poster.png`, que pertenecía a ese recorrido y no conserva consumidores.

- [x] **Step 4: Ejecutar el verificador completo**

Run: `sh scripts/marketing/run.sh --verify`

Expected: PASS con tres películas H.264/AAC, nueve GIF válidos, ambos idiomas,
deep links funcionales y layout sin overflow.

### Task 4: Verificación final y commit

**Files:**
- Modify: `README.md`
- Modify: `README.es.md`
- Modify: `vscode-extension/README.md`
- Modify: `docs/index.html`
- Modify: `CONTRIBUTING.md`
- Modify: `decisiones.md`
- Delete: `demo-poster.png`

**Interfaces:**
- Consumes: el cambio completo.
- Produces: un commit autocontenido de la presentación de marketing.

- [x] **Step 1: Verificar referencias y formato**

Run: `rg -n "LsSQtNFnjRQ|filmterminal" README.md README.es.md docs/index.html`

Expected: exit 1 y ninguna coincidencia.

Run: `git diff --check`

Expected: exit 0 sin salida.

- [x] **Step 2: Revisar el diff final**

Run: `git diff -- README.md README.es.md vscode-extension/README.md docs/index.html CONTRIBUTING.md decisiones.md`

Expected: sólo los cambios aprobados de presentación y la documentación de mantenimiento correspondiente.

- [x] **Step 3: Crear el commit**

```sh
git add README.md README.es.md vscode-extension/README.md docs/index.html CONTRIBUTING.md decisiones.md demo-poster.png docs/superpowers/specs/2026-09-09-readme-demo-presentation-design.md docs/superpowers/plans/2026-09-09-readme-demo-presentation.md
git commit -m "docs: lead with animated IDE demos"
```
