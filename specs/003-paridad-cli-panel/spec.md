# Feature Specification: Paridad de información entre la CLI y el panel del editor

**Feature Branch**: `003-paridad-cli-panel`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "quiero agregar que todo lo q se ve en la cli se vea también
en la extensión"

## Contexto y Motivación *(el porqué)*

### El problema

La extensión ([`002-extension-vscode`](../002-extension-vscode/spec.md)) se
diseñó alrededor del walkthrough, y ahí la paridad es completa: lo que la
terminal imprime al pararse en una entrada —la posición, el path, la marca de
esencial, el *why* del autor— es exactamente lo que el panel muestra.

En los otros dos modos no. Una review commit por commit imprime en la terminal
el asunto del commit y quién lo escribió; el panel muestra un identificador de
siete caracteres y nada más. Una review sin walkthrough imprime la base contra
la que se armó el rango; el panel no la menciona. Y en los tres modos la
terminal dice de qué PR es la review y sobre qué punto quedó fijada, dato que el
panel tiene a mano y no dibuja.

El resultado es que el revisor que eligió commit por commit sigue necesitando la
terminal para saber qué está mirando — el mismo problema de sostener dos
contextos que la extensión existe para eliminar, sólo que corrido de modo.

### Por qué importa ahora

Porque el hueco no viene de una decisión sino de un ángulo muerto. La pregunta
abierta que definió el alcance del modo commit por commit en el contrato
([Q2 de `001-contrato-porcelain`](../001-contrato-porcelain/spec.md)) ofrecía
tres opciones —sin secuencia, con secuencia, con secuencia y ediciones
guardadas— y se eligió la más amplia. Ninguna de las tres mencionaba el
contenido del commit: no se descartó, no se discutió. El requisito que cubre ese
modo en la extensión quedó además como SHOULD, y el modo entero como "la primera
historia que se recorta".

Con las dos features construidas, el hueco es visible y barato de cerrar: todo
el dato que se agrega ya se calcula para imprimirlo en pantalla, y el contrato
se diseñó explícitamente para admitir campos nuevos sin romper a nadie.

### Qué habilita

Que la elección de modo deje de determinar cuánto sirve el panel. Un revisor que
abre una review commit por commit ve qué commit está revisando y quién lo
escribió, igual que lo vería en la terminal, sin cambiar de ventana.

### Qué NO es esto

- **No cambia lo que la CLI muestra.** Esta feature observa la salida humana
  existente y la hace alcanzable por un programa. No agrega, reordena ni
  reescribe nada de lo que hoy se imprime en pantalla.
- **No mueve estado a la extensión.** Todo dato nuevo sale de la CLI. La premisa
  de la feature anterior sigue intacta: si algo falta, se agrega al contrato.
- **No es una interfaz de diff propia.** Sigue vigente la exclusión de `002`:
  mostrar los cambios de un commit se delega en el editor.
- **No toca el modo con walkthrough**, que ya tiene paridad. Lo único que puede
  cambiar ahí es lo que es común a los tres modos.
- **No incluye el cuerpo del mensaje de un commit.** Sólo el asunto (Q3). El
  cuerpo es prosa de largo arbitrario y necesitaría una superficie nueva; queda
  como exclusión registrada.
- **No convierte la paridad en una garantía permanente.** Esta feature cierra el
  hueco que hay hoy; no instala ningún mecanismo que impida volver a abrirlo
  (Q1).
- **No incluye los verbos consecuentes.** `finish`, `abort` y `save` siguen
  fuera por la misma asimetría de riesgo que los dejó afuera de `002`.

## User Scenarios & Testing *(mandatory)*

El actor de las dos historias es **el revisor**.

### User Story 1 - Saber qué commit estoy revisando (Priority: P1)

El revisor tiene una review commit por commit abierta en el editor. El panel le
dice, además de la posición y el identificador del commit, **qué hace ese commit
y quién lo escribió** — lo mismo que leería en la terminal al pararse ahí.

**Why this priority**: Es el hueco. Un identificador de siete caracteres no le
dice a nadie qué está por revisar; es la única pieza sin la cual el panel no
sustituye a la terminal en este modo. Si sólo existiera esta historia, el modo
commit por commit ya sería usable sin cambiar de ventana.

**Independent Test**: Con una review commit por commit sobre commits de asunto y
autor conocidos, verificar que el panel muestra el asunto y el autor del commit
en el que está el cursor, y que al moverse muestra los del commit nuevo. No
depende de la otra historia.

**Acceptance Scenarios**:

1. **Given** una review commit por commit con el cursor en un commit cuyo asunto
   y autor se conocen, **When** el revisor abre el panel, **Then** ve ese asunto
   y ese autor junto a la posición y el identificador.
2. **Given** el mismo estado, **When** el revisor avanza al commit siguiente,
   **Then** el panel muestra el asunto y el autor del commit nuevo, sin quedar
   mostrando los del anterior.
3. **Given** una review commit por commit, **When** el revisor abre el selector
   de la secuencia, **Then** cada commit se identifica por su asunto y no sólo
   por su identificador.
4. **Given** un commit cuyo asunto o cuyo autor contienen caracteres no ASCII,
   **When** el revisor lo mira en el panel, **Then** los ve tal como los escribió
   quien lo hizo, sin escapes ni sustituciones.
5. **Given** un commit cuyo mensaje tiene cuerpo además del asunto, **When** el
   revisor lo mira en el panel, **Then** ve el asunto, y la ausencia del cuerpo
   no se presenta como un dato faltante ni como un error.

---

### User Story 2 - Reconocer de qué review se trata (Priority: P2)

El revisor mira el panel y sabe **de qué PR** es la review y **sobre qué punto**
quedó fijada; y si la review no tiene walkthrough, contra qué base se armó su
rango. Es lo que encabeza la salida de la terminal en los tres modos.

**Why this priority**: Es lo primero que la CLI imprime y lo único que responde
"¿esto es lo que creo que es?" — importa sobre todo con varias reviews abiertas
o al volver a una después de un rato. Va después de P1 porque el revisor puede
inferirlo del nombre de la rama, aunque no siempre.

**Independent Test**: Con reviews en los tres modos, verificar que el panel
identifica el origen y el punto fijado, y que en una review sin walkthrough
también muestra la base. Buena parte de este dato ya llega al panel sin cambiar
la CLI, así que la historia se puede probar por partes.

**Acceptance Scenarios**:

1. **Given** una review activa en cualquiera de los tres modos, **When** el
   revisor abre el panel, **Then** ve de qué origen es la review y sobre qué
   punto quedó fijada.
2. **Given** una review sin walkthrough, **When** el revisor abre el panel,
   **Then** ve además la base contra la que se armó el rango.
3. **Given** una review sin walkthrough donde no hay base registrada, **When** el
   revisor abre el panel, **Then** la ausencia no se muestra como un valor vacío
   ni como un error.

---

### Edge Cases

- **Un asunto muy largo**, o más largo que el ancho del panel.
- **Asuntos y autores con caracteres no ASCII, acentos o emojis** — el proyecto
  ya arrastra tres incidentes de bytes invisibles en paths, y ésta es una
  superficie nueva con el mismo riesgo.
- **Un autor cuyo nombre contiene el separador de campos** de la salida
  estructurada: a diferencia de un path, un nombre de autor **no** tiene la
  garantía de git de estar libre de bytes de control.
- **Un asunto vacío** (un commit cuyo mensaje es sólo cuerpo, o directamente
  vacío): la ausencia no puede confundirse con un dato que la CLI no provee.
- **Una review con cientos de commits**: el asunto y el autor de todos ellos en
  una sola respuesta cambian el tamaño de esa respuesta y el trabajo de
  producirla.
- **Una CLI anterior a esta feature con una extensión posterior**: el panel no
  puede romperse ni mostrar huecos como si fueran datos.
- **Una CLI posterior con una extensión anterior**: tiene que seguir funcionando
  igual que hoy.
- **Una review sin walkthrough en un repositorio sin base configurada.**
- **El asunto de un commit cambia por fuera del editor** (se reescribe la rama):
  el panel no puede quedar mostrando el asunto viejo.

## Requirements *(mandatory)*

### Functional Requirements

#### Origen del estado

- **FR-001**: Todo dato que esta feature agregue al panel MUST obtenerse
  invocando la CLI y leyendo su salida estructurada. La extensión MUST NOT
  derivarlo por su cuenta del repositorio, aunque el dato sea obtenible ahí.
- **FR-002**: La información que se agregue a la salida estructurada MUST ser
  aditiva: un consumidor construido contra el contrato anterior MUST seguir
  funcionando sin cambios.
- **FR-003**: La extensión MUST degradar de forma legible cuando la CLI instalada
  no provea los datos nuevos, mostrando lo que hoy muestra en lugar de huecos,
  valores vacíos o errores.
- **FR-004**: La extensión MUST distinguir un dato ausente porque la CLI no lo
  provee de un dato ausente porque no existe.

#### Contenido del panel

- **FR-005**: En una review commit por commit, el panel MUST identificar el
  commit actual por su asunto además de por su identificador.
- **FR-006**: En una review commit por commit, el panel MUST mostrar quién
  escribió el commit actual.
- **FR-007**: En una review commit por commit, la lista de la secuencia MUST
  identificar cada commit por su asunto además de por su identificador.
- **FR-008**: El panel MUST mostrar, en los tres modos, el origen de la review y
  el punto sobre el que quedó fijada.
- **FR-009**: En una review sin walkthrough, el panel MUST mostrar la base contra
  la que se armó el rango cuando la hay, y MUST NOT mostrar nada en su lugar
  cuando no la hay.
- **FR-010**: Todo texto que provenga de un commit MUST mostrarse tal como lo
  escribió su autor, sin escapes ni sustituciones visibles.

#### Integridad de la salida estructurada

- **FR-011**: Un valor que contenga el separador de campos u otros bytes de
  control MUST NOT poder partir un registro ni desplazar los campos que le
  siguen.
- **FR-012**: La forma de identificar un dato en la salida estructurada MUST
  permanecer estable cuando se agreguen datos nuevos, sin que la posición de un
  campo existente dependa de cuáles otros estén presentes.

#### Costo

- **FR-013**: Mostrar la entrada actual con todo lo que esta feature agrega MUST
  NOT costar ninguna invocación de la CLI adicional respecto de mostrarla sin
  ello.
- **FR-014**: Consultar el estado de una review de decenas de commits MUST
  completarse lo bastante rápido como para no percibirse como demora al navegar,
  igual que hoy.

#### Alcance de la paridad

- **FR-015**: Todo dato que la CLI muestre en pantalla sobre el estado de una
  review y que esta feature no exponga MUST quedar registrado como exclusión con
  su motivo, de modo que un hueco se distinga de una decisión.

### Key Entities

- **Commit de la secuencia**: una posición en una review commit por commit. Hoy
  se identifica sólo por su identificador abreviado; esta feature le suma lo que
  lo hace reconocible — su asunto y quién lo escribió.
- **Encabezado de la review**: los datos comunes a los tres modos que la CLI
  imprime antes que nada — origen, punto fijado y, sin walkthrough, la base.
- **Exclusión deliberada**: un dato que la CLI muestra y que se decide no
  exponer, con el motivo registrado. Esta feature registra dos: la lista de
  archivos que toca un commit y el cuerpo del mensaje de un commit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un revisor con una review commit por commit sabe, sin escribir
  ningún comando ni cambiar de ventana, qué hace el commit en el que está y quién
  lo escribió.
- **SC-002**: Todo dato que la CLI imprime sobre el estado de una review está
  disponible en el panel o registrado como exclusión con su motivo; no queda
  ninguno sin clasificar.
- **SC-003**: Recorrer una review commit por commit de principio a fin no
  requiere cambiar de ventana en ningún momento, igual que ya ocurre con una
  review con walkthrough.
- **SC-004**: Una CLI anterior a esta feature deja el panel exactamente como está
  hoy, sin errores ni campos vacíos, y una CLI posterior no rompe a un consumidor
  construido contra el contrato anterior.
- **SC-005**: Mostrar la entrada actual completa cuesta exactamente las mismas
  invocaciones que antes de esta feature.
- **SC-006**: Un asunto o un autor con caracteres no ASCII producen en el panel
  exactamente el mismo texto que la terminal, byte a byte.
- **SC-007**: Un valor que contenga el separador de campos no altera la
  interpretación de ningún otro dato del estado.
- **SC-008**: Consultar el estado de una review de 50 commits no se percibe como
  demora al navegar.

## Assumptions

- **La salida humana de la CLI es la referencia de la paridad, y no cambia.**
  Esta feature la toma como está: lo que se muestra en pantalla define qué tiene
  que estar disponible, no al revés.
- **El contrato es el único origen de estado**, igual que en `002`. Lo que el
  panel necesite y no esté en el contrato se agrega al contrato.
- **La paridad no se custodia** (Q1). Es un estado que se alcanza en esta
  feature, no una invariante del proyecto: nada impide que una feature futura
  agregue algo a la salida humana y no a la estructurada, y eso es aceptable por
  ahora.
- **El modo con walkthrough ya tiene paridad** y no se revisa, salvo por lo que
  es común a los tres modos.
- **Mostrar los cambios de un commit se sigue delegando en el editor.** La
  exclusión de `002` sigue vigente y esta feature no la reabre.
- **La extensión y la CLI no viajan en lockstep.** La extensión declara un
  requisito mínimo de CLI; los datos que esta feature agrega llegan en una
  versión posterior a ese mínimo, así que convivir con una CLI que no los provee
  es un estado normal y no un error.
- **Los datos que se agregan ya se calculan hoy** para imprimirlos en pantalla:
  no se persiste estado nuevo ni se agregan claves de configuración.
- **El asunto de un commit es una sola línea.** Es lo que lo hace apto para
  viajar en la salida estructurada sin superficie nueva, y es la razón por la
  que el cuerpo queda afuera.

## Preguntas resueltas

Las tres decisiones de alcance que el spec dejó abiertas, con la respuesta que
se tomó.

### Q1: ¿Cómo se custodia que la paridad no se vuelva a perder?

**Context**: cerrar el hueco hoy no impide reabrirlo en la próxima feature — que
es exactamente cómo se llegó acá.

| Option | Answer                                                      | Implications                                                                                                         |
|--------|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| A      | Convención escrita, sin automatización                      | Costo cero, mismo mecanismo que la regla de los dos README. Depende de que alguien la recuerde.                       |
| B      | Test automático que compara ambas salidas                   | Falla sola al desincronizarse, pero comparar prosa contra registros se rompe al reescribir un mensaje humano.         |
| C      | Inventario asentado + test acotado a ese inventario         | El test verifica que cada dato inventariado siga en ambas salidas; un dato nuevo hay que agregarlo al inventario.     |
| Custom | Sin custodia: por ahora la paridad se puede romper          | Alcance mínimo. La paridad es un estado alcanzado, no una invariante. Se cae la historia que la custodiaba.           |

**Your choice**: Custom — sin custodia. La paridad se puede romper.

### Q2: ¿La lista de archivos que toca un commit entra en el alcance?

**Context**: la CLI imprime el diffstat al pararse en un commit; el panel no lo
muestra, pero su botón de cambios ya abre esos mismos archivos con la superficie
nativa del editor.

| Option | Answer                                                      | Implications                                                                                                         |
|--------|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| A      | Exclusión deliberada, con el motivo registrado              | Paridad de información, no de píxeles. Respeta la exclusión de interfaz de diff propia heredada de `002`.             |
| B      | Entra: el panel muestra el diffstat como texto              | Paridad literal, a cambio de duplicar una superficie que el editor ya resuelve mejor.                                 |
| C      | Entra sólo el resumen numérico                              | Un dato de una línea que da idea del tamaño del commit sin duplicar la lista.                                        |

**Your choice**: A — exclusión.

### Q3: ¿Por dónde se lee el mensaje del commit?

**Context**: el asunto es una sola línea; el cuerpo es prosa de largo
arbitrario, que el contrato mantiene fuera de sus registros por diseño.

| Option | Answer                                                      | Implications                                                                                                         |
|--------|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| A      | Sólo el asunto; el cuerpo queda fuera                       | Cero invocaciones extra y ninguna superficie nueva. Pierde el porqué que el autor haya escrito en el cuerpo.          |
| B      | Asunto y cuerpo, ambos en el panel                          | Máxima paridad, a cambio de una invocación nueva y de una decisión sobre la superficie que hoy sólo aplica a walk.    |
| C      | Asunto en el panel, cuerpo como documento aparte            | Espeja cómo `002` resolvió la explicación larga; misma invocación nueva que B, pagada sólo cuando se pide.            |

**Your choice**: A — sólo el asunto.
