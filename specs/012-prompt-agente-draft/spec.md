# Feature Specification: El borrador del revisor, escrito por un agente

**Feature Branch**: `012-prompt-agente-draft`

**Created**: 2026-08-18

**Status**: Draft

**Input**: User description: "El borrador del revisor está pensado para que lo
complete un agente de IA, pero hoy ni el archivo ni los clientes le dan al
agente lo que necesita, y el flujo en las extensiones es malo. El esqueleto
tiene que ubicar el cambio (rango real, cómo ver el contenido del PR), tienen
que existir superficies que no obliguen al agente a escribir dentro de `.git/`,
y el borrador tiene que ser visible y accionable en los clientes: la ruta en el
informe de estado, una situación del panel persistente, copiar al portapapeles
una instrucción corta para el agente, y renombrar la oferta para que comunique
valor. El prompt vive en el archivo del walkthrough, no en un generador aparte.
El hand-off es sólo portapapeles."

## Contexto y Motivación *(el porqué)*

### El problema

La feature 011 le dio al revisor **dónde** escribir su orden de lectura. No le
dio a nadie **con qué** escribirlo.

El esqueleto que produce `git review walkthrough draft` está redactado como
consigna para quien anota el PR —y los dos README dicen explícitamente que
completarlo «es un gran encaje para un agente de programación»—, pero el
esqueleto no dice qué es el PR. Nombra la rama y lista los archivos, y del
rango dice literalmente las palabras «base..tip». No hay ahí un rango que se
pueda resolver, ni una forma de ver el contenido de los archivos que lista.

Eso importa porque **el revisor está parado en la rama base**. Los archivos que
el esqueleto lista existen en su árbol de trabajo, pero con el contenido
*anterior* al PR. Un agente que hace lo único razonable —abrir los archivos que
el archivo le nombra— lee la versión vieja y escribe *whys* verosímiles y
equivocados. No falla: escribe algo plausible sobre código que el PR ya cambió.
Nada en el producto detecta eso, y `draft --build` tampoco: valida la forma y
el conjunto de rutas, nunca el contenido de la prosa.

A eso se suman tres paredes más:

| Lo que el agente necesita | Por qué hoy no lo tiene |
| --- | --- |
| Saber qué rango mirar | El archivo dice la palabra «base..tip»; los SHA reales existen en la CLI y no salen a ningún lado |
| Ver el contenido del PR | El árbol de trabajo tiene la versión base; nadie le dice cómo obtener la otra |
| Escribir el resultado | El único destino es un archivo dentro del directorio de git, y muchas sandboxes de agente se niegan a escribir ahí |
| Saber dónde está ese archivo | La única ruta que el producto imprime lleva la variable `GIT_DIR` sin expandir, y en los clientes la ruta aparece **sólo** cuando el editor no pudo abrir el archivo |

Y del lado de los clientes, el borrador **no existe como cosa**. Existe como un
paso interno del asistente de inicio: se elige una opción llamada *Walkthrough —
draft one*, se abre un archivo, y queda una notificación esperando. Si el
revisor cierra el IDE con el borrador a medio llenar, el borrador desaparece de
toda la interfaz: el panel no lo menciona, el inventario de reviews no lo
menciona, y la única forma de volver a él es reabrir el asistente y volver a
elegir la misma rama. Un trabajo que puede llevar minutos —el tiempo que un
agente tarda en leer un PR entero— cuelga de una notificación.

### Por qué importa ahora

El orden de lectura guiado es lo único que el producto ofrece y que git y
GitHub no tienen. Que dependa de que alguien lo escriba a mano es exactamente
lo que 011 vino a resolver del lado del revisor, y lo resolvió a medias: le dio
un lugar al archivo y no le dio un camino al que lo escribe.

Un revisor humano no puede curar el orden de lectura de un PR que todavía no
leyó —para eso tendría que haberlo leído, que es lo que el orden viene a
facilitar—. Un agente sí: puede leer el diff entero y escribir el orden *antes*
de que el revisor abra el primer archivo. Ese es el caso que vuelve útil a la
feature entera, y hoy es justamente el que peor funciona.

### Qué habilita

- Que un agente pueda completar el borrador **correctamente**, porque el
  archivo le dice qué rango mirar y cómo ver el contenido real del PR.
- Que el agente no tenga que escribir dentro del directorio de git: puede
  recibir el esqueleto por la salida estándar y devolver el resultado por un
  archivo cualquiera o por la entrada estándar.
- Que un borrador a medio escribir sea **visible y accionable** desde el panel,
  sin reabrir ningún asistente.
- Que pasarle el trabajo a un agente sea copiar una línea al portapapeles.

### Qué NO es esto

- **No** es una integración con IA. Sigue sin haber elección de modelo, ni
  credenciales, ni red, ni envío del diff a ningún lado. El único hand-off es
  el portapapeles.
- **No** verifica la *calidad* de lo que el agente escribe. No hay forma de
  hacerlo y no se intenta: la validación sigue siendo de forma y de conjunto de
  rutas, exactamente la que ya existe.
- **No** hay un generador de prompts aparte. La consigna vive en el propio
  archivo del walkthrough; lo que se copia al portapapeles es a lo sumo «seguí
  los pasos de este archivo».
- **No** cambia el flujo del autor: `walkthrough init` y `build` sobre el
  sidecar commiteado siguen igual, salvo por lo que compartan del esqueleto y
  por el bloque de instrucciones, que la construcción pasa a conservar en vez de
  descartar (sin que llegue a mostrarse ni a renderizarse en el PR).
- **No** cambia dónde vive el borrador ni su ciclo de vida: la ruta canónica
  dentro del directorio de git, la precedencia sobre el walkthrough del autor,
  el archivado al pausar, el barrido de `forget` y el guard de metadata al
  finalizar quedan todos exactamente como están.
- **No** publica el borrador al PR ni se lo propone al autor.
- **No** ejecuta comandos por el agente ni los ejecuta el producto: lo que se
  escribe en el archivo son instrucciones para que las corra quien anota.

## Clarifications

### Session 2026-08-19

- Q: ¿De dónde salen otra vez las instrucciones para el agente cuando hay que
  reanotar un borrador ya instalado? → A: Sobreviven dentro del propio archivo
  como un bloque de comentario reconocido: la construcción lo conserva al
  reescribir y la lectura lo sigue filtrando, así que nunca se le muestra al
  revisor ni se renderiza en el PR del autor (FR-007, FR-013a, FR-019).
  *(Refinado durante el plan: la construcción lo conserva **regenerándolo** con
  el rango que acaba de validar, en lugar de arrastrar el entrante. Entrega el
  mismo beneficio y elimina el costo que esta respuesta había aceptado —«que las
  instrucciones envejezcan con el rango»—, con menos código. Ver `research.md`
  § Decisión 4.)*
- Q: ¿Dónde reporta la CLI la existencia, la ruta y el progreso de un borrador
  que todavía no tiene review? → A: En la superficie de configuración y arranque
  que el cliente ya consulta sin review y sin nombrar una rama; el informe de
  estado sigue reportando sólo el borrador en vigor de una review activa
  (FR-020, FR-021, US3 escenario 7).
- Q: Con dos o más borradores a medio escribir y ninguna review activa, ¿qué
  muestra el panel? → A: Todos, como una fila por borrador con su progreso y sus
  acciones; el reporte de la CLI emite un registro por borrador (FR-021,
  FR-025, FR-026, SC-006).
- Q: ¿El estado de borrador pendiente reemplaza el cuerpo del panel sin review o
  convive dentro de él? → A: Es un bloque propio arriba del cuerpo de siempre,
  que sigue entero: el inventario de reviews y arrancar una review quedan
  accesibles (FR-025).
- Q: ¿Qué cuenta como entrada anotada para el progreso? → A: Sólo la que tiene
  las dos marcas de posición resueltas — posición de lectura puesta y *why*
  escrito (FR-022, SC-013).

## User Scenarios & Testing *(mandatory)*

El actor principal sigue siendo el **revisor**, pero esta vez hay un segundo
actor de hecho: el **agente** que el revisor pone a completar el borrador. El
agente no es usuario del producto —no aprende comandos, no lee documentación—;
sólo lee el archivo que se le da y hace lo que ahí dice. Todo lo que el agente
necesita saber tiene que estar en ese archivo.

### User Story 1 - El esqueleto ubica el cambio (Priority: P1)

Un revisor parado en la rama base pide el esqueleto del orden de lectura para
un PR de 14 archivos y se lo pasa a su agente. El agente abre el archivo, y ahí
encuentra —además de la lista de archivos y la consigna de siempre— el rango
concreto que el orden tiene que cubrir y la forma exacta de ver el contenido
del PR sin depender del árbol de trabajo. Escribe los *whys* sobre el código
que el PR realmente introduce, no sobre el que había antes.

**Why this priority**: Es la corrección de un error silencioso. Hoy el flujo
"funciona" y produce prosa equivocada, que es peor que fallar. Todo lo demás de
esta feature es comodidad; esto es corrección.

**Independent Test**: Generar el esqueleto para un PR que *modifica* un archivo
existente (no que lo agrega), comprobar que el archivo nombra un rango
resoluble y una forma de obtener el contenido del PR, y que seguir esas
instrucciones al pie devuelve el contenido posterior al PR y no el del árbol de
trabajo.

**Acceptance Scenarios**:

1. **Given** un revisor parado en la rama base, **When** genera el esqueleto
   para una rama, **Then** el archivo identifica el rango de la review con
   referencias que git puede resolver en ese repositorio, no con palabras
   genéricas.
2. **Given** ese esqueleto, **When** quien lo completa sigue las instrucciones
   que trae para ver un archivo listado, **Then** obtiene el contenido tal como
   queda después del PR, y no el que tiene el árbol de trabajo.
3. **Given** un esqueleto generado para el rango incremental (sólo los commits
   nuevos desde la review anterior), **When** quien lo completa sigue sus
   instrucciones, **Then** ve únicamente los cambios de ese rango incremental y
   no el PR entero.
4. **Given** un esqueleto generado desde adentro de una review activa, donde el
   árbol de trabajo **sí** tiene el contenido del PR, **When** quien lo completa
   lo lee, **Then** las instrucciones del archivo describen esa situación y no
   la contraria.
5. **Given** un rango cuyo límite inferior no es un commit sino un estado
   sintético (porque la rama base fue mergeada dentro del PR), **When** quien
   completa el borrador sigue las instrucciones del archivo, **Then** funcionan
   igual, sin errores de sintaxis de rango.

---

### User Story 2 - El agente no escribe dentro del directorio de git (Priority: P1)

Un revisor le pasa el trabajo a un agente que corre en una sandbox que sólo lo
deja escribir en el árbol del proyecto. El agente obtiene el esqueleto por la
salida estándar, escribe el resultado en un archivo temporal cualquiera, y una
única invocación lo valida y lo instala como borrador de esa rama. El revisor
arranca la review y entra en modo walk.

En ningún momento el agente tocó nada dentro del directorio de git, y el
borrador quedó exactamente donde el resto del producto lo busca.

**Why this priority**: Sin esto, la historia 1 se queda en el papel para una
buena parte de los agentes reales. Y es la que hace que el trabajo se pueda
hacer de una sola pasada, sin ida y vuelta de archivos.

**Independent Test**: Obtener el esqueleto sin que se cree ningún archivo,
completarlo fuera del directorio de git, instalarlo con una sola invocación, y
comprobar que la review entra en modo walk con ese orden y que todas las
superficies de custodia (estado, inventario, pausar, retomar, descartar) lo
tratan igual que a un borrador escrito en el lugar.

**Acceptance Scenarios**:

1. **Given** una rama sin borrador, **When** el revisor pide el esqueleto para
   verlo por la salida estándar, **Then** lo recibe completo y **no** se crea
   ningún archivo en ninguna parte.
2. **Given** un borrador completado que vive en un archivo cualquiera fuera del
   directorio de git, **When** el revisor lo instala nombrando ese archivo,
   **Then** se valida con exactamente las mismas reglas de siempre y queda
   instalado en el lugar canónico del borrador de esa rama.
3. **Given** un borrador completado que llega por la entrada estándar, **When**
   el revisor lo instala, **Then** el resultado es idéntico al del caso
   anterior.
4. **Given** un borrador instalado por cualquiera de esas dos vías, **When** el
   revisor pausa la review, la retoma, consulta el estado, lista las reviews o
   descarta el borrador, **Then** todo se comporta exactamente igual que con un
   borrador escrito directamente en el lugar canónico.
5. **Given** una entrada vacía o de puro espacio en blanco, **When** el revisor
   intenta instalarla, **Then** se rechaza con un motivo accionable y el
   borrador que ya hubiera queda intacto.
6. **Given** una entrada que no pasa la validación, **When** el revisor intenta
   instalarla, **Then** el borrador anterior queda intacto: la instalación es
   todo o nada.

---

### User Story 3 - El borrador a medio escribir es visible en el panel (Priority: P2)

Un revisor arranca el borrador desde su editor, se lo pasa a su agente y cierra
el IDE. Al día siguiente lo abre y el panel le dice, sin que tenga que buscar
nada, que tiene un orden de lectura empezado para esa rama y cuántas entradas
lleva anotadas. Desde ahí puede abrirlo, copiar la instrucción para el agente,
validarlo y arrancar la review, o descartarlo.

**Why this priority**: Es lo que convierte el borrador de un paso efímero de un
asistente en un objeto del producto. Sin esto, el trabajo del agente vive en
una notificación que cualquier cosa se lleva puesta.

**Independent Test**: Crear un borrador a medio llenar, cerrar y reabrir el
editor, y comprobar que el panel lo reporta con su progreso y ofrece las cuatro
acciones, sin abrir el asistente de inicio.

**Acceptance Scenarios**:

1. **Given** un borrador a medio escribir y ninguna review activa, **When** el
   revisor abre el panel, **Then** ve —sin que el cuerpo de siempre desaparezca:
   el inventario de reviews y arrancar una review siguen ahí— que hay un orden
   de lectura empezado, para qué rama es, y cuántas de sus entradas están
   anotadas sobre cuántas tiene.
2. **Given** ese estado, **When** elige abrir el borrador, **Then** el archivo
   se abre para editar.
3. **Given** ese estado, **When** elige copiar la instrucción para el agente,
   **Then** el portapapeles queda con un texto corto que basta para que un
   agente encuentre el archivo y sepa que las instrucciones están adentro.
4. **Given** ese estado y un borrador ya completo, **When** elige validar y
   arrancar, **Then** el borrador se valida y la review arranca en modo walk —
   preguntando por las entradas esenciales sólo si las hay.
5. **Given** ese estado y un borrador incompleto, **When** elige validar y
   arrancar, **Then** ve el motivo concreto del rechazo y el estado del panel
   sigue igual, con el borrador intacto.
6. **Given** ese estado, **When** elige descartar el borrador, **Then** se le
   pide confirmación y, al confirmar, el borrador se elimina y el panel vuelve
   al estado sin review.
7. **Given** un borrador a medio escribir y ninguna review activa, **When** un
   cliente consulta la superficie de configuración y arranque —la que ya
   consulta sin review y sin nombrar ninguna rama—, **Then** la ruta real del
   borrador está ahí, resuelta, sin que el cliente tenga que derivarla por su
   cuenta.
8. **Given** dos o más borradores a medio escribir de ramas distintas y ninguna
   review activa, **When** el revisor abre el panel, **Then** los ve **todos**,
   una fila por borrador, cada una con la rama a la que pertenece, su progreso y
   sus acciones, sin que ninguno quede oculto detrás de otro.
9. **Given** una review activa que corre sobre un borrador, **When** el revisor
   consulta el informe de estado de esa review, **Then** la ruta real del
   borrador en vigor está ahí, resuelta.

---

### User Story 4 - El asistente deja de ser una sala de espera (Priority: P2)

Un revisor abre el asistente de inicio sobre un PR sin orden de lectura y ve
una opción que le dice, en palabras, qué gana eligiéndola y qué pasa si no la
elige. La elige: se le crea el borrador, se le abre y el asistente **termina
ahí**, dejándolo en el estado del panel de la historia 3. No queda ninguna
notificación esperando indefinidamente a que él termine de escribir.

**Why this priority**: Depende de la historia 3 (es donde el revisor aterriza)
y es la que elimina la parte peor del flujo actual. No agrega capacidad nueva,
pero sin ella conviven dos caminos para lo mismo.

**Independent Test**: Recorrer el asistente sobre un PR sin walkthrough,
comprobar que la opción comunica su valor y su alternativa, y que elegirla
deja al revisor en el estado del panel sin ninguna notificación pendiente.

**Acceptance Scenarios**:

1. **Given** un PR sin orden de lectura, **When** el revisor llega al paso de
   forma de lectura, **Then** ve una opción cuyo texto dice qué obtiene y cuál
   es la alternativa si no la toma, sin usar jerga interna del producto.
2. **Given** que la elige, **When** se crea el borrador, **Then** el archivo se
   abre y el asistente cierra, sin dejar ninguna espera abierta.
3. **Given** que la elige y la creación falla, **When** el asistente cierra,
   **Then** el revisor ve el motivo y puede volver a elegir cómo leer el PR sin
   rehacer la elección de rama.
4. **Given** un borrador ya empezado para esa rama, **When** el revisor abre el
   asistente, **Then** la opción se ofrece como continuar el que hay, y
   elegirla lo lleva al mismo estado sin volver a crear nada.

---

### User Story 5 - Lo mismo desde IntelliJ y desde Visual Studio (Priority: P3)

Un revisor que trabaja en IntelliJ o en Visual Studio ve el mismo estado del
panel, con las mismas acciones y las mismas etiquetas, y recorre el mismo
asistente acortado.

**Why this priority**: Paridad de producto entre los tres clientes. No aporta
capacidad nueva y depende enteramente de las historias 3 y 4.

**Independent Test**: Reproducir las historias 3 y 4 en cada cliente y comprobar
que las decisiones que se le ofrecen al revisor son las mismas, tomadas siempre
a partir de lo que reporta la CLI.

**Acceptance Scenarios**:

1. **Given** un borrador a medio escribir, **When** el revisor abre el panel en
   cualquiera de los tres clientes, **Then** ve el mismo bloque con las mismas
   acciones y el mismo progreso.
2. **Given** ese estado, **When** copia la instrucción para el agente, **Then**
   obtiene el mismo texto en los tres.

---

### Edge Cases

- **El PR cambia entre que se pidió el esqueleto y que se instala el
  borrador**: la instalación resuelve el rango contra las referencias actuales,
  así que el desajuste sale como el error de deriva de siempre, nombrando qué
  sobra y qué falta. Nada se instala.
- **Las instrucciones del archivo apuntan a un rango que ya no existe**
  (la rama fue reescrita): quien complete el borrador obtiene un error de git
  al intentar ver el contenido, no una respuesta vacía silenciosa. El
  esqueleto se vuelve a pedir y se rehace.
- **El borrador ya fue validado una vez y hay que reanotarlo** (el autor pusheó
  y ahora sobran o faltan archivos): el archivo instalado **conserva** el bloque
  de instrucciones, así que se le vuelve a pasar al agente tal cual, con los
  *whys* ya escritos adentro. No hay que recuperar nada ni reconciliar dos
  archivos.
- **Alguien borra a mano el bloque de instrucciones de un borrador**: es prosa
  del archivo como cualquier otra; su ausencia no invalida el borrador ni cambia
  cómo se lee. Lo único que se pierde es poder reanotarlo sin volver a pedir el
  esqueleto.
- **El bloque de instrucciones nombra un rango y el borrador se reconstruye más
  tarde**: la reconstrucción vuelve a emitir el bloque con el rango que ella misma
  acaba de validar, así que el archivo nunca queda describiendo uno viejo. Es el
  caso que la deriva **no** cubre: si el conjunto de archivos no cambió, la
  validación pasa y sólo la regeneración impide que el bloque mienta.
- **Se borró el bloque a mano y después se quiere validar y arrancar desde el
  panel**: no se sabe con qué origen ni con qué rango se generó el borrador, así
  que esa fila no ofrece esa acción y remite a la terminal. Adivinar los flags
  produciría un rechazo por desajuste que el revisor no podría explicarse.
- **El borrador está vacío** (se pidió el esqueleto por salida estándar y todavía
  no se instaló nada, o se creó y se vació): se reporta y se muestra igual, con
  cero de cero. Existe, ocupa el nombre de esa rama y hay que poder abrirlo y
  descartarlo.
- **No hay ningún borrador**: el reporte no emite ninguna fila **y termina**. Es
  el caso más común de todos y el que corre en cada refresco del panel.
- **Hay varios borradores sueltos al mismo tiempo**: se reportan y se muestran
  todos, uno por rama, cada uno con su progreso; ninguna acción sobre uno toca a
  los demás.
- **Hay varios borradores y uno de ellos pertenece a una review pausada**: los
  demás se muestran como borradores sueltos y ése no, por el mismo motivo por el
  que no se muestra cuando está solo.
- **Se pide instalar desde la entrada estándar en una terminal interactiva sin
  redirigir nada**: el comando no se queda esperando para siempre; explica que
  esa forma espera contenido por la entrada estándar y cómo usarla.
- **Se pide instalar desde un archivo que no existe o que no se puede leer**:
  falla nombrando el archivo, sin tocar el borrador que ya hubiera.
- **Se pide instalar sobre una rama que ya tiene un borrador propio**: no se
  pisa prosa escrita a mano sin que el revisor lo pida explícitamente.
- **Se pide el esqueleto por salida estándar para una rama que ya tiene
  borrador**: se imprime igual, porque imprimir no destruye nada; la protección
  contra sobrescribir es del que escribe, no del que muestra.
- **Se pide el esqueleto para un PR que no cambia ningún archivo, o para una
  rama inexistente, o sin base configurada**: falla con los mismos mensajes
  accionables de hoy, sin imprimir un esqueleto vacío.
- **El nombre de la rama no es usable como nombre de archivo en este sistema**
  (nombres de dispositivo reservados en Windows): pedir el esqueleto por salida
  estándar funciona igual, porque no escribe nada; instalarlo falla con el
  mismo mensaje explicativo que ya existe.
- **Hay un borrador a medio escribir y una review activa de otra rama al mismo
  tiempo**: el panel muestra la review activa; el borrador de la otra rama no
  compite por el cuerpo del panel.
- **El borrador pertenece a una review pausada**: el estado del panel no lo
  ofrece como si fuera un borrador suelto, porque descartarlo desde ahí le
  sacaría el orden de lectura a una review que va a volver.
- **Todas las entradas del borrador están anotadas pero la validación falla por
  otro motivo** (una ruta duplicada, un marcador con valor): el progreso muestra
  el total anotado y la validación explica lo suyo; el progreso no es una
  promesa de que va a validar.
- **El progreso se pide sobre un borrador que no es del rango actual**: se
  cuenta sobre lo que el archivo tiene, sin inventar una intersección con el
  rango; el desajuste es asunto de la validación.

## Requirements *(mandatory)*

### Functional Requirements

#### El esqueleto tiene que ubicar el cambio

- **FR-001**: El esqueleto del borrador MUST identificar el rango que el orden
  de lectura cubre con referencias que git pueda resolver en ese repositorio,
  en lugar de nombres genéricos. Los dos extremos del rango ya están resueltos
  en el momento de escribir el esqueleto.
- **FR-002**: El esqueleto MUST incluir instrucciones concretas para obtener,
  para cualquiera de los archivos que lista, tanto el cambio que el PR le hace
  como su contenido resultante — sin depender de lo que tenga el árbol de
  trabajo.
- **FR-003**: Esas instrucciones MUST ser válidas también cuando el límite
  inferior del rango no es un commit sino un estado sintético, situación que se
  da cuando la rama base fue mergeada dentro del PR.
- **FR-004**: El esqueleto MUST decir explícitamente qué relación tiene el
  árbol de trabajo con el PR en la situación en que fue generado, distinguiendo
  al menos el caso "generado desde la rama base" (el árbol no tiene el PR) del
  caso "generado desde adentro de una review activa" (el árbol sí lo tiene, más
  las ediciones del revisor).
- **FR-005**: Las instrucciones MUST reflejar el rango efectivamente resuelto,
  incluido el caso incremental, de modo que un esqueleto de rango incremental
  no invite a anotar el PR entero.
- **FR-005a**: Las instrucciones MUST registrar con qué origen y qué rango se
  generó el borrador, de modo que cualquier superficie que después lo valide o
  arranque una review sobre él pueda usar los mismos y no otro conjunto de
  archivos. Ese registro MUST vivir junto al borrador, sin estado paralelo que
  pueda sobrevivirlo o desincronizarse de él.
- **FR-006**: El esqueleto MUST decir explícitamente que el orden de lectura se
  escribe sobre el rango indicado y no sobre lo que el árbol de trabajo
  contenga, y MUST no contener instrucciones que contradigan la situación real
  del revisor.
- **FR-006a**: La instrucción de cierre del esqueleto —la que dice cómo validar e
  instalar lo escrito— MUST nombrar el comando que corresponde a **cómo se
  obtuvo ese esqueleto**. Un esqueleto emitido por la salida estándar no dejó
  ningún archivo, así que la instrucción de cierre no puede ser la misma que la
  de un esqueleto escrito en disco: seguirla instalaría otro archivo, o ninguno,
  sin error visible.
- **FR-007**: El esqueleto del autor (el que se escribe sobre el sidecar
  commiteado del propio PR) MUST recibir el mismo tratamiento en lo que le
  aplique, sin que las dos versiones del texto puedan divergir en silencio. Como
  ese archivo sí se commitea, el bloque de instrucciones que sobrevive a la
  construcción (FR-013a) MUST quedar en una forma que no se renderice al leer el
  PR en la plataforma de revisión, y MUST no quedar commiteado describiendo un
  rango que ya no es el del PR.
- **FR-008**: Las instrucciones que el esqueleto incorpore MUST ser
  descriptivas: el producto no ejecuta nada en nombre de quien anota, ni antes
  ni después.

#### Superficies que no obligan a escribir dentro del directorio de git

- **FR-009**: El revisor MUST poder obtener el esqueleto por la salida estándar
  sin que se cree ni se modifique ningún archivo en ninguna parte, con la misma
  resolución de rama y de rango (origen remoto o local, rango incremental) que
  tiene hoy la generación del borrador.
- **FR-010**: El revisor MUST poder instalar un borrador completado leyéndolo
  de un archivo que él nombre, en cualquier ubicación del sistema.
- **FR-011**: El revisor MUST poder instalar un borrador completado leyéndolo
  de la entrada estándar.
- **FR-012**: En los tres casos anteriores el destino de escritura MUST seguir
  siendo la ubicación canónica del borrador de esa rama, de modo que la
  precedencia sobre el walkthrough del autor, la marca de "orden propio", el
  archivado al pausar, la restauración al retomar, el descarte explícito, el
  informe de estado, las ofertas de lectura y el guard de metadata al finalizar
  sigan funcionando sin ningún cambio.
- **FR-013**: La validación aplicada a un borrador que llega por cualquiera de
  esas vías MUST ser exactamente la misma que se aplica hoy, sin una sola regla
  de más ni de menos, y MUST no verificar la calidad del contenido escrito.
- **FR-013a**: El bloque de instrucciones para el agente MUST ser una pieza
  reconocida del formato del walkthrough, con tres propiedades: la reescritura
  que hace la validación lo **conserva** en lugar de descartarlo como andamiaje,
  **emitiéndolo de nuevo con el rango que esa misma reescritura acaba de
  validar** —de modo que nunca quede describiendo un rango viejo—; la lectura del
  walkthrough durante la review lo **filtra**, de modo que nunca se le muestra al
  revisor donde se muestra la prosa previa a la primera entrada; y su presencia o
  ausencia MUST no cambiar el resultado de ninguna regla de validación. Es la
  única excepción a "todo comentario es andamiaje", y se define en un solo lugar
  para el borrador del revisor y para el sidecar del autor.
- **FR-014**: Una instalación que falla la validación MUST dejar intacto el
  borrador anterior, si lo había: la instalación es atómica.
- **FR-015**: Una entrada vacía o de puro espacio en blanco MUST rechazarse con
  un motivo accionable, sin instalar nada.
- **FR-016**: Instalar sobre un borrador existente MUST requerir que el revisor
  lo pida explícitamente, con la misma asimetría de riesgo que rige hoy para
  sobrescribir un borrador.
- **FR-017**: Pedir el contenido por la entrada estándar en una terminal
  interactiva sin nada redirigido MUST fallar con una explicación, en lugar de
  quedarse esperando indefinidamente.
- **FR-018**: Un archivo de origen inexistente o ilegible MUST fallar
  nombrándolo, sin tocar el borrador que hubiera.
- **FR-019**: *(consecuencia de FR-013a; se conserva el número porque el plan, los
  contratos y las tareas lo referencian.)* Reanotar un borrador ya instalado MUST
  ser volver a pasarle ese mismo archivo al agente, con los *whys* ya escritos
  adentro y sin reconciliar nada. No hay un comando de recuperación aparte.

#### El borrador como objeto del producto

- **FR-020**: El informe de estado de una review activa MUST reportar la ruta
  real del borrador en vigor, resuelta, de modo que ningún cliente necesite
  derivarla por su cuenta. Ese informe sigue hablando **sólo** de la review de la
  rama en la que se lo consulta: no reporta borradores sueltos, que son asunto de
  FR-021.
- **FR-021**: El producto MUST reportar cada borrador que existe —la rama a la
  que pertenece, su ruta real resuelta, su progreso y el origen y rango con los
  que se generó (FR-005a)— en la superficie de configuración y arranque que un
  cliente ya consulta **sin** una review activa y **sin** nombrar ninguna rama.
  MUST emitirse un registro por borrador, no uno solo: puede haber varios a la
  vez y ninguno puede quedar oculto detrás de otro. Un borrador vacío MUST
  reportarse igual que los demás: existe, y hay que poder abrirlo y descartarlo.
- **FR-021a**: Ese reporte MUST terminar siempre, también cuando no hay ningún
  borrador. Es la superficie que un cliente consulta en cada refresco y que un
  usuario corre a mano en una terminal; quedarse esperando entrada es un modo de
  fallo inaceptable en el caso más común de todos.
- **FR-022**: El progreso MUST contarse sobre lo que el archivo del borrador
  contiene, sin cruzarlo contra el rango: informar avance no es validar. Una
  entrada cuenta como anotada sólo cuando tiene resueltas **las dos** marcas de
  posición que el esqueleto deja: su posición de lectura y su *why*. Una entrada
  con posición y sin *why*, o con *why* y sin posición, no cuenta.
- **FR-023**: El inventario de reviews MUST reportar de forma legible por
  máquina qué filas cargan un borrador, tal como el listado para personas ya lo
  señala hoy.
- **FR-024**: Un borrador que pertenece a una review pausada MUST distinguirse
  de un borrador suelto en todo lo que reporte el producto, para que ningún
  cliente ofrezca descartar el orden de lectura de una review que va a volver.

#### Lo que muestran los clientes

- **FR-025**: Los tres clientes MUST presentar "hay un orden de lectura empezado
  y ninguna review activa" como un **bloque propio arriba del cuerpo del panel
  sin review**, que persista entre sesiones del editor y no dependa de ninguna
  notificación. El cuerpo de siempre MUST seguir entero debajo: el inventario de
  reviews, retomar una review pausada y arrancar una review nueva quedan
  accesibles mientras el borrador exista.
- **FR-026**: El bloque MUST llevar una fila por borrador reportado, y cada fila
  MUST decir a qué rama pertenece y ofrecer cuatro acciones sobre **ese**
  borrador: abrirlo, copiar la instrucción para el agente, validarlo y arrancar
  la review, y descartarlo. Una acción sobre una fila MUST no afectar a las
  demás.
- **FR-027**: Cada fila MUST mostrar el progreso de su borrador tal como lo
  reporta la CLI, sin que ningún cliente lo derive leyendo el archivo.
- **FR-028**: Copiar la instrucción para el agente MUST poner en el portapapeles
  un texto corto que baste para que un agente encuentre el archivo de **ese**
  borrador y sepa que las instrucciones están adentro, e incluya su ruta real. MUST NOT abrir
  ninguna conexión, invocar ningún modelo ni integrarse con ningún asistente.
- **FR-029**: Validar y arrancar MUST validar primero y, en verde, arrancar la
  review en modo walk, ofreciendo elegir entre el recorrido completo y sólo las
  entradas esenciales únicamente cuando esa segunda opción sea viable según la
  CLI.
- **FR-029a**: Validar y arrancar MUST hacerlo con el **mismo origen y rango con
  los que el borrador fue generado** (FR-005a), no con los de por defecto. Un
  borrador generado con un origen local o un rango incremental cubre otro
  conjunto de archivos, así que usar los de por defecto lo rechazaría **siempre**
  por desajuste, sobre un borrador perfectamente válido y sin salida dentro del
  panel. Si ese dato no está disponible, la fila MUST no ofrecer la acción, en
  lugar de suponerlo.
- **FR-030**: Una validación en rojo MUST mostrar el motivo concreto y dejar el
  estado del panel y el borrador exactamente como estaban.
- **FR-031**: Descartar MUST pedir confirmación antes de eliminar prosa escrita
  a mano.
- **FR-032**: El asistente de inicio MUST terminar en cuanto el borrador queda
  creado, sin abrirlo y sin dejar ninguna espera abierta: la continuación vive en
  el estado del panel, que aparece con el refresco que sigue a toda mutación y ya
  trae la ruta reportada por la CLI. Abrirlo desde el asistente obligaría a
  conocer esa ruta antes de que exista el reporte que la trae, que es la única
  forma en que la prohibición de derivarla podría reintroducirse.
- **FR-033**: La oferta del asistente MUST nombrarse en términos de lo que el
  revisor obtiene y de la alternativa que tiene si no la toma, en lugar de
  jerga interna del producto, y MUST seguir diferenciando empezar de continuar.
- **FR-034**: Los tres clientes MUST ofrecer el mismo conjunto de decisiones con
  las mismas etiquetas, todas derivadas de lo que reporta la CLI, y el contrato
  anti-drift multi-cliente MUST declarar las acciones y la disposición nuevas en
  el mismo cambio.
- **FR-035**: Una divergencia deliberada de algún cliente MUST declararse en el
  contrato, no en el cliente.

#### Documentación

- **FR-036**: Los dos README (inglés y español) MUST documentar la superficie
  nueva en el mismo cambio.
- **FR-037**: La documentación MUST dejar explícito que el producto no completa
  el borrador, no ejecuta las instrucciones que el esqueleto trae y no se
  conecta con ningún servicio.
- **FR-038**: La documentación MUST mostrar el circuito completo con un agente
  —obtener el esqueleto, completarlo afuera, instalarlo— como el camino
  recomendado.

### Key Entities

- **Esqueleto del borrador**: el archivo que el producto genera con la lista de
  archivos del rango y la consigna para quien lo complete. Esta feature le
  agrega la ubicación del cambio: qué rango, cómo verlo, y qué relación tiene
  el árbol de trabajo con el PR. Puede materializarse como archivo o emitirse
  por la salida estándar.
- **Bloque de instrucciones**: la parte del esqueleto dirigida a quien lo
  completa —el rango, cómo ver el contenido, la relación con el árbol de
  trabajo—. Es una pieza reconocida del formato: sobrevive a la construcción del
  archivo y se filtra al leerlo durante la review, así que ni el revisor ni el
  PR la ven, pero el agente la sigue teniendo delante cuando hay que reanotar.
- **Borrador instalado**: el orden de lectura del revisor en su ubicación
  canónica, que es lo que el resto del producto lee. No cambia con esta
  feature; lo que cambia es de dónde puede venir su contenido — y que conserva su
  bloque de instrucciones.
- **Progreso del borrador**: cuántas de las entradas que el borrador declara
  tienen resueltas sus dos marcas de posición —posición de lectura y *why*—,
  sobre el total que declara. Es un dato de avance, no de validez.
- **Instrucción para el agente**: el texto corto que el revisor copia al
  portapapeles. No es el prompt: el prompt está en el archivo. Es sólo lo que
  hace falta para que el agente llegue hasta él.
- **Estado del panel con borrador pendiente**: la situación "hay un orden de
  lectura empezado y ninguna review activa", presentada como un bloque arriba del
  cuerpo del panel sin review —que sigue entero debajo—, con una fila por
  borrador, su rama, su progreso y sus cuatro acciones.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un agente que sigue al pie las instrucciones del esqueleto anota
  el contenido posterior al PR en el **100 %** de los archivos que el esqueleto
  lista, en cualquiera de los orígenes y rangos que el producto soporta
  (remoto, local, sin red, incremental) y esté el revisor parado en la base o
  dentro de una review activa.
- **SC-002**: Ninguna instrucción del esqueleto queda en desacuerdo con la
  situación real del revisor: el archivo nunca le dice al que anota que el
  árbol de trabajo no tiene el PR cuando sí lo tiene, ni al revés.
- **SC-003**: Un agente puede completar el trabajo entero **sin escribir ni una
  sola vez dentro del directorio de git**, y el resultado es indistinguible de
  un borrador escrito ahí: mismo modo de review, mismo orden, mismo
  comportamiento en pausar, retomar, listar, descartar y finalizar.
- **SC-004**: Ninguna forma de instalar un borrador deja el estado a medias:
  o queda instalado y válido, o el borrador anterior sigue byte por byte como
  estaba.
- **SC-005**: Ningún comando de esta feature se queda esperando entrada
  indefinidamente sin haberlo dicho.
- **SC-006**: Todo borrador a medio escribir sobrevive al cierre del editor y
  vuelve a estar a la vista **en el primer vistazo al panel**, sin abrir ningún
  asistente, sin recordar ningún comando y sin buscar ninguna ruta — los N que
  haya, no el último—, y sin que aparecer le saque del panel el inventario de
  reviews ni el botón de arrancar una.
- **SC-007**: Pasarle el trabajo a un agente cuesta **una sola acción** desde el
  panel, y el texto copiado alcanza para que el agente llegue al archivo sin
  más datos.
- **SC-008**: Ningún cliente deriva por su cuenta la ruta del borrador, su
  existencia ni su progreso: los tres muestran únicamente lo que la CLI
  reporta.
- **SC-009**: Los tres clientes ofrecen el mismo conjunto de decisiones, y el
  contrato anti-drift lo verifica automáticamente.
- **SC-010**: Un revisor que elige armarse el orden de lectura desde el
  asistente no queda con ninguna notificación pendiente después de que el
  asistente cierra.
- **SC-011**: El texto de la oferta del asistente comunica el resultado y su
  alternativa sin usar términos que sólo existan dentro de este producto.
- **SC-012**: Ninguna acción del panel puede destruir el orden de lectura de una
  review pausada.
- **SC-013**: El progreso nunca marca el total mientras quede una entrada sin
  posición de lectura o sin *why*, y un borrador recién generado marca **cero**
  sobre el total de archivos del rango.
- **SC-014**: Un borrador reanotado se le vuelve a pasar al agente **sin
  reconstruir el esqueleto ni reconciliar dos archivos**: el archivo instalado
  basta por sí solo.
- **SC-015**: El bloque de instrucciones no aparece nunca en lo que el producto
  le muestra al revisor durante la review, ni renderizado en el PR del autor.
- **SC-016**: Correr **literalmente** el comando que el esqueleto imprime al
  cierre instala el contenido que quien anota acaba de escribir, cualquiera sea
  la forma en que obtuvo ese esqueleto. Nunca instala otro archivo, y nunca sale
  en verde sin haber instalado nada.
- **SC-017**: Validar y arrancar desde el panel funciona sobre un borrador
  generado con **cualquiera** de los orígenes y rangos soportados, no sólo con
  los de por defecto.
- **SC-018**: El bloque de instrucciones de un borrador ya construido describe
  siempre el rango contra el que ese borrador fue validado por última vez.

## Assumptions

- **La consigna vive en el archivo.** No hay generador de prompts ni comando
  que produzca un texto para pegarle a un modelo. Lo que se copia al
  portapapeles es sólo el puntero al archivo, porque el archivo ya trae la
  consigna. Decisión tomada, no se re-litiga.
- **El hand-off es sólo portapapeles.** No hay integración con ningún asistente
  del editor, ni con las APIs de modelos que los hosts exponen. Es la misma
  frontera que 011 ya trazó.
- **La calidad de lo que escribe el agente está fuera de alcance.** No hay forma
  de verificarla y no se intenta. La validación sigue siendo de forma y de
  conjunto de rutas.
- **El destino de escritura no se mueve.** Todo lo que 011 construyó cuelga de
  la ubicación canónica del borrador; separar de dónde viene el contenido no es
  moverlo. Ninguna superficie de ciclo de vida se toca.
- **Las instrucciones del esqueleto son descriptivas.** El producto escribe qué
  comandos sirven para ver el cambio; no los corre, ni antes ni después. Es la
  misma regla que ya rige para la guía de autoría opcional: se apunta, no se
  interpreta.
- **El rango se resuelve una vez, al generar el esqueleto.** Las referencias que
  el archivo contiene son una foto del momento en que se generó; si el PR se
  mueve, la validación lo detecta como deriva, que es el mecanismo que ya
  existe. No se re-resuelve nada al vuelo.
- **El progreso es un conteo, no una promesa.** Que todas las entradas estén
  anotadas no implica que la validación vaya a pasar; sigue habiendo reglas de
  duplicados, de marcadores y de deriva.
- **El estado del panel con borrador pendiente sólo aparece sin review
  activa.** Una review en curso es siempre lo más importante que el panel tiene
  para decir; el borrador de otra rama no le compite el cuerpo. Y donde sí
  aparece, se suma al cuerpo de siempre en vez de reemplazarlo: a diferencia de
  "falta configurar la base", tener un borrador a medio escribir no impide hacer
  ninguna de las otras cosas que ese panel ofrece.
- **El bloque de instrucciones es la única excepción a "todo comentario es
  andamiaje".** El resto del formato no cambia: los marcadores de posición del
  esqueleto se siguen descartando al construir, y la prosa previa a la primera
  entrada se sigue preservando verbatim. Se agrega una sola pieza reconocida, y
  se define una sola vez para los dos lados del walkthrough. La excepción es
  *conservarlo*, no copiarlo: el bloque que sale de una construcción lo emite el
  mismo generador que escribió el esqueleto, con el rango de esa corrida, así que
  el archivo nunca arrastra una descripción vencida de sí mismo.
- **La oferta se renombra con la alternativa explícita.** El revisor tiene que
  poder decidir sin saber qué es un walkthrough: qué gana armando el orden, y
  qué le queda si no lo arma. La forma exacta de la copy se define al
  implementar, dentro de esa regla.
- **La CLI sigue siendo la única fuente de verdad.** Los clientes no leen ni
  interpretan el borrador: muestran lo que la CLI reporta e invocan comandos.
  El progreso y la ruta se agregan a lo que la CLI reporta precisamente por eso.
- **Alcance por fases.** La CLI va primero, porque todo lo que los clientes
  muestran depende de que ella lo reporte; después la extensión de VS Code, el
  plugin de JetBrains y la extensión de Visual Studio, en ese orden.
- **El contrato multi-cliente crece con la feature.** La matriz de acciones y el
  bloque de disposición del panel se amplían en el mismo cambio, y su
  verificador automático se actualiza junto con ellos; las tres puntas por
  cliente se mueven a la vez.
