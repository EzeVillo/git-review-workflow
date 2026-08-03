# Feature Specification: Extensión de VS Code para revisar con walkthrough

**Feature Branch**: `002-extension-vscode`

**Created**: 2026-08-02

**Status**: Draft

**Input**: User description: "vamos avanzando entonces, te dejo que determines que de todos los
pasos siguientes queda dentro del scope de esta tarea"

## Contexto y Motivación *(el porqué)*

### El problema

El diferencial de `git review` es que el diff del PR queda en tu working tree:
editable, ejecutable, con los tests a mano. Eso ya funciona dentro de un editor
sin que el editor sepa nada del producto — VS Code muestra los cambios staged en
su panel de Source Control como mostraría cualquier otro cambio.

Lo que **no** existe dentro del editor es el walkthrough. Hoy, para revisar con
un walkthrough hay que sostener dos contextos a la vez: la terminal, que dice en
qué entrada estás y por qué el autor te pidió leer ese archivo, y el editor,
donde efectivamente leés y editás. El orden de lectura vive en una ventana y la
lectura ocurre en la otra.

### Por qué importa ahora

El walkthrough es la pieza que convierte un diff en una review guiada, y es
también la más difícil de vender: hay que instalar la CLI, aprender los verbos y
recién ahí se ve el valor. Un panel dentro del editor muestra ese valor sin
intermediarios — la primera vez que alguien ve, al lado del código, en qué
archivo está y por qué el autor le pidió leerlo, entiende el producto.

Hay además una razón de distribución: el Marketplace es un canal con audiencia
propia, y una extensión es la forma natural de que alguien descubra la CLI en
lugar de tener que buscarla.

Y hay una razón de oportunidad: el contrato porcelain
([`001-contrato-porcelain`](../001-contrato-porcelain/spec.md)) ya está
terminado y probado. Existe precisamente para que este consumidor pueda leer el
estado de una review sin parsear prosa ni duplicar el modelo de estado. Sin él
esta feature no debería intentarse; con él, es un cliente tonto de una API
estable.

### Qué habilita

Que revisar un PR con walkthrough ocurra íntegramente dentro del editor: en qué
entrada estás dentro del orden que el autor eligió, el *why* de esa entrada a la
vista, un clic para saltar al archivo, y avanzar sin cambiar de ventana.

### Qué NO es esto

- **No reemplaza a la CLI ni la duplica.** La extensión no lee config de git, no
  mueve refs y no toca el working tree por su cuenta: invoca verbos y vuelve a
  leer el estado. La CLI es la única fuente de verdad. Toda funcionalidad que
  requiera lógica nueva del lado de la extensión está fuera de esta feature por
  definición — si algo falta, se agrega a la CLI.
- **No es una interfaz de diff propia.** El editor ya sabe mostrar y editar los
  cambios de una review; la extensión no reimplementa eso. Que el panel tenga
  superficie propia de dibujo no cambia esto: mostrar cambios se sigue
  delegando en el editor.
- **No incluye los verbos consecuentes.** `finish`, `abort` y `save` cambian
  ramas y refs. El proyecto trata el riesgo de forma asimétrica, y ponerlos a un
  clic en una primera versión —donde el usuario todavía no tiene modelo mental
  de qué hace cada uno— invierte esa asimetría. La extensión indica cuál
  corresponde correr; correrlo es del usuario.
- **No incluye autoría de walkthroughs** (`walkthrough init` / `build`). Es un
  flujo de autor, no de revisor.
- **No incluye la publicación en el Marketplace** ni el release de la CLI que la
  extensión requiere. Ambos son pasos operativos con sus propias decisiones (ver
  Assumptions).

## User Scenarios & Testing *(mandatory)*

El actor de todas las historias es **el revisor**: alguien que recibió un PR y
quiere leerlo. Se asume que ya sabe iniciar una review, o que la inició desde la
terminal.

### User Story 1 - Ver dónde estoy en el walkthrough (Priority: P1)

El revisor abre en el editor un repositorio donde hay una review activa con
walkthrough. Sin escribir ningún comando, ve un panel que le dice en qué entrada
está: qué archivo, en qué posición del orden que el autor eligió, si el autor la
marcó como esencial, y —cuando la hay— la explicación que escribió para ella. La
secuencia completa está a un gesto de distancia, no ocupando el panel.

**Why this priority**: Es la feature. Todo lo demás son grados de comodidad
sobre esto. Si sólo existiera esta historia, la extensión ya resolvería el
problema de sostener dos contextos: el orden de lectura pasa a estar en la misma
ventana donde se lee.

**Independent Test**: Se abre un repositorio con una review en modo walk y se
verifica que el panel identifica la entrada actual con su posición y sus marcas,
y que desde ahí se alcanza cualquier otra entrada de la secuencia, en el orden
de la secuencia. No depende de ninguna otra historia.

**Acceptance Scenarios**:

1. **Given** una review activa en modo walk con 7 entradas, la 3ª marcada como
   esencial y el cursor en la 2ª, **When** el revisor abre el repositorio,
   **Then** el panel muestra la 2ª entrada como actual, indica que es la 2 de 7,
   y al abrir el selector de entradas aparecen las 7 en orden con la 3ª
   distinguida como esencial.
2. **Given** un walkthrough que no cubre todos los archivos del rango, **When**
   el revisor mira el panel, **Then** ve cuántos archivos del rango quedaron sin
   entrada y puede alcanzarlos por separado, sin que se mezclen con la secuencia
   del walkthrough.
3. **Given** una review activa en modo whole (sin walkthrough), **When** el
   revisor abre el repositorio, **Then** el panel indica que la review no tiene
   walkthrough, sin ofrecer una secuencia de lectura y sin presentarlo como un
   error.
4. **Given** un walkthrough que degradó a whole por estar roto o desactualizado,
   **When** el revisor mira el panel, **Then** ve que degradó y por qué, y la
   review sigue siendo usable.
5. **Given** cualquiera de los estados anteriores, **When** el revisor usa un
   tema de alto contraste o navega sólo con el teclado, **Then** el panel sigue
   siendo legible y operable, y ninguna distinción se transmite únicamente por
   color.

---

### User Story 2 - Saltar al archivo de una entrada (Priority: P1)

Desde el panel, el revisor abre el archivo de la entrada actual —o el de
cualquier otra que elija de la secuencia— y el editor lo muestra con los cambios
de la review, listo para leer y editar.

**Why this priority**: Sin esto el panel es un cartel que hay que trasladar a
mano al explorador de archivos, y el revisor sigue haciendo trabajo de
traducción. Junto con la Historia 1 forma el mínimo que justifica instalar la
extensión.

**Independent Test**: Con una review activa, abrir cada entrada desde el panel y
verificar que abre el archivo correcto y que los cambios de la review son
visibles y editables.

**Acceptance Scenarios**:

1. **Given** el panel mostrando una entrada, **When** el revisor la abre,
   **Then** el editor abre ese archivo con los cambios de la review visibles, y
   las ediciones que haga se aplican al working tree.
2. **Given** una entrada cuyo path contiene espacios o caracteres no ASCII,
   **When** el revisor la abre, **Then** abre el archivo correcto.
3. **Given** una entrada correspondiente a un archivo eliminado en el rango,
   **When** el revisor la abre, **Then** el editor muestra el estado del archivo
   sin error.

---

### User Story 3 - Leer el porqué de la entrada (Priority: P2)

El revisor lee, sin salir del editor y sin ninguna acción adicional, la
explicación que el autor escribió para la entrada en la que está.

**Why this priority**: Es el contenido que distingue a un walkthrough de una
lista de archivos — es lo que el autor quiso decir. Va después de P1 porque el
orden de lectura entrega valor aun sin los textos, pero no al revés.

**Independent Test**: Con un walkthrough cuyas entradas tienen textos conocidos,
recorrer la secuencia y verificar que en cada posición se muestra el texto de
esa entrada, con el formato preservado.

**Acceptance Scenarios**:

1. **Given** una entrada con texto explicativo de varias líneas, **When** el
   revisor está en ella, **Then** ve ese texto con sus saltos de línea y su
   formato preservados, sin los marcadores reservados del formato, sin tener que
   pedirlo.
2. **Given** una entrada sin texto, **When** el revisor está en ella, **Then**
   se le indica que no tiene explicación, sin error.
3. **Given** una explicación más larga que el espacio del panel, **When** el
   revisor quiere leerla entera, **Then** puede abrirla como documento aparte,
   con el mismo texto.

---

### User Story 4 - Avanzar y retroceder en la secuencia (Priority: P2)

El revisor termina de leer una entrada y avanza a la siguiente desde el editor.
La posición avanza igual que si hubiera corrido el verbo en la terminal, y el
panel refleja el cambio.

**Why this priority**: Elimina el último motivo para volver a la terminal
durante la lectura. Va después de P1 porque el revisor puede navegar haciendo
clic en las entradas; esta historia hace que la posición registrada acompañe.

**Independent Test**: Con una review activa, avanzar y retroceder desde el
editor y verificar contra la CLI que la posición registrada coincide.

**Acceptance Scenarios**:

1. **Given** el cursor en la entrada 2 de 7, **When** el revisor avanza, **Then**
   el panel marca la 3ª como actual, abre su archivo, y la posición consultada
   desde la terminal es la 3.
2. **Given** el cursor en la última entrada, **When** el revisor intenta
   avanzar, **Then** recibe la misma respuesta que daría la CLI, sin que el
   panel quede en un estado inconsistente.
3. **Given** el cursor en la primera entrada, **When** el revisor intenta
   retroceder, **Then** ocurre lo mismo que en el escenario anterior.
4. **Given** que el revisor corrió el verbo en la terminal en lugar de usar el
   panel, **When** vuelve al editor, **Then** el panel refleja la posición real
   sin necesidad de reabrir nada.

---

### User Story 5 - Entender por qué no hay nada que mostrar (Priority: P2)

El revisor abre un repositorio donde no hay ninguna review, o donde la CLI no
está instalada, o donde la review quedó en un estado que necesita una acción
suya. En todos los casos entiende qué pasa y qué puede hacer.

**Why this priority**: Es la primera pantalla que ve todo el mundo, incluido
quien instala la extensión sin conocer el producto. Una extensión que muestra un
error genérico en su primer uso no sobrevive a sus propias reseñas. No es P1
sólo porque no entrega valor por sí sola.

**Independent Test**: Colocar el entorno en cada estado (sin review, sin CLI,
CLI vieja, cursor fuera de rango) y verificar que el panel explica el estado y
ofrece la salida correspondiente.

**Acceptance Scenarios**:

1. **Given** un repositorio sin review activa, **When** el revisor abre el
   panel, **Then** ve que no hay ninguna review en curso, presentado como estado
   normal y no como error, junto con la forma de iniciar una.
2. **Given** que la CLI no está instalada, **When** el revisor abre el panel,
   **Then** ve que hace falta instalarla y una forma directa de hacerlo.
3. **Given** una CLI instalada anterior a la que introdujo el contrato, **When**
   el revisor abre el panel, **Then** ve que necesita actualizarla, distinguido
   del caso de ausencia.
4. **Given** una review cuyo cursor quedó fuera de rango porque el revisor
   commiteó sobre la base, **When** abre el panel, **Then** ve qué pasó y la
   acción concreta que lo resuelve, distinguido de un error irrecuperable.
5. **Given** un repositorio que no es un repositorio git, o una rama de review
   con metadata corrupta, **When** abre el panel, **Then** ve un diagnóstico que
   no promete una solución que no existe.
6. **Given** un repositorio con reviews abiertas en otras ramas, **When** el
   revisor abre el panel parado en una rama sin review, **Then** las ve listadas
   con su modo y su posición, sin tener que recordar sus nombres.
7. **Given** una review que el revisor pausó, **When** la ve listada, **Then**
   puede retomarla desde ahí, con una confirmación previa porque la acción
   cambia de rama y reordena el editor.

---

### User Story 6 - Revisar commit por commit (Priority: P3)

El revisor abre un repositorio con una review iniciada en modo step y usa el
mismo panel: cuál es el commit actual, la secuencia completa en orden a un gesto
de distancia, cuáles tienen ediciones guardadas, y la misma navegación.

**Why this priority**: El contrato ya expone este modo, así que el costo
incremental es bajo; pero el walkthrough es lo que justifica la extensión y el
modo step ya es usable desde la terminal. Es la primera historia que se recorta
si hay que recortar.

**Independent Test**: Con una review en modo step, verificar que el panel
identifica el commit actual y que la secuencia completa se alcanza en orden, con
los que tienen ediciones guardadas distinguidos.

**Acceptance Scenarios**:

1. **Given** una review en modo step de 9 commits con el cursor en el 2º y
   ediciones guardadas en el 1º, **When** el revisor abre el panel, **Then** ve
   el 2º como actual dentro de 9, y en el selector aparecen los 9 en orden con
   el 1º distinguido por tener ediciones.
2. **Given** una review en modo step, **When** el revisor abre un commit de la
   secuencia, **Then** ve los cambios de ese commit.

---

### Edge Cases

- **El estado cambia por fuera del editor.** El revisor corre verbos en la
  terminal mientras el panel está abierto: la posición avanza, la review
  termina, la rama cambia. El panel no puede quedar mostrando un estado que ya
  no existe.
- **La ventana tiene varias carpetas abiertas.** Más de un repositorio, con o
  sin review activa en cada uno. Tiene que quedar claro a qué repositorio
  corresponde lo que muestra el panel.
- **La ventana no tiene ninguna carpeta abierta.**
- **La review termina mientras el panel está abierto.** La rama deja de ser una
  rama de review y el panel tiene que volver al estado "no hay review".
- **Un path con caracteres que git cita.** El contrato entrega esos paths tal
  como git los cita; la extensión no puede mostrarlos con las comillas y los
  escapes crudos como si fueran parte del nombre.
- **Una review muy grande**, con cientos de entradas o archivos sin cobertura.
- **La CLI existe pero falla al invocarse** (permisos, PATH roto, instalación a
  medias).
- **La CLI tarda en responder** en un repositorio grande: el panel no puede
  quedar en blanco sin explicación ni bloquear el editor.
- **Varias invocaciones se solapan**: el revisor avanza dos veces seguidas antes
  de que la primera termine.

## Requirements *(mandatory)*

### Functional Requirements

#### Origen del estado

- **FR-001**: La extensión MUST obtener todo el estado de una review invocando
  los comandos de la CLI y leyendo su salida estructurada. No debe leer la
  configuración del repositorio, sus refs ni sus ramas por su cuenta para
  derivar estado de review.
- **FR-002**: La extensión MUST cambiar el estado de una review únicamente
  invocando verbos de la CLI, nunca modificando refs, configuración o el índice
  directamente.
- **FR-003**: La extensión MUST ignorar los campos adicionales al final de un
  registro conocido y los registros cuya etiqueta no reconozca, de modo que una
  CLI más nueva no la rompa.
- **FR-004**: La extensión MUST tratar cada resultado posible de una invocación
  como un estado distinto y presentarlo como tal: hay review; no hay review; el
  cursor quedó fuera de rango; error. En particular, "no hay review" no debe
  presentarse como una falla.

#### Panel

- **FR-005**: La extensión MUST mostrar un panel dedicado cuyo contenido
  principal sea la entrada actual de la secuencia de lectura: su identificador,
  sus marcas y, cuando la tenga, su explicación.
- **FR-005a**: El panel MUST dar acceso a la secuencia completa, en el orden de
  la secuencia, sin que esa lista ocupe el panel de forma permanente.
- **FR-006**: El panel MUST señalar cuál es la entrada actual, tanto en su
  contenido principal como en la lista de la secuencia.
- **FR-007**: El panel MUST distinguir las entradas que el autor marcó como
  esenciales, por un canal que no sea únicamente el color.
- **FR-008**: El panel MUST dar acceso, separados de las entradas del
  walkthrough, a los archivos que cambian en la review y no tienen entrada, e
  indicar cuántos son.
- **FR-009**: El panel MUST indicar la posición actual y el total de la
  secuencia.
- **FR-010**: El panel MUST informar cuando el walkthrough degradó, junto con el
  motivo, sin impedir el uso de la review.
- **FR-011**: El panel MUST advertir cuando el total derivado difiere del total
  registrado al iniciar la review.
- **FR-012**: El panel MUST mostrar los paths de forma legible, resolviendo el
  citado que aplica git en lugar de exhibirlo crudo.

#### Navegación

- **FR-013**: Los revisores MUST poder abrir el archivo de una entrada desde el
  panel, con los cambios de la review visibles y editables.
- **FR-014**: Los revisores MUST poder avanzar a la entrada siguiente y volver a
  la anterior desde el editor.
- **FR-015**: Al avanzar o retroceder, la extensión MUST abrir el archivo de la
  entrada resultante.
- **FR-016**: La extensión MUST propagar el resultado de un intento de navegar
  más allá de los límites de la secuencia tal como lo reporta la CLI, sin
  inventar comportamiento propio.

#### Explicaciones

- **FR-017**: El panel MUST mostrar el texto explicativo de la entrada actual sin
  que el revisor tenga que pedirlo, con su formato y sus saltos de línea
  preservados.
- **FR-017a**: Los revisores MUST poder abrir ese mismo texto como documento
  aparte, para leerlo completo sin la restricción de espacio del panel.
- **FR-018**: La extensión MUST distinguir una entrada sin texto de un fallo al
  obtenerlo.
- **FR-018a**: La extensión MUST pedir la explicación de a una entrada por vez y
  sólo cuando corresponde mostrarla; nunca las de toda la secuencia por
  adelantado.

#### Sincronización

- **FR-019**: La extensión MUST reflejar los cambios de estado producidos por
  fuera del editor sin requerir que el revisor la reinicie ni reabra el panel.
- **FR-020**: La extensión MUST evitar que dos invocaciones que cambian estado
  se solapen.

#### Requisitos previos y diagnóstico

- **FR-021**: La extensión MUST detectar que la CLI no está disponible y
  ofrecerle al revisor una forma directa de instalarla.
- **FR-022**: La extensión MUST detectar que la CLI instalada es anterior a la
  que introduce el contrato, y presentarlo como un caso distinto de su ausencia.
- **FR-023**: La extensión MUST mostrar, para el estado recuperable de cursor
  fuera de rango, la acción concreta que lo resuelve.
- **FR-024**: La extensión MUST preservar los diagnósticos que emite la CLI en
  lugar de reemplazarlos por mensajes propios genéricos.

#### Alcance por modo

- **FR-025**: La extensión MUST soportar reviews con walkthrough.
- **FR-026**: La extensión MUST informar de forma inteligible el caso de una
  review sin walkthrough, sin ofrecer una secuencia de lectura.
- **FR-027**: La extensión SHOULD soportar reviews commit por commit,
  distinguiendo los pasos que tienen ediciones guardadas.

#### Entorno

- **FR-028**: La extensión MUST funcionar en Windows, macOS y Linux.
- **FR-029**: La extensión MUST determinar sin ambigüedad a qué repositorio
  corresponde lo que muestra cuando la ventana tiene más de una carpeta abierta.
- **FR-030**: La extensión MUST permanecer utilizable mientras una invocación
  está en curso, indicando que está trabajando.
- **FR-031**: El panel MUST adoptar el tema activo del editor —incluidos los de
  alto contraste— y ser operable con el teclado, sin depender de que el revisor
  use el mouse ni de que su tema sea uno en particular.
- **FR-032**: Sin review en la rama actual, el panel MUST listar las reviews
  abiertas en el resto del repositorio —activas y pausadas— con su modo y su
  posición, tomándolas de la CLI y no de las ramas del repositorio.
- **FR-033**: La extensión MUST permitir retomar una review pausada desde ese
  listado, previa confirmación, y MUST NOT ofrecer la acción donde la CLI la
  rechazaría por una condición que el propio listado ya deja ver. Una review
  activa en otra rama se lista **sin** acción: volver a ella es cambiar de rama,
  y el editor ya tiene esa superficie.

### Key Entities

- **Estado de review**: lo que la CLI reporta sobre la review en curso — rama,
  origen, tip, modo, situación del walkthrough y, si el modo tiene cursor,
  posición, total derivado, total registrado y elemento actual.
- **Entrada de la secuencia**: una posición en el orden de lectura. Tiene un
  identificador (un archivo o un commit según el modo) y una marca propia del
  modo: esencial en walkthrough, con ediciones guardadas en commit por commit.
- **Archivo sin cobertura**: un archivo que cambia en la review y no tiene
  entrada en el walkthrough.
- **Explicación**: el texto que el autor escribió para una entrada.
- **Review del inventario**: una review que existe en otra rama del repositorio
  —activa o pausada—, con su modo y la posición que quedó registrada. Es lo
  único que el panel muestra de reviews que no son la de la rama actual.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un revisor con una review activa ve, al abrir el repositorio y sin
  escribir ningún comando, en qué entrada del walkthrough está y por qué el
  autor la incluyó.
- **SC-002**: Leer una review con walkthrough de principio a fin no requiere
  cambiar de ventana en ningún momento.
- **SC-003**: Todos los estados en los que el panel no puede mostrar una review
  —sin review, sin CLI, CLI vieja, cursor fuera de rango, metadata corrupta— se
  presentan diferenciados entre sí, y los que tienen solución la indican.
- **SC-004**: La posición y el orden que muestra el panel coinciden con lo que
  reporta la CLI en todo momento, incluido después de operar desde la terminal.
- **SC-005**: Ninguna funcionalidad del panel deriva estado de review por fuera
  de la CLI; una revisión del código lo verifica.
- **SC-006**: Una CLI más nueva que agregue campos o registros al contrato no
  degrada el panel.
- **SC-007**: Los tres sistemas operativos soportados se ejercitan
  automáticamente en cada cambio.
- **SC-008**: Un revisor que nunca usó el producto llega desde el panel a tener
  la CLI instalada sin salir del editor.
- **SC-009**: Mostrar la entrada actual con su explicación cuesta a lo sumo una
  invocación más que mostrarla sin ella, cualquiera sea el largo de la
  secuencia.
- **SC-010**: El panel se ve y se opera correctamente en los temas claro, oscuro
  y de alto contraste, sin ajustes del revisor.

## Assumptions

- **El contrato porcelain está terminado y es el único origen de estado.** Es la
  premisa de toda la feature. Si algo que el panel necesita no está en el
  contrato, se agrega al contrato — no se deriva del lado de la extensión.
- **La CLI se distribuye publicada.** La extensión requiere una versión
  publicada que incluya el contrato; la versión publicada al momento de escribir
  este spec (0.2.1) no lo incluye. Cortar ese release es un paso operativo
  previo, fuera de esta feature, pero la bloquea.
- **La extensión declara un requisito mínimo de CLI y no viaja en lockstep con
  ella.** Sus versiones son independientes: la CLI se publica en npm y Homebrew,
  la extensión en el Marketplace, con cadencias distintas.
- **La extensión convive en este repositorio, en su propio subdirectorio.** El
  contrato y su consumidor se versionan juntos para que un cambio del contrato y
  su adopción entren en el mismo cambio, igual que las dos traducciones del
  README. Su cadena de construcción queda contenida en ese subdirectorio y no
  viaja en el paquete de la CLI.
- **El editor ya provee la superficie de diff y edición.** La extensión no
  construye una propia.
- **La publicación en el Marketplace es un paso operativo posterior**, con sus
  propias decisiones (identidad del publicador, credenciales, materiales de la
  ficha). Esta feature termina con una extensión instalable localmente.
- **El revisor tiene o puede tener la CLI**; la extensión no incorpora una copia
  propia de la lógica de review para funcionar sin ella.
- **"Esencial" y "con ediciones guardadas" se muestran, no se editan.** Marcar
  una entrada como esencial es del autor del walkthrough, y es un flujo fuera de
  esta feature.
