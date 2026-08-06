# Feature Specification: Ofertas de lectura al iniciar review

**Feature Branch**: `008-start-layout-offers`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "La extensión no puede detectar qué formas de
start tiene una rama (walk, walk solo-keys, whole, step). 'Automatic' no
debería existir: hay que ofrecer walk (recomendado) solo cuando es posible,
ocultar lo imposible (p. ej. keys sin keys), reordenar el asistente para
elegir origen y rango antes de la forma de lectura, y que la CLI reporte las
ofertas reales del tip+rango sin red (el tip remoto es el tracking ref ya
fetcheado; el fetch sigue solo en start)."

## Contexto y Motivación *(el porqué)*

### El problema

Al iniciar una review desde el panel, el revisor ve siempre la misma lista
estática de “cómo leerla”: *Automatic*, commit por commit, keys only, e
ignorar el walkthrough. Esa lista **no sabe** si la rama elegida tiene
walkthrough usable, ni si hay entradas marcadas esenciales en el rango, ni si
el tip remoto local del clone siquiera existe.

Consecuencias:

- *Automatic* es opaco: puede terminar en walk o en whole sin que el revisor
  lo sepa al elegir.
- *Keys only* aparece aunque no haya keys; el rechazo llega tarde, al
  ejecutar start.
- *Ignore the walkthrough* aparece aunque no haya walkthrough que ignorar.

### Por qué importa ahora

La extensión ya ofrece layouts que dependen del contenido del PR
(walkthrough / keys). Sin un informe de **viabilidad por tip y rango**, cada
nuevo layout empeora el asistente. El submodo solo-keys y el propio walk
necesitan la misma regla que ya se usa para el rango incremental: **solo
ofrecer lo que el reporte de configuración dice que es viable**.

### Qué habilita

- Que el revisor vea, **antes de confirmar**, solo las formas de lectura
  posibles para la rama + origen + rango elegidos.
- Que walk se presenten como **recomendados** cuando son viables; que whole
  y step no lleven recomendación cuando no hay walk.
- Que la copia remota se evalúe sobre el tip de tracking **ya presente** en
  el clone (sin red en el informe); el start real sigue pudiendo actualizar
  el remoto al confirmar.

### Qué NO es esto

- **No** introduce un flag `--walk` obligatorio en la CLI de start: el start
  sin flags de layout sigue detectando walk como hoy. Cambia la **UI** del
  asistente y el **informe** de viabilidad, no el semántica bare-start de la
  CLI para uso en terminal.
- **No** hace fetch en el paso de ofertas.
- **No** hace que la extensión lea ni parsee el walkthrough.
- **No** cambia el comportamiento de una review ya activa (panel, next/prev).
- **No** añade preferencia persistente de layout.
- **No** autoría de walkthroughs desde el panel.

## User Scenarios & Testing *(mandatory)*

El actor principal es el **revisor** que inicia desde la extensión. La CLI
es la fuente de verdad del informe; un revisor en terminal puede usar el
mismo informe machine-readable si lo desea, pero no es el journey principal.

### User Story 1 - Ver solo formas de lectura posibles (Priority: P1)

El revisor elige rama, origen y (si aplica) rango. Antes de confirmar, el
asistente le muestra únicamente las formas de lectura viables para esa
combinación: walk cuando el tip tiene walkthrough usable en el rango; keys
solo si hay al menos una entrada esencial en rango; whole y step siempre que
el tip/rango sean resolubles; y no aparece una opción “automática” opaca.

**Why this priority**: sin ofertas honestas no hay producto; el resto
(recomendación, copy) cuelga de esto.

**Independent Test**: en un repo de prueba con tres ramas (sin walkthrough;
con walkthrough sin keys; con walkthrough y keys), iniciar el asistente en
cada una y verificar el conjunto exacto de opciones mostradas (sin ejecutar
start si solo se valida el listado).

**Acceptance Scenarios**:

1. **Given** una rama cuyo tip en el origen elegido no tiene walkthrough
   usable en el rango, **When** el revisor llega al paso de forma de
   lectura, **Then** ve whole y commit-por-commit, y **no** ve walk, keys
   ni “automático”.
2. **Given** una rama con walkthrough usable y cero keys en rango, **When**
   llega a forma de lectura, **Then** ve walk, commit-por-commit y whole, y
   **no** ve keys ni “automático”.
3. **Given** una rama con walkthrough usable y al menos una key en rango,
   **When** llega a forma de lectura, **Then** ve walk, keys only,
   commit-por-commit y whole.
4. **Given** el revisor eligió origen remoto y el clone **no** tiene ref de
   tracking para esa rama, **When** el asistente pide las ofertas, **Then**
   recibe un fallo claro (no se inventan opciones) y no se inicia review.
5. **Given** ofertas ya mostradas, **When** el revisor elige una y confirma
   start, **Then** la review queda en el modo correspondiente a esa opción
   (no en otro modo “automático” distinto al elegido).

---

### User Story 2 - Walk recomendado cuando es viable (Priority: P2)

Cuando walk es viable, el asistente lo marca como recomendado y lo propone
primero. Keys only, si aparece, es disponible pero no recomendado. Cuando
solo hay whole y step, ninguna opción lleva marca de recomendado.

**Why this priority**: guía al revisor hacia el orden del autor sin
esconder las demás opciones viables.

**Independent Test**: misma matrix de ramas; comprobar marca/orden de
recomendación solo en el caso con walk usable.

**Acceptance Scenarios**:

1. **Given** walk viable, **When** se muestra el paso de lectura, **Then**
   walk está marcado como recomendado y aparece de forma que el revisor lo
   vea como la opción principal (p. ej. primero / preseleccionado).
2. **Given** walk y keys viables, **When** se muestra el paso, **Then**
   keys es elegible pero **no** lleva la marca de recomendado.
3. **Given** solo whole y step, **When** se muestra el paso, **Then**
   ninguna opción está marcada como recomendada.

---

### User Story 3 - Orden del asistente: origen y rango antes de lectura (Priority: P2)

El asistente pregunta en este orden: rama → origen → rango (solo si hay
punto de referencia incremental para ese origen) → forma de lectura →
confirmación. Así las ofertas de lectura se calculan con el tip y el rango
correctos.

**Why this priority**: sin este orden las ofertas mentirían al cambiar de
remoto/local o de full/delta.

**Independent Test**: rama con walk en tip remoto y no en local (o
walkthrough que solo intersecta en full y no en delta); cambiar origen o
rango y ver que el conjunto de ofertas cambia en consecuencia.

**Acceptance Scenarios**:

1. **Given** un repositorio sin review, **When** el revisor abre start,
   **Then** el orden de pasos es rama, origen, rango (si aplica), forma de
   lectura, confirmación.
2. **Given** la misma rama con tip remoto que tiene walk usable y tip local
   que no, **When** elige origen remoto vs local, **Then** las ofertas de
   lectura difieren de forma coherente con cada tip.
3. **Given** un delta cuyo rango hace que el walkthrough no intersecte,
   **When** elige rango “solo lo nuevo”, **Then** no se ofrece walk ni keys
   (degrada a whole+step), a diferencia del rango completo si éste sí
   intersecta.

---

### User Story 4 - Tip remoto sin red en el informe (Priority: P3)

Al elegir origen remoto, las ofertas se basan en el tip de tracking ya
presente en el clone. El informe **no** actualiza el remoto. El start
confirmado con origen remoto **sí** puede actualizar el remoto como hoy; si
el tip remoto cambió entre el informe y el start, el revisor ve el resultado
real de start (notas/estado), no un segundo wizard silencioso.

**Why this priority**: cierra el contrato de honestidad con la red sin
introducir fetch en el asistente; es el matiz de producto del tip remoto.

**Independent Test**: tracking ref con walkthrough; ofertas muestran walk;
(opcional) avanzar el remoto fuera del clone y start: el resultado sigue
siendo el de la CLI tras fetch, sin que el informe haya hecho red.

**Acceptance Scenarios**:

1. **Given** origen remoto y tracking ref local con walk usable, **When**
   el asistente calcula ofertas, **Then** se ofrece walk **sin** haber
   contactado la red en ese paso.
2. **Given** ofertas calculadas y luego el remoto en el servidor cambió,
   **When** el revisor confirma start con origen remoto, **Then** start se
   comporta como la CLI actual (incluye fetch si corresponde) y el panel
   refleja el modo real post-start; no se reabre el asistente solo por el
   desfase.

---

### Edge Cases

- **Walkthrough presente pero ninguna entrada en rango** (stale / delta
  estrecho): no ofrecer walk ni keys; ofrecer whole y step.
- **Todas las entradas son key**: ofrecer walk (recomendado) y keys (sin
  recomendado); ambas son elegibles.
- **Base no configurada**: se resuelve antes de las ofertas (flujo ya
  existente); no se piden ofertas sin base cuando el rango full la necesita.
- **CLI antigua sin registro de ofertas**: el asistente no inventa walk ni
  keys; ofrece un fallback mínimo whole + step (sin recomendado) para no
  bloquear start.
- **Fallo al resolver tip** (rama local inexistente, tracking ausente): error
  visible; no start.
- **Cancelación en cualquier paso**: no mutación; no review creada.
- **Compare y review ya activa**: fuera de alcance de esta feature.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Antes de mostrar la forma de lectura, el sistema MUST obtener
  del reporte de configuración las formas de lectura **viables** para la
  combinación rama + origen + rango ya elegidos por el revisor.
- **FR-002**: El sistema MUST NOT ofrecer una forma de lectura que el
  informe no marque como viable (ocultar lo imposible).
- **FR-003**: El sistema MUST NOT presentar una opción “automática” u otra
  etiqueta que oculte si el resultado será walk o whole.
- **FR-004**: Cuando el walkthrough del tip es usable en el rango, el
  informe MUST incluir walk como viable y MUST marcarlo como la única
  forma recomendada.
- **FR-005**: Keys only MUST ser viable solo si walk es viable y existe al
  menos una entrada esencial en rango; MUST NOT llevar marca de
  recomendado.
- **FR-006**: Whole y commit-por-commit MUST ser viables siempre que el tip
  y el rango sean resolubles; cuando walk no es viable, whole y step MUST
  aparecer sin marca de recomendado.
- **FR-007**: Cuando walk es viable, la opción de revisar el diff entero
  MUST seguir existiendo como whole (equivalente de “ignorar el orden de
  lectura”), no como un nombre distinto opaco.
- **FR-008**: El asistente de inicio MUST pedir las decisiones en orden:
  rama → origen → rango (condicional) → forma de lectura → confirmación.
- **FR-009**: El cálculo de ofertas para origen remoto MUST usar el tip de
  tracking ya presente en el repositorio local y MUST NOT realizar acceso
  de red. El start confirmado con origen remoto MAY actualizar el remoto
  como hoy.
- **FR-010**: La extensión MUST NOT leer ni interpretar el archivo de
  walkthrough ni claves crudas de configuración de git para decidir
  ofertas; MUST basarse en el informe de la CLI.
- **FR-011**: La confirmación de start MUST nombrar la forma de lectura
  elegida en lenguaje claro (walk / keys only / commit-por-commit /
  whole), sin “automatically…”.
- **FR-012**: Si el informe de ofertas falla, el sistema MUST mostrar el
  diagnóstico y MUST NOT iniciar la review.
- **FR-013**: Si la CLI no emite ofertas (versión antigua), el asistente
  MUST degradar a whole + step sin recomendado y MUST NOT ofrecer walk ni
  keys inventados.
- **FR-014**: Al confirmar, el start invocado MUST corresponder de forma
  unívoca a la opción elegida (mismo resultado de modo que el revisor
  esperaba al ver el listado).

### Key Entities

- **Oferta de lectura**: una forma viable de iniciar (walk, keys, step,
  whole), con opcional marca de recomendado. Se deriva del tip y del rango;
  no se persiste.
- **Contexto de ofertas**: rama + origen (remoto / local / sin red) + rango
  (completo / solo lo nuevo). Determina qué tip y qué lower bound usa el
  informe.
- **Intento de inicio (intent)**: rama, origen, rango y forma de lectura
  elegidos; se traduce a la invocación de start tras confirmación.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: En una matrix de al menos tres ramas de prueba (sin walk; walk
  sin keys; walk con keys), el 100% de las opciones mostradas en el paso de
  lectura son viables y el 100% de las opciones inviables están ocultas.
- **SC-002**: En el 100% de los casos con walk viable, el revisor ve walk
  como recomendado y no ve la etiqueta “automático”.
- **SC-003**: Un revisor completa el asistente (rama → … → confirmación)
  eligiendo una forma de lectura y obtiene esa forma en la review iniciada,
  en un solo flujo sin reintentos por opción imposible.
- **SC-004**: El paso que calcula ofertas con origen remoto no realiza
  acceso de red (verificable por instrumentación o por ausencia de fetch en
  el informe); un start remoto posterior puede seguir actualizando el
  remoto.
- **SC-005**: Tras desplegar la feature, cero caminos del asistente ofrecen
  keys only cuando el informe indica cero keys en rango.

## Assumptions

- Las decisiones de producto ya acordadas: recomendar + ocultar lo
  imposible; solo walk es recomendado; sin walk → whole+step sin
  recomendado; un solo concepto “whole” (no “no-walk” como nombre de
  producto); orden rama → origen → rango → lectura; informe sin red.
- El tip remoto del informe es el tracking ref del remoto configurado (p.
  ej. `origin/<rama>` o el remote efectivo del producto), igual que el
  listado de candidatas ya asume refs locales.
- Un desfase entre informe (sin fetch) y start (con fetch en remoto) es
  aceptable y se resuelve con el resultado real de start + notas de la CLI,
  no con un segundo asistente.
- El feature `007-walk-keys-only` (o equivalente) ya expone keys en start
  de CLI y el significado de “entrada esencial”; esta feature no redefine
  el submodo, solo cuándo ofrecerlo.
- `config --porcelain` sigue siendo el canal machine-readable de
  “qué hay disponible antes de una review”; las ofertas son aditivas a ese
  canal.
- No se requiere cambiar la landing ni la autoría de walkthroughs.
- Documentación de producto (README EN+ES) se actualiza si el asistente o
  el contrato de config cambian la superficie descrita; la landing solo si
  toca una de las cuatro superficies duplicadas (no aplica a este feature).
