# Feature Specification: Contrato de salida legible por programas

**Feature Branch**: `001-contrato-porcelain`

**Created**: 2026-08-02

**Status**: Draft

**Input**: User description: "vamos a centrarnos bien en el porque hacemos esto, quiero que definas
muy bien que es lo que necesitamos para que luego pueda avanzar con la creacion de la extension, por
ahora solo vamos con los porcelain o los cambios en si necesarios en los comandos, nada mas"

## Contexto y Motivación *(el porqué)*

### El problema

`git review` hoy sólo sabe hablarle a un humano. Cada verbo imprime prosa pensada
para leerse en una terminal (`review of feat-x (tip a1b2c3d)`, `mode walk [3/7]
on src/foo.ts (key)`), y ningún verbo expone su estado de una forma que otro
programa pueda consumir sin adivinar.

Eso no fue un descuido: hasta ahora el único consumidor era una persona. Pero el
producto está por ganar un segundo consumidor —una extensión de editor— y ahí el
problema se vuelve estructural, no cosmético.

### Por qué importa ahora

Un consumidor externo que quiera mostrar una review tiene hoy exactamente dos
caminos, y los dos son malos:

1. **Parsear la salida humana.** Convierte la prosa en una API pública de hecho.
   A partir de ese momento nadie puede mejorar un mensaje sin romper al
   consumidor, y el acoplamiento es invisible: no hay ningún test que lo declare.

2. **Reimplementar el modelo de estado por fuera.** Leer las claves de config y
   re-derivar la secuencia de lectura en el lenguaje del consumidor. Este camino
   es peor, y en *este* proyecto en particular es directamente inaceptable: el
   proyecto tiene una regla explícita de que toda comparación de paths entre el
   walkthrough y git pasa por dos únicos puntos de normalización
   (`walk_normalize` y `changed_paths`). Una reimplementación externa crea un
   tercer punto. El síntoma cuando se desincroniza no es un error ruidoso: es una
   entrada que desaparece del orden de lectura en silencio, o el mismo archivo
   apareciendo a los dos lados de un error de drift. Es exactamente la clase de
   bug invisible que este proyecto ya pagó tres veces (CRLF, BOM, whitespace).

El costo de no hacerlo, entonces, no es "la extensión sale más fea". Es que la
extensión nace acoplada a la prosa o duplicando la lógica más delicada del
proyecto, y cualquier divergencia posterior se manifiesta como datos incorrectos
mostrados con total confianza.

### Qué habilita

Un contrato estable convierte a cualquier consumidor externo en un cliente tonto:
la CLI sigue siendo la única fuente de verdad sobre qué es una review, en qué
estado está y en qué orden se lee. La extensión de editor es el primer
consumidor, pero no el único imaginable — scripts de CI que reporten cobertura de
walkthrough, otros editores, o herramientas de métricas obtienen lo mismo sin
pedir nada nuevo.

### Qué NO es esto

Esta especificación cubre **únicamente** los cambios necesarios en los comandos
existentes. No incluye la extensión de editor, ni decisiones sobre su interfaz,
ni empaquetado o distribución. El criterio de éxito de esta feature es que,
cuando termine, alguien pueda construir ese consumidor sin volver a tocar los
comandos.

## User Scenarios & Testing *(mandatory)*

En todas las historias, el "consumidor" es cualquier programa que invoca los
comandos y necesita datos estructurados. El caso motivador es un panel de editor,
pero ninguna historia asume que el consumidor sea eso.

### User Story 1 - Leer el estado de la review actual (Priority: P1)

Un consumidor necesita saber, sin ambigüedad, qué review está en curso en el
repositorio: qué rama la contiene, qué PR se está revisando, en qué modo, y —si
el modo tiene cursor— en qué posición está y sobre qué archivo o commit.

Hoy toda esa información existe y se calcula, pero sale mezclada con texto de
ayuda y formato de presentación. El consumidor tiene que recortarla de frases.

**Why this priority**: Es la base de todo lo demás. Sin poder responder "¿hay una
review acá y cómo está?", ningún consumidor puede siquiera decidir si tiene algo
que mostrar. Cualquier otra historia presupone ésta.

**Independent Test**: Se puede probar íntegramente iniciando una review en cada
uno de los tres modos y verificando que la salida estructurada contiene los
campos correctos, con valores exactos, sin depender de ninguna otra historia.

**Acceptance Scenarios**:

1. **Given** una review activa en modo walk posicionada en la entrada 3 de 7,
   **When** el consumidor pide el estado en formato estructurado, **Then**
   obtiene la rama, el PR de origen, el tip, el modo, la posición actual, el
   total, el path de la entrada actual y si esa entrada está marcada como
   esencial.
2. **Given** una review activa en modo whole, **When** el consumidor pide el
   estado, **Then** obtiene los campos comunes y ningún campo de cursor, sin que
   la ausencia se confunda con un valor vacío legítimo.
3. **Given** una review activa en modo step, **When** el consumidor pide el
   estado, **Then** obtiene la posición, el total y la identificación del commit
   actual.
4. **Given** cualquier review activa, **When** se modifica un mensaje de la
   salida humana, **Then** la salida estructurada permanece byte a byte idéntica.

---

### User Story 2 - Obtener la secuencia de lectura completa (Priority: P2)

Un consumidor necesita la lista **completa** de entradas del walkthrough tal como
aplican a la review en curso: todas, en orden de lectura, cada una con su
posición, su path y si está marcada como esencial.

Éste es el dato que hoy no existe en ninguna superficie. La secuencia se deriva
internamente durante cada operación y se descarta salvo la entrada actual. Un
consumidor que quiera mostrar el mapa completo del PR —y permitir saltar a la
entrada 7 sin pasar por la 4, 5 y 6— no tiene de dónde sacarlo.

**Why this priority**: Es el valor diferencial. Un panel que sólo muestra la
entrada actual no aporta nada sobre la terminal; lo que justifica una interfaz
visual es ver el recorrido entero de un vistazo. Va después de P1 sólo porque sin
saber que hay una review, la lista no tiene contexto.

**Independent Test**: Se puede probar creando un walkthrough con entradas
conocidas —incluyendo algunas fuera del rango de la review y alguna marcada como
esencial— e iniciando la review, verificando que la secuencia devuelta contiene
exactamente las entradas esperadas, en el orden esperado.

**Acceptance Scenarios**:

1. **Given** una review en modo walk con 7 entradas aplicables, **When** el
   consumidor pide la secuencia, **Then** recibe las 7 en orden de lectura, cada
   una con posición, path y marca de esencial.
2. **Given** un walkthrough cuyas entradas incluyen paths que no cambiaron en el
   rango de la review, **When** el consumidor pide la secuencia, **Then** esas
   entradas no aparecen, igual que no aparecen al recorrer la review desde la
   terminal.
3. **Given** un walkthrough cuyas entradas incluyen paths con caracteres no ASCII,
   **When** el consumidor pide la secuencia, **Then** los paths salen literales y
   coinciden exactamente con los que reporta git para esos mismos archivos.
4. **Given** una review en modo whole sin walkthrough, **When** el consumidor pide
   la secuencia, **Then** obtiene una respuesta vacía sin que eso se reporte como
   error.

---

### User Story 3 - Distinguir "no hay review" de "algo se rompió" (Priority: P2)

Un consumidor necesita separar tres situaciones que hoy se ven casi iguales desde
afuera: no estar en una review (normal, no hay nada que mostrar), estar en una
review con metadata corrupta (error real, hay que avisar), y no poder operar por
otro motivo.

Hoy los tres casos terminan en el mismo código de salida, distinguibles sólo por
el texto del mensaje. Un consumidor que quiera comportarse bien queda obligado a
buscar frases en inglés — es decir, vuelve a acoplarse a la prosa por la puerta
de atrás, justo lo que esta feature intenta evitar.

**Why this priority**: Determina si el consumidor puede comportarse
razonablemente en el caso más frecuente de todos. La mayoría del tiempo el
usuario **no** está en una review, y un panel que muestre un error en esa
situación es peor que no tener panel.

**Independent Test**: Se puede probar invocando los comandos en un repositorio
sin review activa, con una review sana, y con metadata deliberadamente corrupta,
verificando que cada situación produce un código de salida distinto y estable.

**Acceptance Scenarios**:

1. **Given** un repositorio sin ninguna review activa, **When** el consumidor
   consulta el estado, **Then** recibe un código de salida específico que
   significa "no hay review", distinto del código de error genérico.
2. **Given** una review cuya metadata fue alterada a mano y quedó inconsistente,
   **When** el consumidor consulta el estado, **Then** recibe el código de error
   y un diagnóstico en el canal de errores.
3. **Given** un directorio que no es un repositorio git, **When** el consumidor
   consulta el estado, **Then** recibe un código que no se confunde con "no hay
   review".
4. **Given** una review walk sobre cuya base el usuario commiteó, de modo que el
   cursor quedó fuera del rango vigente, **When** el consumidor consulta el
   estado, **Then** recibe un código propio para esa situación recuperable,
   distinto tanto del error genérico como de "no hay review", y el mismo código
   que recibiría si la detectara navegando.

---

### User Story 4 - Obtener el porqué de una entrada (Priority: P3)

Un consumidor necesita, para una entrada dada, el texto que el autor escribió
explicando por qué ese archivo importa — el contenido, sin los marcadores
reservados que forman parte del formato y no del mensaje.

Se separa deliberadamente de la historia 2: la secuencia es un dato tabular y
barato, que se pide cada vez que hay que refrescar una vista; el porqué es prosa
de longitud arbitraria que sólo hace falta cuando alguien decide leer esa entrada
en particular.

**Why this priority**: Un consumidor puede entregar valor sin esto —mostrar el
mapa y navegar ya sirve— pero el porqué es la razón de existir del walkthrough.
Es la primera mejora obvia después del MVP.

**Independent Test**: Se puede probar pidiendo el porqué de entradas conocidas y
verificando que el texto sale completo, sin los marcadores reservados, y vacío
para una entrada sin cuerpo.

**Acceptance Scenarios**:

1. **Given** una entrada con varias líneas de explicación, **When** el consumidor
   pide su porqué, **Then** recibe el texto completo preservando saltos de línea.
2. **Given** una entrada marcada como esencial, **When** el consumidor pide su
   porqué, **Then** el marcador reservado no aparece en el texto devuelto.
3. **Given** una entrada sin explicación, **When** el consumidor pide su porqué,
   **Then** recibe una respuesta vacía sin error.

---

### User Story 5 - Saber qué archivos no están cubiertos (Priority: P3)

Un consumidor necesita saber qué archivos cambian en el rango de la review pero
no tienen entrada en el walkthrough, para poder mostrarlos como parte del
recorrido en lugar de ocultarlos.

Este dato ya se calcula al iniciar una review y se emite como una nota suelta;
después se pierde.

**Why this priority**: Sin esto, un panel que muestre sólo las entradas del
walkthrough le miente al revisor por omisión: da la impresión de que el
walkthrough cubre todo el PR. Es una mejora de confianza, no de capacidad.

**Independent Test**: Se puede probar con una review cuyo rango incluya archivos
deliberadamente ausentes del walkthrough, verificando que se reportan todos y
sólo ésos.

**Acceptance Scenarios**:

1. **Given** una review walk donde 3 archivos del rango no tienen entrada,
   **When** el consumidor pide la cobertura, **Then** recibe exactamente esos 3
   paths.
2. **Given** una review walk donde el walkthrough cubre todo el rango, **When**
   el consumidor pide la cobertura, **Then** recibe una respuesta vacía.

---

### User Story 6 - Inventario de reviews abiertas (Priority: P4)

Un consumidor necesita enumerar todas las reviews del repositorio —activas y
pausadas— con su modo y posición, para poder ofrecer cambiar entre ellas.

**Why this priority**: Es comodidad. Un consumidor útil puede ignorar por
completo la existencia de otras reviews y trabajar sólo con la actual.

**Independent Test**: Se puede probar creando varias reviews en distintos modos,
pausando alguna, y verificando que el inventario las lista todas con su estado y
marca cuál es la actual.

**Acceptance Scenarios**:

1. **Given** dos reviews activas y una pausada, **When** el consumidor pide el
   inventario, **Then** recibe las tres identificadas por rama, con su modo,
   posición y si están pausadas.
2. **Given** una rama de review sin metadata (huérfana), **When** el consumidor
   pide el inventario, **Then** aparece marcada como tal en lugar de omitirse.

---

### Edge Cases

- **Walkthrough presente pero inaplicable**: el PR trae walkthrough pero ninguna
  de sus entradas cae en el rango de la review, y la review degrada a whole. El
  consumidor tiene que poder distinguir esto de "no hay walkthrough": el primero
  merece un aviso accionable al autor, el segundo no es noticia.
- **Paths con caracteres especiales**: nombres con acentos, con espacios, o con
  caracteres que obligan a git a escapar el path. La respuesta tiene que ser
  inequívoca sobre dónde empieza y termina un path.
- **Explicación que imita el formato de salida**: el porqué de una entrada es
  markdown libre y puede contener cualquier cosa, incluida algo que se parezca a
  un campo del contrato. No debe poder confundir a quien lee la salida.
- **Cursor fuera de rango**: el usuario commiteó encima de una review walk y la
  secuencia derivada se achicó. Hoy existe un diagnóstico específico para eso; el
  consumidor tiene que poder distinguirlo de una corrupción real.
- **Review en curso mientras cambia el working tree**: el consumidor consulta
  mientras el usuario edita. Las respuestas tienen que reflejar el estado en el
  momento de la consulta sin dejar residuos ni modificar la review.
- **Consulta concurrente**: dos consultas simultáneas, o una consulta mientras
  corre un comando de navegación.

## Requirements *(mandatory)*

### Functional Requirements

#### Contrato y estabilidad

- **FR-001**: El sistema DEBE ofrecer, para cada dato que un consumidor necesita,
  una forma de obtenerlo destinada a programas, separada de la salida destinada a
  personas.
- **FR-002**: La salida destinada a programas DEBE poder cambiar de forma sólo de
  manera aditiva: agregar información nueva no debe invalidar a un consumidor que
  no la conoce.
- **FR-003**: La salida destinada a programas y la destinada a personas DEBEN
  poder evolucionar por separado; un cambio de redacción en la segunda no debe
  alterar la primera.
- **FR-004**: El sistema DEBE tratar la salida destinada a programas como
  interfaz pública, con cobertura de pruebas que falle ante cualquier cambio de
  forma no intencional.
- **FR-005**: Toda la información expuesta DEBE derivarse de los mismos
  mecanismos internos que usan los comandos interactivos, de modo que no exista
  una segunda fuente de verdad que pueda divergir.

#### Estado de la review

- **FR-006**: El sistema DEBE exponer, para la review en curso, su rama, el
  origen que se está revisando, el punto fijado del origen y el modo.
- **FR-007**: El sistema DEBE exponer, en los modos que tienen cursor, la posición
  actual, el total de posiciones y el elemento sobre el que está posicionado.
- **FR-008**: El sistema DEBE indicar si la entrada actual está marcada como
  esencial por el autor del walkthrough.
- **FR-009**: El sistema DEBE indicar cuándo el PR traía un walkthrough que no
  pudo aplicarse, de forma distinguible de cuándo no traía ninguno.

#### Secuencia y contenido del walkthrough

- **FR-010**: El sistema DEBE exponer la secuencia completa de entradas aplicables
  a la review, en orden de lectura, con posición, path y marca de esencial para
  cada una.
- **FR-011**: La secuencia expuesta DEBE coincidir exactamente con la que
  recorren los comandos de navegación, incluyendo el filtrado por rango.
- **FR-012**: El sistema DEBE exponer el texto explicativo de una entrada
  identificada por su path, sin los marcadores reservados del formato.
- **FR-013**: El sistema DEBE exponer los archivos que cambian en el rango de la
  review y no tienen entrada en el walkthrough.
- **FR-014**: La obtención del texto explicativo DEBE estar separada de la
  obtención de la secuencia, de modo que listar el recorrido no requiera
  transferir prosa.

#### Paths

- **FR-015**: Los paths expuestos DEBEN ser idénticos, byte a byte, a los que el
  sistema usa internamente para comparar contra git.
- **FR-016**: La salida DEBE permitir determinar sin ambigüedad los límites de un
  path, incluso cuando contiene espacios u otros caracteres que en otros
  contextos actuarían como separadores.

#### Señalización de situaciones

- **FR-017**: El sistema DEBE señalizar mediante un código de salida propio la
  ausencia de review activa, distinguiéndola de las condiciones de error. La
  señal DEBE ser la misma en todo verbo que informe esa ausencia, no sólo en
  las superficies de consulta: un mismo hecho no puede tener dos códigos según
  quién lo detecte.
- **FR-018**: El sistema DEBE mantener códigos de salida estables y documentados
  para las situaciones que un consumidor necesita distinguir.
- **FR-019**: Los diagnósticos DEBEN seguir emitiéndose por el canal de errores,
  sin contaminar la salida destinada a programas.
- **FR-023**: El sistema DEBE señalizar de forma propia —sin obligar a inspeccionar
  texto— el caso en que el cursor de una review quedó fuera del rango vigente
  porque el usuario movió la base (situación recuperable por el usuario),
  distinguiéndolo de una metadata corrupta (situación que el usuario no causó ni
  puede deshacer). Igual que FR-017, la señal DEBE ser la misma en todo verbo
  que detecte esa situación.

#### Inventario

- **FR-020**: El sistema DEBE exponer el inventario de reviews del repositorio con
  su rama, modo, posición, y si están pausadas o carecen de metadata.

#### No regresión

- **FR-021**: Ningún **texto** destinado a personas DEBE cambiar como
  consecuencia de esta feature: ni un mensaje, ni su redacción, ni el canal por
  el que sale. Los códigos de salida quedan explícitamente fuera de esta
  garantía — FR-017 y FR-023 los cambian a propósito, y son dato, no prosa.
- **FR-022**: Ninguna consulta destinada a programas DEBE modificar el estado del
  repositorio, el working tree ni la posición de la review.

### Key Entities

- **Estado de review**: la situación de la review en curso. Identidad (rama,
  origen, punto fijado), modo, y —si corresponde— cursor. Es lo que responde
  "¿dónde estoy?".
- **Entrada de walkthrough**: una unidad del recorrido guiado. Tiene posición en
  el orden de lectura, un path, una marca opcional de esencial y un texto
  explicativo. Su existencia depende de que el path realmente cambie en el rango.
- **Secuencia de lectura**: las entradas aplicables a una review concreta,
  ordenadas. No se almacena: se deriva del walkthrough fijado y del rango real.
- **Cobertura**: la relación entre los archivos que cambian en el rango y las
  entradas del walkthrough. Su complemento —lo no cubierto— es lo que importa.
- **Situación**: la condición en que quedó una consulta (hay review / no hay /
  error), como dato explícito y no como texto.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un consumidor puede reconstruir la vista completa de una review
  —estado, recorrido entero y cobertura— sin leer una sola línea de texto
  destinado a personas.
- **SC-002**: Un consumidor puede armar esa vista completa con como máximo 3
  invocaciones, sin necesitar una por entrada del recorrido.
- **SC-003**: Cero lógica de interpretación de paths o de formato de walkthrough
  necesita reimplementarse fuera del proyecto para consumir estos datos.
- **SC-004**: Reescribir cualquier mensaje destinado a personas no altera ninguna
  salida destinada a programas, y existe una prueba que lo demuestra.
- **SC-005**: Un consumidor distingue correctamente las tres situaciones
  (hay review / no hay / error) en el 100% de los casos sin inspeccionar texto.
- **SC-006**: Un walkthrough con paths no ASCII, con BOM o con finales de línea de
  Windows produce exactamente la misma secuencia que su equivalente ASCII limpio.
- **SC-007**: Refrescar la vista de una review de 50 entradas se completa lo
  bastante rápido como para no percibirse como demora al navegar.
- **SC-008**: Toda la funcionalidad existente sigue pasando su suite de pruebas
  sin modificar ninguna aserción sobre el **texto** de la salida humana. Las
  únicas aserciones existentes que se tocan son las de código de salida
  alcanzadas por FR-017 y FR-023, y sólo ésas; cada una queda anotada con el
  requisito que la cambia.

## Assumptions

- **Alcance cerrado en la CLI**: esta feature termina en los comandos. La
  extensión de editor, su interfaz y su distribución quedan explícitamente fuera.
- **El consumidor invoca los comandos**: se asume que cualquier consumidor ejecuta
  la CLI instalada, en lugar de leer el estado del repositorio por su cuenta. El
  contrato existe precisamente para que ésa sea la opción cómoda.
- **Los tres modos siguen existiendo tal cual**: whole, step y walk no cambian su
  semántica. Esta feature los observa, no los modifica.
- **El formato del walkthrough no cambia**: el sidecar y sus marcadores reservados
  quedan como están. Exponerlos no es rediseñarlos.
- **Sin estado nuevo persistido**: no se agregan claves de configuración ni
  referencias. Todo lo expuesto ya existe o se deriva como hoy.
- **Compatibilidad con el soporte actual**: lo que se agregue tiene que funcionar
  en los mismos entornos donde el proyecto ya funciona, sin exigir herramientas
  que hoy no requiere.
- **Las notas informativas se conservan**: los avisos que hoy acompañan al inicio
  de una review siguen existiendo para el usuario humano; esta feature agrega una
  forma de consultarlos, no los reemplaza.
- **Un consumidor puede ser viejo**: se asume que consumidores construidos contra
  una versión anterior seguirán ejecutándose contra versiones posteriores, lo que
  obliga a que el contrato sea aditivo (FR-002).

## Preguntas abiertas

Estas dos decisiones afectan el alcance y conviene resolverlas antes de planificar.

### Q1: ¿La secuencia de lectura se puede consultar fuera de una review activa?

**Context**: FR-010 asume una review en curso, de donde salen el punto fijado y el
rango. Fuera de una review, esos datos habría que derivarlos de la rama actual y
de la configuración del proyecto.

**What we need to know**: ¿El consumidor necesita mostrar el recorrido de un PR
antes de empezar a revisarlo (a modo de vista previa), o alcanza con mostrarlo una
vez que la review arrancó?

| Option | Answer                                              | Implications                                                                                                                                                |
|--------|-----------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| A      | Sólo dentro de una review activa                    | Alcance mínimo y sin ambigüedad sobre el rango. El consumidor no puede ofrecer vista previa; el usuario tiene que iniciar la review para ver el mapa.       |
| B      | También fuera, derivando el rango de la rama actual | Habilita la vista previa y hace el comando útil por sí solo, pero agrega un segundo modo de operación y un caso de error nuevo (sin rama base configurada). |
| C      | Sólo dentro ahora, con la puerta abierta a B        | Se implementa A, pero se decide desde el principio que el contrato admita agregar el caso después sin romper consumidores.                                  |
| Custom | Otra respuesta                                      | Indicá el comportamiento deseado.                                                                                                                           |

**Your choice**: A

### Q2: ¿El contrato cubre el modo step con el mismo detalle que walk?

**Context**: Las historias 2, 4 y 5 están escritas alrededor del walkthrough. En
modo step existe una secuencia análoga —los commits del rango— con su propio
cursor y sus propias ediciones guardadas por paso.

**What we need to know**: ¿El consumidor va a mostrar reviews commit por commit,
o el recorrido visual es exclusivo del walkthrough?

| Option | Answer                                                               | Implications                                                                                                                   |
|--------|----------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| A      | Sólo walk tiene secuencia expuesta; step queda en el estado básico   | Menos superficie y menos pruebas. Un consumidor que abra una review step muestra sólo la posición, sin recorrido navegable.    |
| B      | Step expone su secuencia de commits en paralelo a walk               | El consumidor trata los dos modos igual. Agrega campos y pruebas, e implica decidir qué identifica a un commit en el contrato. |
| C      | Step expone secuencia, y además qué pasos tienen ediciones guardadas | Lo más completo: el consumidor puede señalar en qué commits ya se trabajó. Es el mayor alcance de los tres.                    |
| Custom | Otra respuesta                                                       | Indicá el comportamiento deseado.                                                                                              |

**Your choice**: C
