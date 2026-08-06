# Feature Specification: El ciclo de una review, completo desde el panel

**Feature Branch**: `005-ciclo-review-panel`

**Created**: 2026-08-04

**Status**: Draft

**Input**: User description: "quiero que ahora se pueda iniciar una review desde la
extensión de VS Code, seleccionando incluso el modo en el que se va a iniciar, y luego
también quiero que se pueda finalizar, también pudiendo seleccionar con cuál de las
distintas flags, y que se pueda guardar la review […] que siga respetando la spec uno,
la filosofía" / "1- entra [`abort` junto con `start`]" / "2- no tengo ni idea, tomá la
mejor decisión, controlá los errores de la mejor manera en caso de que haya" /
"3- `--local` entra, no recuerdo la dif con `--offline`, pero si siguen la misma
filosofía, entra también, es importante por si no hay red o no se quiere hacer un
fetch, ¿debería ser como una config más global quizá? no lo sé, `--delta` también" /
"por otro lado, la config del base al que se va a comparar, ¿no debería estar mediante
un porcelain o algo del estilo? si eso cambia el lugar donde se guarda, ¿qué?"

## Contexto y Motivación *(el porqué)*

### El problema

El panel del editor ([`002-extension-vscode`](../002-extension-vscode/spec.md))
sabe leer una review y moverse dentro de ella. No sabe **abrirla ni cerrarla**.

El revisor que abre el editor sin review activa ve un estado vacío que le
explica que no hay ninguna en curso y lo manda a la documentación a aprender un
comando. El que termina de leer una review y quiere quedarse con sus ediciones
tiene que volver a la terminal, acordarse de qué verbo era y de qué flag quería.
El que necesita dejar la review a un lado para atender otra cosa, también —
aunque **retomarla** ya se hace con un clic desde el propio panel, porque
`continue` sí entró en `002`.

O sea: el editor cubre el medio del ciclo y ninguna de las dos puntas. Y el
diferencial del producto es que la review vive en el working tree, que es
exactamente donde el revisor ya está parado. Mandarlo a la terminal para abrir y
para cerrar es pedirle que sostenga los dos contextos que la extensión existe
para eliminar, corridos del medio a los extremos.

### Por qué importa ahora

Porque la exclusión que dejó esto afuera era **explícitamente temporal**.
`002` lo dice con todas las letras:

> **No incluye los verbos consecuentes.** `finish`, `abort` y `save` cambian
> ramas y refs. El proyecto trata el riesgo de forma asimétrica, y ponerlos a un
> clic **en una primera versión** —donde el usuario todavía no tiene modelo
> mental de qué hace cada uno— invierte esa asimetría.

La condición que justificaba la exclusión era la falta de modelo mental en una
primera versión. Con el panel construido y dos features de paridad encima
([`003`](../003-paridad-cli-panel/spec.md),
[`004`](../004-listado-archivos-whole/spec.md)), el revisor que llega a este
punto ya vio en qué consiste una review, en qué modo está y qué archivos toca.
La asimetría de riesgo no se abandona: se traduce. Lo que en la terminal es
"escribir el verbo completo a propósito", en el editor es una confirmación que
dice en concreto qué va a pasar — que es el molde que `002` ya fijó para
`continue` (su FR-033) y que esta feature extiende al resto del ciclo.

Hay además una razón que no es de comodidad sino de coherencia: el estado vacío
del panel es, según `002`, "la primera pantalla que ve todo el mundo, incluido
quien instala la extensión sin conocer el producto". Hoy esa pantalla sabe
resolver por sí sola el caso de la CLI ausente (su SC-008: "un revisor que nunca
usó el producto llega desde el panel a tener la CLI instalada sin salir del
editor") y no sabe resolver el paso inmediatamente siguiente, que es empezar a
usarla.

### La pregunta del `base`, y por qué ordena media feature

El origen del pedido incluye una pregunta que resulta ser el eje técnico de todo
lo demás: *"la config del base al que se va a comparar, ¿no debería estar
mediante un porcelain o algo del estilo? si eso cambia el lugar donde se guarda,
¿qué?"*.

La respuesta es sí, y el "¿qué?" es precisamente el argumento. Hoy la rama base
contra la que se arma el rango vive en una clave de configuración del
repositorio. Si el panel la leyera de ahí, el lugar de almacenamiento pasaría a
ser parte del contrato de facto: moverlo —o volverlo derivado, o admitir un
segundo origen— rompería al consumidor sin que nada lo declare. Es exactamente
lo que `002` prohíbe en su tabla de prohibiciones ("Leer `branch.review/*.review*`
u otra config de git") y lo que el contrato porcelain existe para evitar: el
consumidor pregunta *cuál es la base efectiva* y la CLI responde, sin que el
consumidor sepa nunca de dónde salió.

Y hay un hueco concreto: la base **ya se reporta** por el contrato, pero sólo
mientras hay una review en curso en modo whole. Para *iniciar* una review hace
falta saberla **antes** de que la review exista — justo en el estado donde el
contrato hoy no reporta nada. Lo mismo pasa con el marcador que habilita el
rango incremental y con el remoto por defecto. Esta feature cierra ese hueco por
donde corresponde: agregando al contrato, no leyendo config por izquierda.

### Qué habilita

Que el ciclo entero de una review —abrirla eligiendo cómo leerla, dejarla a un
lado, retomarla, cerrarla quedándose con las ediciones, deshacer ese cierre, o
cancelarla sin consecuencias— ocurra dentro del editor, sin que el revisor tenga
que recordar la superficie de comandos, y sin que ninguna de esas acciones sea
más fácil de disparar por accidente de lo que es hoy escribirla a mano.

### Qué NO es esto

- **No mueve estado ni lógica a la extensión.** Sigue intacta la premisa de
  `002`: el panel no lee config, no mueve refs, no toca el índice. Si algo que
  necesita no está en el contrato, se agrega al contrato. Esta feature agrega
  bastante, y ése es el punto.
- **No inventa comportamiento que la CLI no tenga.** En particular no existe un
  "modo walk" que se elija: la CLI *detecta* el walkthrough y entra en walk sola.
  El panel ofrece lo que la CLI ofrece —el automático, commit por commit,
  ignorar el walkthrough— y nada más.
- **No es un formulario de flags.** La superficie de opciones de `start` no se
  traduce campo por campo a una interfaz; se ofrecen elecciones con significado.
- **No incluye los verbos destructivos sin inversa.** `clean` y `forget` borran
  ramas, refs y marcadores que no vuelven. Quedan fuera, y el criterio por el que
  quedan fuera se escribe abajo para que no haya que re-litigarlo feature a
  feature.
- **No incluye autoría de walkthroughs** (`walkthrough init` / `build`), ni
  `compare` ni `preview`. La primera sigue siendo flujo de autor, como en `002`;
  las otras dos no participan del ciclo de una review de PR.
- **No es un cliente de GitHub.** El panel no lista pull requests, no consulta
  ninguna API remota y no sabe qué es un PR más allá de la rama que se le nombre.
- **No reemplaza al panel de control de código fuente.** Después de un cierre las
  ediciones quedan staged en una rama y hay que revisarlas y commitearlas: eso es
  lo que el editor ya hace, y se delega ahí igual que se delega el diff.
- **No incluye la publicación en el Marketplace.** Sigue fuera de alcance, como
  en `002`.

### Criterio de admisión de verbos al panel

Para que la próxima feature no tenga que discutir de cero qué entra, la regla
que se aplica acá queda escrita. Un verbo puede ofrecerse desde el panel sólo si
cumple **las tres**:

1. **Es representable.** El estado que produce se puede leer por el contrato
   porcelain. Un verbo que deja al panel sin poder describir dónde quedó el
   usuario no entra hasta que el contrato lo cubra.
2. **Tiene una salida.** Existe una inversa alcanzable desde el mismo panel:
   `save` ↔ `continue`, `finish` ↔ deshacer el cierre, `start` ↔ `abort`.
3. **Pertenece al ciclo.** El revisor lo necesita para abrir, sostener o cerrar
   la review que está leyendo.

`clean` y `forget` fallan (2). `walkthrough init`/`build` fallan (3). Los cinco
verbos de esta feature cumplen los tres, y el segundo criterio es la razón por
la que `abort` entra aunque no se haya pedido: poner `start` a un clic sin la
salida sin consecuencias es el desbalance exacto que `002` quiso evitar.

## Clarifications

### Session 2026-08-04

- Q: ¿La feature incluye configurar la rama base desde el editor, o sólo informar
  que falta y cómo se arregla? → A: Incluye configurarla desde el panel,
  eligiéndola de una lista de ramas en lugar de escribirla a mano.
- Q: ¿Qué se recuerda entre invocaciones, y con qué alcance? → A: Sólo el origen
  (copia remota / copia local / copia local sin red). La forma de lectura y el
  rango se eligen en cada invocación.
- Q: ¿De dónde sale la lista de ramas que el revisor ve en el selector — de la
  CLI, o el panel las lee del repositorio por su cuenta? → A: De la CLI, por el
  contrato, junto al reporte de configuración efectiva. El panel sigue sin leer
  nada del repositorio, así que la frontera que hace verificable a SC-005 queda
  intacta.

## User Scenarios & Testing *(mandatory)*

El actor de todas las historias es **el revisor**. A diferencia de `002`, acá no
se asume que ya sabe iniciar una review: la Historia 1 existe para el que no.

### User Story 1 - Empezar a revisar sin saber el comando (Priority: P1)

El revisor abre en el editor un repositorio donde no hay ninguna review. En
lugar de un cartel que lo manda a la documentación, tiene la acción a mano:
elige qué rama revisar y cómo quiere leerla, confirma, y queda dentro de la
review con el panel mostrando por dónde empezar.

**Why this priority**: es la punta que falta y la que convierte el estado vacío
—la primera pantalla que ve todo el mundo— de callejón en punto de entrada. Sin
esto, ninguna de las otras historias tiene a quién servirle: el revisor que
igual tuvo que ir a la terminal para empezar ya está en la terminal.

**Independent Test**: en un repositorio sin review, iniciar una desde el panel y
verificar contra la CLI que quedó exactamente la misma review que habría dejado
el comando equivalente —misma rama, mismo modo, misma posición— y que el panel
la muestra sin ninguna acción adicional.

**Acceptance Scenarios**:

1. **Given** un repositorio sin review y una rama con walkthrough, **When** el
   revisor inicia la review sin elegir nada especial, **Then** queda en el mismo
   modo que dejaría el comando sin flags —el orden de lectura del autor— y el
   panel muestra la primera entrada.
2. **Given** un repositorio sin review, **When** el revisor pide leerla commit
   por commit, **Then** queda en modo commit por commit con el cursor en el
   primero.
3. **Given** una rama con walkthrough, **When** el revisor pide ignorarlo,
   **Then** queda en una review del diff entero, sin orden de lectura.
4. **Given** que el repositorio no tiene una rama base configurada, **When** el
   revisor va a iniciar una review, **Then** se le indica antes de intentarlo que
   falta ese dato y qué significa, y puede elegirla ahí mismo de una lista en
   lugar de escribirla a mano o irse a la terminal.
5. **Given** que el revisor eligió la base desde el panel, **When** vuelve a
   iniciar otra review en ese repositorio, **Then** esa base ya está configurada
   y no se la vuelve a pedir.
6. **Given** un repositorio con la base configurada, **When** el revisor abre el
   diálogo, **Then** ve contra qué se va a comparar sin tener que buscarlo en
   ningún archivo de configuración, y puede cambiarla desde ahí.
7. **Given** que el revisor tiene cambios sin commitear, **When** intenta
   iniciar, **Then** recibe el mismo diagnóstico que daría la CLI y ninguna
   review queda a medio crear.
8. **Given** una review ya existente para esa rama —activa o pausada—, **When**
   el revisor intenta iniciar otra, **Then** se le informa cuál es y qué hacer
   con ella, sin que el intento destruya nada.

---

### User Story 2 - Salir de una review sin dejar rastro (Priority: P1)

El revisor decide que no va a seguir con la review que abrió. Desde el panel la
cancela: vuelve a la rama donde estaba, la review desaparece y el repositorio
queda como antes de empezarla.

**Why this priority**: es la condición de entrega de la Historia 1, no una
comodidad. El proyecto trata el riesgo de forma asimétrica; ofrecer la entrada a
un clic sin la salida a un clic invierte esa asimetría en vez de trasladarla.
Además es la historia que hace seguro equivocarse al elegir el modo: si el
revisor eligió mal, deshacer cuesta lo mismo que elegir.

**Independent Test**: iniciar una review (desde el panel o la terminal),
cancelarla desde el panel y verificar que el repositorio quedó en el mismo estado
que antes de iniciarla y que el panel volvió al estado vacío.

**Acceptance Scenarios**:

1. **Given** una review activa en cualquier modo, **When** el revisor la cancela
   y confirma, **Then** vuelve a la rama de la que había salido y el panel
   muestra el estado vacío.
2. **Given** una review con ediciones sin guardar en el working tree, **When**
   el revisor la cancela, **Then** la confirmación dice explícitamente que esas
   ediciones se pierden, antes de que se pierdan.
3. **Given** el diálogo de confirmación abierto, **When** el revisor lo descarta,
   **Then** no ocurre absolutamente nada y la review sigue como estaba.

---

### User Story 3 - Quedarse con las ediciones al terminar (Priority: P1)

El revisor terminó de leer y editar. Desde el panel cierra la review eligiendo
dónde quiere que queden sus ediciones, y el editor lo deja parado donde tiene que
revisarlas y commitearlas.

**Why this priority**: es la razón de ser del producto. Todo el resto del ciclo
existe para llegar acá: la review se editaba para que las ediciones salieran a
algún lado. Es también el momento donde el revisor tiene más para perder, y por
lo tanto donde una interfaz que explique qué va a pasar vale más.

**Independent Test**: con una review con ediciones, cerrarla desde el panel con
cada una de las dos ubicaciones posibles y verificar contra la CLI que las
ediciones quedaron staged donde corresponde, en ambos casos.

**Acceptance Scenarios**:

1. **Given** una review con ediciones, **When** el revisor la cierra sin elegir
   nada especial, **Then** sus ediciones quedan staged en la rama de arreglos y
   el editor lo deja ahí, con el panel indicando que hay un cierre en curso y
   cómo deshacerlo.
2. **Given** la misma review, **When** el revisor elige que las ediciones vayan
   sobre la rama del PR en lugar de una aparte, **Then** quedan staged ahí, y la
   diferencia entre las dos ubicaciones se le explica **antes** de elegir.
3. **Given** una review sin ninguna edición, **When** el revisor la cierra,
   **Then** se lo informa como resultado normal —no como error— y no queda ningún
   cierre a medias que haya que deshacer después.
4. **Given** una review cerrada, **When** el revisor mira el panel, **Then** ve
   que hay un cierre pendiente de resolver sobre esa review, y no el estado vacío
   de "no hay ninguna review".
5. **Given** un cierre que la CLI rechaza por una condición del repositorio,
   **When** ocurre, **Then** el revisor ve el diagnóstico de la CLI tal cual y la
   review sigue intacta.

---

### User Story 4 - Deshacer un cierre, o destrabar uno que quedó a mitad (Priority: P2)

El revisor cerró la review y se da cuenta de que le faltaba algo, o el cierre se
frenó porque sus ediciones chocaron con el PR. En los dos casos el panel le dice
en qué estado está y cuál es la acción que corresponde, y la ofrece.

**Why this priority**: es lo que hace reversible a la Historia 3, y es el estado
que hoy el panel **no puede ver siquiera**. Va después porque la Historia 3 ya
es entregable con el diagnóstico de la CLI a la vista; ésta la vuelve operable
sin volver a la terminal.

**Independent Test**: producir cada uno de los dos estados (cierre completo,
cierre frenado por conflicto) y verificar que el panel los distingue entre sí y
del estado normal, y que la acción que ofrece cada uno deja el repositorio como
lo dejaría el comando equivalente.

**Acceptance Scenarios**:

1. **Given** un cierre completo y sin tocar, **When** el revisor lo deshace,
   **Then** vuelve a estar editando la review exactamente donde estaba, con sus
   ediciones intactas.
2. **Given** un cierre sobre el que el revisor ya hizo trabajo nuevo, **When**
   intenta deshacerlo, **Then** se le advierte que ese trabajo se descartaría y
   la acción no ocurre salvo que lo confirme por separado, de forma distinguible
   de la confirmación normal.
3. **Given** un cierre frenado por un choque de ediciones, **When** el revisor
   mira el panel, **Then** ve que hay un cierre trabado, que el working tree
   tiene marcas para resolver, y las dos salidas posibles: continuar una vez
   resuelto, o dar marcha atrás.
4. **Given** ese mismo estado trabado, **When** el revisor intenta avanzar o
   retroceder en la secuencia de lectura, **Then** el panel no se lo permite, en
   lugar de dejarlo operar sobre una review que está a mitad de un cierre.
5. **Given** un cierre trabado ya resuelto en el working tree, **When** el
   revisor pide continuar, **Then** el cierre se completa como si nunca se
   hubiera trabado.

---

### User Story 5 - Dejar la review a un lado (Priority: P2)

Al revisor le cae otra cosa encima. Desde el panel pausa la review: vuelve a
donde estaba trabajando y la review queda guardada con todo lo que había hecho,
lista para retomarla después desde el mismo inventario que el panel ya muestra.

**Why this priority**: cierra un ciclo que está construido a medias — retomar
una review pausada **ya se hace desde el panel** desde `002`, pero pausarla no.
Va después de las anteriores porque el revisor puede vivir sin pausar (cancela y
vuelve a empezar); no puede vivir sin abrir ni sin cerrar.

**Independent Test**: con una review con ediciones en cualquier modo, pausarla
desde el panel, verificar que aparece en el inventario del estado vacío, y
retomarla con la acción que ya existe verificando que las ediciones volvieron.

**Acceptance Scenarios**:

1. **Given** una review con ediciones sin commitear, **When** el revisor la
   pausa y confirma, **Then** vuelve a la rama de la que salió, el panel muestra
   el estado vacío y la review aparece listada como pausada con su modo y su
   posición.
2. **Given** esa review pausada, **When** el revisor la retoma con la acción que
   ya existía, **Then** vuelve a estar donde estaba, con sus ediciones.
3. **Given** una review commit por commit con ediciones en varios pasos, **When**
   se pausa y se retoma, **Then** ninguna de esas ediciones se pierde.
4. **Given** que ya hay una review pausada para esa misma rama, **When** el
   revisor intenta pausar, **Then** recibe el diagnóstico de la CLI y la review
   actual queda intacta.

---

### User Story 6 - Elegir qué se compara y de dónde sale (Priority: P3)

El revisor no quiere el comportamiento por defecto: quiere revisar sólo lo nuevo
desde la última vez, o su copia local de la rama, o trabajar sin red. Elige eso
al iniciar, y no tiene que volver a elegirlo cada vez si es su forma habitual de
trabajar.

**Why this priority**: son ejes reales y pedidos explícitamente, pero el revisor
entrega valor con el comportamiento por defecto desde la Historia 1. Es la
primera historia que se recorta si hay que recortar, y la única cuya ausencia no
rompe el ciclo.

**Independent Test**: iniciar reviews con cada combinación de rango y origen
desde el panel y verificar contra la CLI que el rango resultante es idéntico al
del comando equivalente.

**Acceptance Scenarios**:

1. **Given** una rama ya revisada antes, **When** el revisor pide revisar sólo
   lo nuevo, **Then** la review cubre únicamente los commits agregados desde
   entonces.
2. **Given** una rama que nunca se revisó, **When** el revisor abre el diálogo,
   **Then** la opción de revisar sólo lo nuevo no se le ofrece como si fuera
   viable, porque el dato que la habilita ya se sabe que no existe.
3. **Given** que el revisor trabaja sin conexión, **When** inicia una review sin
   red, **Then** no se intenta ningún acceso remoto y la review se arma con lo
   que hay localmente.
4. **Given** que el revisor eligió una vez trabajar sobre su copia local,
   **When** vuelve a iniciar una review, **Then** esa elección es la que viene
   propuesta, y sigue estando a la vista para cambiarla en esa misma invocación.
5. **Given** un origen y un rango elegidos, **When** el revisor va a confirmar,
   **Then** el diálogo le muestra en una sola frase qué review va a quedar —qué
   rama, contra qué, cómo se lee— antes de crearla.

---

### Edge Cases

- **El remoto pide credenciales.** Iniciar una review accede a la red. Si el
  remoto pide autenticación y no hay nadie que pueda contestarle, la operación no
  puede quedarse colgada hasta un timeout sin decir nada, ni fallar con un
  diagnóstico que no menciona la causa real.
- **La red está caída o el remoto no responde.** Distinto del caso anterior y
  distinto de un error del repositorio.
- **La operación tarda.** Un fetch sobre un repositorio grande no es un refresco:
  el revisor tiene que ver que está pasando algo y el editor tiene que seguir
  usable.
- **El revisor dispara dos veces.** Dos clics sobre cerrar, o cerrar mientras
  todavía corre un pausar. Ninguna de estas operaciones es descartable en
  silencio como sí lo es un avance de cursor.
- **Alguien corrió el verbo en la terminal mientras el diálogo estaba abierto.**
  El estado sobre el que se decidió ya no existe cuando se confirma.
- **La operación se interrumpe a mitad** (el editor se cierra, el proceso muere):
  el repositorio puede quedar en un estado intermedio que el panel tiene que
  poder describir al volver.
- **La rama que se quiere revisar no existe en el remoto**, o existe localmente
  apuntando a otro lado que la copia remota — caso en el que la CLI emite una
  advertencia aunque la operación tenga éxito, y el revisor tiene que llegar a
  leerla.
- **El repositorio no tiene rama base configurada**, y el revisor no sabe qué es
  eso.
- **El nombre de la rama contiene caracteres que hay que tratar con cuidado**, o
  empieza con un guion.
- **Una CLI más vieja que la que introduce los estados nuevos**: el panel no
  puede ofrecer acciones cuyo resultado no sabría leer.
- **El repositorio queda sin ninguna review activa después de un cierre**, pero
  con un cierre pendiente: no es el mismo estado que "nunca hubo una review".

## Requirements *(mandatory)*

Los requisitos de `002` siguen vigentes salvo donde éstos los enmienden
explícitamente. Las referencias con prefijo (`002/FR-001`) apuntan a esa feature.

### Functional Requirements

#### Enmienda del alcance heredado

- **FR-001**: Esta feature MUST enmendar de forma explícita y trazable la
  exclusión de los verbos consecuentes de `002` y la fila correspondiente de su
  lista cerrada de invocaciones permitidas, dejando registrado qué feature la
  cambió y por qué. MUST NOT quedar dos documentos vigentes que se contradigan
  sobre qué puede invocar la extensión.
- **FR-002**: La lista de invocaciones permitidas MUST seguir siendo **cerrada y
  verificable leyendo el código**, y MUST extenderse para acotar también **los
  argumentos** que cada invocación tiene permitido llevar. Un argumento que no
  esté enumerado no puede aparecer en el código.
- **FR-003**: Los verbos que no cumplan el criterio de admisión declarado más
  arriba MUST seguir prohibidos, y su ausencia de la lista MUST NOT leerse como
  permiso tácito.

#### Origen del estado (se mantiene)

- **FR-004**: La extensión MUST seguir obteniendo todo el estado invocando la
  CLI. MUST NOT leer configuración, refs ni ramas del repositorio para decidir
  qué ofrecer, qué habilitar o qué mostrar (`002/FR-001`).
- **FR-005**: La extensión MUST cambiar el estado únicamente invocando verbos, y
  MUST NOT escribir configuración ni mover refs por su cuenta (`002/FR-002`),
  incluida la configuración que esta feature necesita leer.
- **FR-006**: La extensión MUST NOT parsear la salida humana de ninguno de los
  verbos nuevos. El estado posterior a una invocación se obtiene volviendo a
  consultar el contrato.

#### Configuración efectiva del repositorio

- **FR-007**: La CLI MUST exponer por el contrato, de forma legible por máquina y
  **sin que haga falta una review activa**, la configuración que determina cómo
  se armaría una review: al menos la rama base efectiva, el remoto efectivo y si
  existe un punto de referencia de última review para una rama dada.
- **FR-008**: Ese reporte MUST distinguir "configurado" de "ausente" sin recurrir
  a valores centinela, y MUST NOT exponer dónde está guardado cada dato, de modo
  que cambiar el lugar de almacenamiento no rompa a ningún consumidor.
- **FR-009**: La extensión MUST tomar la base, el remoto y la disponibilidad del
  rango incremental de ese reporte, y de ningún otro lugar.
- **FR-009a**: La CLI MUST exponer también, por el mismo contrato y sin review
  activa, las **ramas candidatas** del repositorio: las que se pueden revisar y
  las que se pueden fijar como base. La extensión MUST tomarlas de ahí y MUST NOT
  enumerar ramas por su cuenta ni a través de la integración de git del editor,
  cuya excepción sigue acotada a descubrir el repositorio y saber que algo
  cambió.
- **FR-009b**: Ese listado MUST distinguir las ramas por su origen —las del
  remoto efectivo y las locales—, porque de eso depende cuál corresponde ofrecer
  según el origen elegido (FR-014), y MUST excluir las ramas propias del producto
  (`review/*`, `review-saved/*`, `review-fixes/*`), que la CLI ya se niega a
  revisar.
- **FR-010**: El panel MUST mostrar, antes de que el revisor confirme, contra qué
  se va a comparar la review, y MUST señalar como condición pendiente el caso de
  que no haya base configurada, explicando qué es, en lugar de dejar que el
  intento falle.
- **FR-010a**: Los revisores MUST poder fijar la rama base desde el panel,
  eligiéndola de una lista en lugar de escribirla, tanto cuando falta como cuando
  quieren cambiar la que hay. La elección MUST persistir para las reviews
  siguientes de ese repositorio.
- **FR-010b**: La CLI MUST ofrecer la forma de fijar esa configuración, y la
  extensión MUST usarla: escribirla directamente sigue prohibido (FR-005). Esa
  superficie MUST cubrir la misma configuración que FR-007 reporta, para que leer
  y escribir no queden asimétricos.

#### Iniciar una review

- **FR-011**: Los revisores MUST poder iniciar una review desde el panel,
  eligiendo qué rama revisar de las candidatas que reporta la CLI, con la rama
  actual propuesta por defecto —el mismo criterio que aplica la CLI cuando no se
  le nombra ninguna. El listado MUST ser filtrable, porque un repositorio puede
  tener cientos de ramas.
- **FR-012**: El panel MUST ofrecer, como elección de **cómo leer** la review,
  exactamente las alternativas que la CLI tiene: el comportamiento automático (el
  orden de lectura del autor si el PR trae uno, y si no el diff entero), commit
  por commit, e ignorar el orden de lectura. MUST NOT presentar el modo con orden
  de lectura como una elección explícita, porque la CLI no la ofrece: lo detecta.
- **FR-013**: Cada alternativa MUST estar acompañada de qué implica para la
  lectura, no sólo de su nombre.
- **FR-014**: Los revisores MUST poder elegir el rango incremental (sólo lo nuevo
  desde su última review) y el origen (la copia remota de la rama, su copia local,
  o su copia local sin acceso a la red). El panel MUST explicar la diferencia
  entre las dos últimas, porque decide si hay acceso a la red *y* contra qué se
  resuelve la base.
- **FR-015**: El panel MUST NOT ofrecer el rango incremental como viable cuando el
  reporte de configuración ya indica que no existe punto de referencia para esa
  rama **en el origen elegido** (marker remoto vs local son ejes disjuntos; un
  marker del otro origen no cuenta); MUST NOT anticipar ninguna otra condición
  de fallo (`002/FR-033`).
- **FR-016**: La elección de origen —y **sólo** ésa— MUST poder fijarse como
  preferencia persistente, y MUST seguir visible y modificable en cada
  invocación: cambia qué instantánea se revisa, así que nunca puede quedar
  invisible. La forma de lectura y el rango MUST elegirse en cada invocación, sin
  memoria.
- **FR-016a**: Esa preferencia MUST poder fijarse tanto para el revisor —la misma
  en todos sus repositorios, que es el caso que la motiva: trabajar sin red— como
  para un repositorio en particular, con la del repositorio ganando. MUST NOT
  alterar el comportamiento de la CLI: sólo decide qué viene propuesto.
- **FR-017**: Antes de confirmar, el panel MUST resumir en una frase la review
  que va a quedar: rama, contra qué, y cómo se va a leer.

#### Cerrar, deshacer y pausar

- **FR-018**: Los revisores MUST poder cerrar la review desde el panel eligiendo
  dónde quedan sus ediciones, con la diferencia entre las dos ubicaciones
  explicada antes de elegir.
- **FR-019**: La extensión MUST presentar "no había ediciones que extraer" como
  resultado normal y no como fallo.
- **FR-020**: Los revisores MUST poder deshacer un cierre desde el panel, y MUST
  poder continuar un cierre que se frenó por un choque de ediciones.
- **FR-021**: El descarte forzado de trabajo hecho después de un cierre MUST
  requerir una confirmación distinguible de las demás, que nombre qué se
  descarta. MUST NOT ocurrir como consecuencia de la confirmación normal ni de un
  reintento.
- **FR-022**: Los revisores MUST poder pausar la review desde el panel, y la
  review pausada MUST aparecer en el inventario que el panel ya lista, retomable
  con la acción que ya existe.
- **FR-023**: Los revisores MUST poder cancelar la review desde el panel; la
  confirmación MUST decir explícitamente que las ediciones no guardadas se
  pierden.

#### Estados nuevos que el contrato debe reportar

- **FR-024**: La CLI MUST reportar por el contrato que sobre una review hay un
  **cierre completo pendiente de resolver**, de modo que el panel pueda
  distinguirlo de "no hay ninguna review" — que es lo que hoy vería.
- **FR-025**: La CLI MUST reportar por el contrato que sobre una review hay un
  **cierre frenado por un choque de ediciones**, de modo que el panel pueda
  distinguirlo de una review normal — que es lo que hoy vería.
- **FR-026**: Esos reportes MUST incluir lo necesario para que el panel nombre la
  review afectada y ofrezca la acción correspondiente, sin derivar nada por su
  cuenta.
- **FR-027**: El panel MUST impedir la navegación por la secuencia de lectura
  mientras haya un cierre trabado sobre esa review.
- **FR-028**: Los estados nuevos MUST agregarse de forma compatible: una CLI que
  los reporte MUST NOT romper a un consumidor que no los conozca, y la extensión
  MUST NOT ofrecer acciones que dependan de ellos contra una CLI que no los
  reporte, presentándolo como el caso de CLI desactualizada que ya existe
  (`002/FR-022`).

#### Riesgo, confirmación y errores

- **FR-029**: Toda acción que cambie de rama, mueva refs o descarte trabajo MUST
  ir detrás de una confirmación explícita que nombre en concreto qué va a pasar,
  siguiendo el molde que `002` fijó para retomar una review pausada.
- **FR-030**: Descartar la confirmación MUST no tener ningún efecto.
- **FR-031**: La extensión MUST preservar el diagnóstico de la CLI tal cual, sin
  reemplazarlo por texto propio (`002/FR-024`), incluidas las advertencias que la
  CLI emite en operaciones que igual tienen éxito.
- **FR-032**: La extensión MUST NOT anticipar condiciones de fallo que sólo el
  repositorio conoce (working tree sucio, rama inexistente, rama local en otro
  punto): las deja fallar y muestra el diagnóstico.
- **FR-033**: Después de cualquiera de estas operaciones —haya tenido éxito o
  no— el panel MUST reflejar el estado real sin que el revisor tenga que
  refrescar nada.

#### Red, demora y concurrencia

- **FR-034**: Cuando una operación acceda a la red, la extensión MUST NOT quedar
  bloqueada de forma indefinida por un pedido de credenciales que nadie puede
  contestar, y MUST hacer llegar al revisor la causa real cuando eso ocurra.
- **FR-035**: Las operaciones que pueden tardar MUST indicar que están en curso y
  MUST NOT bloquear el editor.
- **FR-036**: Estas operaciones MUST NOT solaparse entre sí ni con las que ya
  existen, y —a diferencia del avance de cursor, que se descarta— un pedido
  duplicado MUST NOT ejecutarse dos veces ni desaparecer sin señal.
- **FR-037**: Una operación que ya empezó a modificar el repositorio MUST NOT
  poder ser interrumpida por la extensión, para no dejarla a mitad de camino.
- **FR-038**: Si el estado cambió entre que el revisor decidió y confirmó, la
  extensión MUST NOT ejecutar la acción sobre una premisa caduca.

#### Documentación

- **FR-039**: Todo cambio de superficie de la CLI MUST reflejarse en **los dos
  README** en el mismo cambio.
- **FR-040**: Las acciones nuevas MUST documentarse en el README de la extensión,
  en inglés, como el resto de esa superficie.

### Key Entities

- **Configuración efectiva**: lo que la CLI reporta sobre cómo se armaría una
  review en este repositorio —base, remoto, existencia de un punto de referencia
  previo para una rama—, con independencia de dónde esté guardado.
- **Rama candidata**: una rama que el revisor puede elegir para revisar o fijar
  como base, con el origen del que sale (el remoto efectivo o local). Las ramas
  propias del producto no son candidatas.
- **Intención de review**: la elección todavía no ejecutada de qué rama revisar,
  contra qué, desde qué origen y con qué forma de lectura. Existe entre que el
  revisor elige y confirma; no se persiste, salvo la preferencia de origen.
- **Preferencia de origen**: la elección persistente sobre desde dónde se arman
  las reviews —la copia remota, la local, o la local sin red—, fijable para el
  revisor o para un repositorio. Es lo único que se recuerda entre invocaciones.
  Propone un valor por defecto; nunca decide sola.
- **Cierre pendiente**: una review sobre la que se corrió un cierre que todavía
  no se resolvió. Tiene dos formas: completo (deshacible) y trabado por un choque
  de ediciones (continuable o deshacible).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un revisor que nunca usó el producto llega, desde el estado vacío
  del panel y sin salir del editor, a tener una review abierta y leyéndose —
  incluso partiendo de un repositorio que no tiene ninguna configuración previa
  del producto.
- **SC-002**: El ciclo completo —abrir, leer, pausar, retomar, cerrar— se recorre
  sin escribir ningún comando en ninguna terminal.
- **SC-003**: Para cada forma de lectura y cada combinación de rango y origen, la
  review que deja el panel es indistinguible de la que deja el comando
  equivalente: misma rama, mismo rango, mismo modo, misma posición.
- **SC-004**: Ninguna acción que cambie de rama, mueva refs o descarte trabajo
  ocurre sin una confirmación previa que diga qué va a pasar; una revisión del
  código lo verifica sobre la lista cerrada de invocaciones.
- **SC-005**: Ningún dato que el panel usa para decidir qué ofrecer sale de la
  configuración o las refs del repositorio; una revisión del código lo verifica.
- **SC-006**: Los estados que produce un cierre —completo pendiente, trabado por
  choque de ediciones— se presentan diferenciados entre sí, del estado normal de
  review y del estado vacío, y cada uno indica su salida.
- **SC-007**: Un fallo de red, un pedido de credenciales sin respuesta posible y
  un error del repositorio se presentan diferenciados, y ninguno deja la
  extensión esperando sin explicación.
- **SC-008**: Ninguna de estas operaciones deja el repositorio en un estado que
  el panel no pueda describir al volver a mirarlo, incluso si el editor se cerró
  mientras corría.
- **SC-009**: Una CLI anterior a la que introduce los estados nuevos no hace que
  el panel ofrezca acciones cuyo resultado no sabría leer.
- **SC-010**: Los tres sistemas operativos soportados ejercitan automáticamente,
  en cada cambio, todo lo que no requiere un remoto que pida autenticación —
  incluido que la operación con red se invoque en las condiciones que impiden
  que se cuelgue. Lo que necesita ese remoto se valida a mano y está enumerado,
  no queda implícito.

## Assumptions

- **El contrato porcelain se extiende, no se elude.** Esta feature agrega
  reportes y estados al contrato porque el panel los necesita, siguiendo la
  premisa de `002`: si algo falta, se agrega al contrato. Ninguna extensión del
  contrato rompe a un consumidor existente.
- **La exclusión de `002` era temporal y su condición se cumplió.** El
  razonamiento —falta de modelo mental en una primera versión— quedó saldado por
  el panel ya construido y las dos features de paridad. La asimetría de riesgo se
  traslada a la confirmación, no se abandona.
- **`abort` entra aunque no se haya pedido explícitamente**, por el criterio de
  admisión: es la inversa de `start`, y ofrecer la entrada sin la salida
  desbalancea el riesgo.
- **El editor ya provee la superficie para revisar y commitear lo que un cierre
  produce.** El panel no construye una propia; termina donde empieza el control
  de código fuente.
- **Las ramas candidatas también salen de la CLI.** Enumerar ramas es el primer
  dato del panel que no es estado de review pero sí es estado del repositorio.
  Se resuelve por el mismo camino que el resto —agregándolo al contrato— para que
  la frontera de `002` siga siendo una sola regla verificable de un vistazo, y no
  un juicio caso por caso. La excepción de la integración de git del editor sigue
  acotada a descubrir el repositorio y recibir la señal de cambio.
- **La preferencia persistente de origen no cambia el comportamiento de la CLI**,
  sólo qué viene propuesto en el diálogo.
- **Las versiones de la CLI y de la extensión siguen siendo independientes**, con
  un requisito mínimo declarado, como en `002`.
- **La publicación en el Marketplace sigue fuera de alcance.**
