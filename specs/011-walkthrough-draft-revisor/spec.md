# Feature Specification: Walkthrough del revisor (draft local)

**Feature Branch**: `011-walkthrough-draft-revisor`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Quiero que sea mucho más sencillo revisar PRs
cuyo autor no escribió el walkthrough: que el revisor pueda crearlo y verlo en
modo walk sin mucho problema. Hoy, si no estaba commiteado no te lo tomaba; si
lo dejabas staged no podías iniciar la review; y si lo commiteabas, después
cómo deshacés ese commit. Esas son las fricciones que quiero resolver. Quién
completa el walkthrough que lo resuelva el usuario."

## Contexto y Motivación *(el porqué)*

### El problema

El walkthrough es lo único que git y GitHub no ofrecen: un orden de lectura
sobre un PR, con el *why* de cada archivo. Pero hoy **sólo existe si el autor
lo escribió y lo commiteó**. Un revisor que se topa con un PR sin walkthrough
—la enorme mayoría— sólo puede leerlo como diff plano o commit por commit.

Y si ese revisor quiere armarse el orden de lectura por su cuenta, choca con
tres paredes, que son la misma pared:

| Lo que intenta | Por qué falla |
| --- | --- |
| Escribirlo sin commitear | El walkthrough se lee del tip commiteado; el working tree no existe para el lector |
| Dejarlo staged | `start` exige árbol limpio; y aunque entrara, `finish` se lo llevaría a `review-fixes/` como si fuera una edición suya |
| Commitearlo | Ensució el PR de otra persona, y le queda un commit que deshacer |

A eso se suma que el verbo que escribe el esqueleto (`walkthrough init`)
deriva su rango de `base..HEAD` y asume que estás parado **en tu propio PR**.
El revisor está parado en la rama base, así que ni siquiera puede generarlo:
obtiene "no changes vs base".

**El walkthrough del revisor no tiene dónde vivir.** Ese es el problema
completo.

### Por qué importa ahora

El modo walk es la propuesta de valor diferencial del producto, y hoy depende
de un acto de generosidad del autor que casi nunca ocurre. Cada review que
entra en modo whole por ausencia de walkthrough es una review donde la
herramienta se comporta como cualquier otra.

Además, el esqueleto que escribe `walkthrough init` ya está redactado como
consigna para que lo complete un agente ("the author, typically an AI
agent"). La mitad del trabajo está hecha: sólo apunta al rol equivocado.

### Qué habilita

- Que cualquier PR se pueda leer en orden curado, lo haya escrito el autor o
  no.
- Que armar ese orden **no requiera commitear, stagear ni deshacer nada**: el
  borrador vive fuera del árbol versionado y es invisible para la review.
- Que el borrador se complete con la herramienta que el revisor prefiera —a
  mano, con un agente, con lo que sea— sin que el producto se meta.
- Que el asistente de inicio deje de esconder la opción *Walkthrough* cuando
  el PR no trae uno, y en su lugar ofrezca armarlo.

### Qué NO es esto

- **No** es una integración con IA. El producto no elige modelo, no guarda
  credenciales, no hace red y no envía el diff a ningún lado. Quién completa
  el borrador es decisión del revisor.
- **No** cambia el modo de una review ya iniciada. `start` sigue siendo el
  único que decide el modo: si arrancaste en whole, seguís en whole.
- **No** agrega botones ni bloques nuevos al panel, ni toca la disposición
  declarada en `contracts/client-product-surface.yaml`.
- **No** agrega inventario, progreso ("3 de 12 anotados") ni seguimiento del
  borrador en el panel.
- **No** publica el borrador al PR ni lo propone al autor.
- **No** lista ramas candidatas ni intenta adivinar cuáles son revisables.
- **No** cambia el flujo del autor: `walkthrough init` / `build` sobre el
  sidecar commiteado siguen exactamente igual.

## Clarifications

### Session 2026-08-09

- Q: ¿Se distingue durante la review un orden de lectura escrito por el revisor
  de uno escrito por el autor del PR? → A: Sí, con un marcado discreto en todas
  las superficies que informan el modo (FR-014a, SC-009).
- Q: ¿Puede el revisor armarse un borrador propio para un PR que ya trae
  walkthrough del autor? → A: Sí, por invocación explícita desde la terminal; el
  asistente no ofrece ese camino (FR-005a, FR-016a).
- Q: ¿Qué hace cancelar en el aviso que espera mientras se completa el
  borrador? → A: Devuelve al paso de forma de lectura conservando el borrador
  (FR-018a, SC-010).
- Q: Si se pausa una review que corre sobre un borrador y luego se limpian las
  reviews viejas, ¿el borrador sobrevive? → A: Sí; pausar lo pone a salvo y la
  limpieza sólo elimina los borradores que no pertenecen a una review pausada
  (FR-008a, SC-011).
- Q: ¿La comparación entre dos revisiones usa el borrador del revisor? → A: Sí
  cuando la comparación nombra la rama; el walkthrough del autor cuando compara
  revisiones sueltas (FR-011a).

## User Scenarios & Testing *(mandatory)*

El actor principal es el **revisor**: alguien que va a leer el PR de otra
persona y quiere hacerlo en un orden que hoy nadie escribió. El autor no
participa de ninguna de estas historias.

### User Story 1 - El revisor se arma el orden de lectura desde la terminal (Priority: P1)

Un revisor recibe un PR de 14 archivos sin walkthrough. Antes de empezar, pide
el esqueleto del orden de lectura para esa rama. Recibe un archivo con los 14
archivos listados y la consigna de completarlos. Lo completa —a mano o
pidiéndoselo a su agente—, lo valida, y arranca la review: entra en modo walk
y avanza archivo por archivo con el *why* que él mismo escribió.

En ningún momento tuvo que commitear, stagear ni descartar nada. El árbol de
trabajo del repositorio nunca cambió.

**Why this priority**: Es la feature entera. Sin esto no hay nada que
mostrar en ningún cliente, y el registro que consumen los clientes para
ofrecerlo depende de que exista primero acá.

**Independent Test**: Sobre un PR sin walkthrough, generar el borrador,
completarlo, iniciar la review y comprobar que el modo es walk con el orden
escrito — verificando además que `git status` no reporta ningún cambio en
ningún momento.

**Acceptance Scenarios**:

1. **Given** un PR sin walkthrough y un revisor parado en la rama base,
   **When** pide el borrador para esa rama, **Then** obtiene un esqueleto con
   exactamente los archivos que la review va a cubrir, y el estado del
   repositorio queda sin cambios.
2. **Given** un borrador completado y validado, **When** el revisor inicia la
   review de esa rama, **Then** la review entra en modo walk siguiendo ese
   orden, con el *why* de cada entrada disponible.
3. **Given** un borrador con errores (archivos faltantes, consignas sin
   completar), **When** el revisor lo valida, **Then** la validación falla
   indicando qué corregir, y nada del estado de la review se modifica.
4. **Given** una review en curso iniciada sobre un borrador, **When** el
   revisor la termina, **Then** las ediciones extraídas contienen únicamente
   sus cambios sobre el código: el borrador no aparece entre ellas.
5. **Given** un PR cuyo autor sí escribió walkthrough, **When** el revisor
   inicia la review sin haber creado ningún borrador, **Then** el
   comportamiento es idéntico al actual (walk sobre el walkthrough del autor).

---

### User Story 2 - El asistente de inicio ofrece armarlo (Priority: P2)

Un revisor abre el asistente de inicio en su editor y elige la rama. Al llegar
al paso de "cómo querés leerlo", además de las opciones de siempre ve una para
armar el orden de lectura, porque el PR no trae ninguno. La elige: se le abre
el borrador y aparece un aviso que se queda esperando, sin bloquearle el
editor. Completa el borrador con calma, vuelve al aviso y confirma. Si algo
está mal, el aviso se lo dice y sigue esperando. Cuando está bien, la review
arranca en modo walk.

**Why this priority**: Es donde la feature se vuelve descubrible. Un revisor
que no lee la documentación de la CLI nunca se entera de que puede armarse el
orden; el asistente se lo ofrece en el momento exacto en que le falta.

**Independent Test**: Abrir el asistente sobre un PR sin walkthrough y
comprobar que la opción aparece, que el aviso espera sin bloquear la edición,
que un borrador inválido devuelve al aviso con el motivo, y que uno válido
inicia la review en modo walk.

**Acceptance Scenarios**:

1. **Given** un PR sin walkthrough, **When** el revisor llega al paso de forma
   de lectura, **Then** ve una opción para armar el orden de lectura.
2. **Given** que eligió esa opción, **When** se crea el borrador, **Then** se
   le abre para editar y el aviso queda visible con las acciones de continuar
   y cancelar, sin impedirle escribir en el archivo.
3. **Given** un borrador incompleto, **When** confirma, **Then** ve el motivo
   concreto del rechazo y el aviso sigue disponible para reintentar.
4. **Given** un borrador válido **sin** entradas marcadas como esenciales,
   **When** confirma, **Then** la review arranca en modo walk sin preguntarle
   nada más.
5. **Given** un borrador válido **con** entradas marcadas como esenciales,
   **When** confirma, **Then** se le ofrece elegir entre el recorrido completo
   y sólo las esenciales, y la review arranca según lo que elija.
6. **Given** un borrador a medio completar, **When** el revisor cierra el
   editor y más tarde reabre el asistente sobre la misma rama, **Then** la
   opción ofrece continuar el borrador existente en vez de empezar de cero.

---

### User Story 3 - Lo mismo desde IntelliJ IDEA (Priority: P3)

Un revisor que trabaja en IntelliJ recorre el mismo asistente, con la misma
opción, el mismo aviso que espera sin bloquear el IDE y el mismo resultado.

**Why this priority**: Paridad de producto entre clientes. Depende de lo
mismo que la historia 2 y no aporta capacidad nueva, pero sin ella el plugin
queda con una carencia visible frente a la extensión.

**Independent Test**: Recorrer el asistente del plugin sobre un PR sin
walkthrough y comprobar los mismos resultados que en la historia 2.

**Acceptance Scenarios**:

1. **Given** un PR sin walkthrough, **When** el revisor llega al paso de forma
   de lectura en el plugin, **Then** ve la misma opción con el mismo texto que
   en la extensión.
2. **Given** que eligió esa opción, **When** aparece el aviso de espera,
   **Then** puede seguir editando el borrador en el IDE mientras está visible.

---

### Edge Cases

- **El PR cambia mientras el borrador está a medio escribir** (el autor
  pushea): la validación reporta la diferencia entre los archivos del borrador
  y los del PR, nombrando cuáles sobran y cuáles faltan. Si el revisor inicia
  la review igual, las entradas que ya no aplican se ignoran y los archivos sin
  entrada se leen al final, sin abortar la review — el mismo trato que recibe
  hoy un walkthrough del autor que quedó viejo.
- **El borrador queda sin completar y el revisor lo abandona**: sobrevive
  donde está, invisible para el repositorio, y se recupera al volver a pedirlo.
  La limpieza de datos de review lo elimina junto con el resto del estado.
- **El revisor pide el borrador para una rama que no existe o sin base
  configurada**: falla con el mismo mensaje accionable que ya da el inicio de
  review en esas condiciones, sin crear nada.
- **El PR no cambia ningún archivo respecto de la base**: no hay nada que
  ordenar; se rechaza con un mensaje que lo explique, sin crear un borrador
  vacío.
- **El revisor elige leer sólo las entradas esenciales pero no marcó
  ninguna**: la opción no se le ofrece, porque la viabilidad la reporta la CLI
  y no la adivina el cliente.
- **Hay un borrador para una rama y el revisor arranca la review de otra**: el
  borrador de la primera no interviene de ninguna forma.
- **El revisor pausa una review sobre su borrador y luego limpia**: la limpieza
  se lleva los borradores sueltos, no el de la review pausada; al retomarla,
  sigue leyendo en el mismo orden y por la misma entrada.
- **El autor publica un walkthrough después de que el revisor armó el suyo**:
  la review sigue usando el del revisor, que es el marcado como propio; el del
  autor no se pierde ni se pisa, y vuelve a regir en cuanto el revisor elimina
  su borrador.
- **El revisor completa el borrador con una herramienta que guarda con saltos
  de línea de Windows o con marca de orden de bytes**: se lee igual que
  cualquier walkthrough, sin que ningún archivo desaparezca del orden.

## Requirements *(mandatory)*

### Functional Requirements

#### El borrador y su ciclo de vida

- **FR-001**: El revisor MUST poder generar un esqueleto de walkthrough para
  una rama bajo review sin estar parado en ella, indicándola igual que se la
  indica al iniciar una review, y con la rama actual como valor por omisión.
- **FR-002**: El esqueleto MUST listar exactamente los archivos que la review
  de esa rama va a cubrir, resolviendo el rango con las mismas reglas que el
  inicio de review (base configurada, origen remoto o local, pliegue de la
  base ya integrada).
- **FR-003**: El borrador MUST almacenarse fuera del árbol de trabajo
  versionado, de modo que no aparezca como cambio del repositorio, no impida
  iniciar una review y no requiera ninguna acción para deshacerlo.
- **FR-004**: El borrador MUST sobrevivir al cierre del editor y a reintentos,
  y MUST poder recuperarse para seguir completándolo.
- **FR-005**: El sistema MUST rechazar sobrescribir un borrador existente
  salvo que el revisor lo pida explícitamente.
- **FR-005a**: El revisor MUST poder generar un borrador propio incluso para
  un PR que ya trae walkthrough del autor, con el conocimiento explícito de
  que el suyo tendrá precedencia durante la review.
- **FR-006**: El revisor MUST poder validar el borrador con los mismos
  criterios que se aplican al walkthrough del autor: consignas sin completar,
  archivos del PR ausentes, entradas que ya no corresponden al PR, rutas
  duplicadas y uso incorrecto de la marca de entrada esencial.
- **FR-007**: La validación MUST informar cada problema de forma accionable,
  nombrando los archivos involucrados, y MUST no modificar nada cuando falla.
- **FR-008**: La limpieza del estado de review MUST eliminar los borradores
  junto con el resto de los datos de la review.
- **FR-008a**: Pausar una review MUST poner su borrador a salvo de esa
  limpieza, del mismo modo en que ya protege las ediciones: retomar una review
  pausada MUST devolver el mismo orden de lectura con el que se pausó. La
  limpieza MUST seguir eliminando los borradores que no pertenecen a ninguna
  review pausada.
- **FR-009**: Un borrador MUST no aparecer nunca entre las ediciones que la
  review extrae al finalizar.

#### Efecto sobre la review

- **FR-010**: Al iniciar una review, el sistema MUST usar el borrador local
  del revisor si existe, y el walkthrough commiteado del PR en caso contrario.
- **FR-011**: Una review iniciada sobre un borrador MUST comportarse
  exactamente igual que una iniciada sobre un walkthrough del autor:
  navegación entre entradas, texto explicativo por archivo, recorrido
  restringido a las entradas esenciales, y comparación entre revisiones.
- **FR-011a**: La comparación entre dos revisiones de una rama MUST usar el
  borrador del revisor cuando exista para esa rama, de modo que la misma rama
  nunca se lea en dos órdenes distintos según el comando. Cuando la comparación
  no nombra una rama (revisiones sueltas), MUST usar el walkthrough del autor,
  que es la única referencia disponible.
- **FR-012**: Un borrador válido pero no formalmente validado MUST ser
  legible: la validación es un control de calidad, no un requisito para leer.
- **FR-013**: Un borrador viejo o dañado MUST degradar la review a diff
  completo con una nota, nunca abortarla.
- **FR-014**: Generar o completar un borrador MUST no alterar el modo de una
  review ya iniciada.
- **FR-014a**: Una review que corre sobre un borrador del revisor MUST
  identificarse como tal ante quien la lee, de forma discreta y en todas las
  superficies donde se informa el modo, para que el revisor no atribuya al
  autor del PR un orden y unos *why* que escribió él.

#### Lo que reportan los clientes

- **FR-015**: El informe de configuración de una rama MUST indicar, además de
  las formas de lectura hoy viables, si para esa rama se puede armar un orden
  de lectura y si ya hay un borrador empezado — de modo que ningún cliente
  necesite inspeccionar el borrador por su cuenta.
- **FR-016**: El asistente de inicio MUST ofrecer armar el orden de lectura en
  el mismo paso en que hoy se elige cómo leer el PR, con el texto diferenciado
  según haya que empezarlo o continuarlo.
- **FR-016a**: El asistente MUST NO ofrecer armar el orden de lectura cuando el
  PR ya trae walkthrough del autor y el revisor no tiene borrador propio para
  esa rama: en ese caso el paso se comporta como hoy. Reemplazar un walkthrough
  del autor queda disponible sólo por invocación explícita desde la terminal.
- **FR-017**: Al elegir esa opción, el cliente MUST crear el borrador, abrirlo
  para editar y presentar un aviso que permanezca disponible hasta que el
  revisor actúe, **sin** impedirle editar el archivo mientras tanto.
- **FR-018**: El aviso MUST ofrecer continuar y cancelar. Al continuar, el
  cliente MUST validar el borrador; si la validación falla, MUST mostrar el
  motivo y volver a dejar el aviso disponible, tantas veces como haga falta.
- **FR-018a**: Cancelar MUST devolver al revisor al paso de forma de lectura,
  conservando el borrador, de modo que pueda iniciar la review de otra forma en
  ese mismo momento y retomar el orden de lectura más adelante.
- **FR-019**: Con la validación en verde, el cliente MUST volver a consultar
  las formas de lectura viables y MUST ofrecer elegir entre el recorrido
  completo y sólo las entradas esenciales **únicamente** cuando esa segunda
  opción sea viable; en caso contrario MUST continuar sin preguntar.
- **FR-020**: Si el revisor abandona el flujo, MUST poder retomarlo reabriendo
  el asistente sobre la misma rama, sin perder lo que ya escribió.
- **FR-021**: El plugin de IntelliJ MUST ofrecer el mismo flujo con los
  mismos textos y el mismo aviso no bloqueante, sin exigir paridad visual.

#### Documentación

- **FR-022**: Los dos README (inglés y español) MUST documentar la superficie
  nueva en el mismo cambio.
- **FR-023**: La documentación MUST dejar explícito que el producto no
  completa el borrador ni se conecta con ningún servicio para hacerlo.

### Key Entities

- **Borrador de walkthrough (draft)**: orden de lectura escrito por el
  revisor para una rama determinada. Vive asociado a los datos internos de la
  review, no al árbol de trabajo. Uno por rama. Mismo formato que el
  walkthrough del autor: preámbulo, entradas numeradas con su *why*, y marca
  de entrada esencial.
- **Walkthrough del autor (sidecar)**: el que viaja commiteado en el PR. No
  cambia con esta feature; pasa a ser la segunda opción cuando el revisor
  tiene un borrador propio.
- **Oferta de lectura**: cada forma en que la CLI declara que se puede leer una
  rama. Esta feature agrega la de armar el orden de lectura, con dos variantes
  según haya borrador empezado o no.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un revisor puede pasar de "este PR no tiene orden de lectura" a
  "estoy leyéndolo en orden" **sin ejecutar ni una sola operación que altere
  el historial o el árbol del repositorio** (sin `add`, `commit`, `stash`,
  `reset` ni descarte de cambios).
- **SC-002**: En cualquier punto del flujo, `git status` reporta exactamente
  lo mismo que antes de empezar.
- **SC-003**: Desde el asistente, armar el orden de lectura y arrancar la
  review se hace **sin salir del flujo**: el revisor no tiene que volver a
  abrir el asistente ni recordar un comando para retomar.
- **SC-004**: Un borrador a medio completar sobrevive al cierre del editor y se
  recupera en el primer intento, sin que el revisor tenga que buscar dónde
  quedó.
- **SC-005**: Todas las capacidades del modo walk (navegación, texto por
  archivo, recorrido de esenciales, comparación entre revisiones) funcionan
  sobre un borrador sin diferencia observable respecto de un walkthrough del
  autor.
- **SC-006**: Ningún borrador aparece jamás en las ediciones extraídas al
  finalizar una review, en ninguna combinación de modo, rango y origen.
- **SC-007**: Un borrador inválido nunca deja la review en un estado a medias:
  o se corrige y arranca, o no arranca nada.
- **SC-008**: Los tres clientes (terminal, extensión, plugin) ofrecen el mismo
  conjunto de decisiones al revisor, tomadas siempre a partir de lo que
  reporta la CLI.
- **SC-009**: En una review sobre un borrador propio, el revisor puede saber
  de un vistazo —sin abrir ningún archivo ni ejecutar ningún comando extra—
  que el orden de lectura lo escribió él y no el autor del PR.
- **SC-010**: Un revisor que se arrepiente después de haber pedido el borrador
  puede iniciar la review de otra forma sin rehacer ningún paso del asistente y
  sin perder lo que ya escribió.
- **SC-011**: Ninguna secuencia de pausar y limpiar deja a un revisor sin el
  orden de lectura de una review pausada; recuperarlo no requiere reescribirlo.

## Assumptions

- **Lo pausado sobrevive a la limpieza.** El borrador sigue la misma regla que
  ya rige para las ediciones de una review pausada, en vez de estrenar una regla
  propia. La limpieza sigue recogiendo los borradores sueltos.
- **El revisor completa el borrador por sus propios medios.** El producto
  entrega el esqueleto con la consigna escrita y valida el resultado; entre esos
  dos momentos no interviene. Se asume que quien lo complete —una persona o un
  agente— tiene acceso al diff del PR por otras vías.
- **El esqueleto actual sirve tal cual para el revisor.** Su redacción está
  pensada para quien anota un PR, sin depender de que sea el autor; se asume
  que no hace falta un texto distinto según el rol.
- **Cancelar conserva el borrador y devuelve a elegir cómo leer.** Es
  invisible para el repositorio y no cuesta nada dejarlo; permite retomar más
  tarde y se elimina con la limpieza de datos de review. Arrepentirse del orden
  de lectura no debe costar la review entera.
- **El borrador del revisor tiene precedencia sobre el del autor.** Si existen
  los dos, manda el propio: es una decisión deliberada del revisor, que además
  queda señalada durante toda la review. El asistente no propone ese camino
  cuando el PR ya trae walkthrough; hay que pedirlo desde la terminal.
- **Un borrador por rama.** No se contemplan variantes ni versiones múltiples
  del mismo orden de lectura.
- **El borrador es local y personal.** No se comparte, no se sincroniza y no
  se propone al autor del PR. Compartirlo, si alguna vez se quiere, es una
  feature aparte.
- **La CLI sigue siendo la única fuente de viabilidad.** Los clientes no leen
  ni interpretan el borrador: sólo muestran lo que la CLI reporta e invocan
  comandos.
- **El flujo del autor no se toca.** `walkthrough init` y `build` siguen
  operando sobre el sidecar commiteado con el comportamiento actual.
- **Alcance por fases.** La CLI va primero porque el informe que consumen los
  clientes depende de ella; extensión y plugin van después, en ese orden.
