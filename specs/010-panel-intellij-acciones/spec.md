# Feature Specification: Panel del plugin de IntelliJ con la superficie de acciones del panel de VS Code

**Feature Branch**: `010-panel-intellij-acciones`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "En VS Code el webview dibuja muchos botones en el
panel (Next, Finish, Open, etc.). En IntelliJ hoy el ReviewPanel es más display
de estado + un Refresh; el resto de acciones vive sobre todo en Tools → git
review. Falta pintar/conectar esos controles como en el panel de VS Code.
¿Tiene que verse igual? No: nativo IDEA. ¿Puede tener los mismos botones y
flujos? Sí, es paridad de superficie de producto. Quiero que sea la misma
experiencia de usuario, solo que visualmente se vea como de IDEA. Quiero que
tenga lo mismo, en los mismos lugares a ser posible, solo cambiando a nivel de
estilos, nada más. Es muy importante: no tiene que haber problema si antes usaba
la otra extensión y ahora no sabe dónde encontrar las cosas, o peor, si nunca
usó nada y ahora no lo encuentra. Tiene que estar igual, solo cambiando botones
y cosas del estilo."

## Contexto y Motivación *(el porqué)*

### El problema

La feature 009 entregó el plugin con **paridad de capacidades**: las 27 acciones
del contrato existen y funcionan. Pero la paridad quedó repartida distinto que
en VS Code: la extensión pone los controles **en el panel, junto al estado que
los motiva**; el plugin los pone casi todos en **Tools → git review**, y el panel
quedó como un display de estado con un solo botón (Refresh).

El resultado no es "menos features": es **otra experiencia de uso**. En VS Code
el revisor lee la entrada y avanza con el botón que está debajo del *why*; en
IntelliJ tiene que soltar el panel, abrir un menú de la barra superior, buscar
el verbo entre 24 entradas planas y volver. Lo que en un cliente es un gesto de
lectura, en el otro es una búsqueda en un menú — por cada paso del walkthrough.

Peor: el panel actual **remite explícitamente a otra superficie**. Dice *"Start a
review from the git review actions"* y *"Use the 'Set the Base Branch' action
(Settings → git review)"*. Un panel que explica dónde está el botón en vez de
tener el botón es la evidencia del gap.

### Por qué importa ahora

- El contrato `contracts/client-product-surface.yaml` ya declara `surface:
  panel | action | both` por acción. El plugin cumple la columna `action` y no
  la columna `panel`: el canónico anti-drift está **descrito pero no
  ejercido** del lado IntelliJ.
- El ciclo de lectura (walk/step) es el uso dominante del producto y es
  justamente donde más pesa la diferencia: navegar es la acción que más se
  repite en una sesión.
- Cuanto más tiempo el panel del plugin siga apoyado en textos que mandan al
  menú, más superficie textual hay que rehacer después (esos mensajes
  desaparecen cuando aparecen los controles).

### Qué habilita

Que el revisor en IntelliJ IDEA haga **la misma sesión de review que en VS
Code, con los mismos gestos, en los mismos lugares y en los mismos momentos**.
Dos personas concretas tienen que salir beneficiadas y ninguna perjudicada:

- **Quien viene de la extensión de VS Code** abre el plugin y no tiene que
  reaprender nada: busca el botón donde estaba y ahí está, con otro aspecto.
- **Quien nunca usó ninguno de los dos** encuentra cada cosa donde el diseño ya
  probado la puso, y la documentación del producto (README, landing, capturas)
  le sirve sin traducción mental.

### Qué NO es esto

- **No es copiar la apariencia del webview.** Nada de emular chips, gradientes,
  animaciones ni la tipografía del panel de VS Code. Los controles son los
  nativos del IDE y se ven como el resto de IntelliJ.
- **No es libertad para reorganizar.** La disposición —qué va arriba de qué,
  qué está agrupado con qué, qué es principal y qué es secundario— **sí se
  copia**. Lo único que cambia es con qué se dibuja.
- **No agrega ni saca acciones del producto.** El conjunto sigue siendo el del
  contrato: esta feature cambia **cómo se ven** los controles, no **qué** hay ni
  **dónde** está.
- **No toca la CLI ni el contrato porcelain.** No se agregan invocaciones
  nuevas; todo lo que se pinta ya tiene su acción implementada en el plugin.
- **No elimina el menú Tools → git review.** El menú sigue siendo la superficie
  global, igual que la paleta de comandos en VS Code. El panel se suma, no
  reemplaza.
- **No cambia la extensión de VS Code.** La extensión es la referencia de
  producto; acá se la sigue, no se la modifica.
- **No introduce estado propio en el panel.** Igual que hoy: todo lo que se
  muestra sale del modelo derivado del porcelain de la CLI.

## Invariante rector: mismo lugar, otro estilo

Todo lo que sigue se subordina a esta regla, que es **no negociable** y decide
cualquier duda de diseño que aparezca durante la implementación:

> **Lo único que puede diferir del panel de VS Code es con qué se dibuja cada
> cosa. Qué hay, dónde está, en qué orden, agrupado con qué, con qué rótulo,
> cuándo aparece y con qué gesto se acciona: idéntico.**

Corolarios que se aplican sin volver a preguntar:

1. **Nada se muda de superficie.** Lo que en la extensión está en el cuerpo del
   panel va en el cuerpo del panel; lo que está en la barra de título de la
   vista va en la barra del tool window; lo que está sólo en la paleta de
   comandos se queda sólo en el menú del plugin.
2. **Nada se reordena.** El orden de arriba abajo y de izquierda a derecha se
   conserva, incluidas las filas de dos controles.
3. **Nada cambia de jerarquía.** El control que en la extensión es el principal
   de su pantalla se lee como el principal; los secundarios, como secundarios.
4. **Nada cambia de gesto.** Si allá se acciona con un clic, acá se acciona con
   un clic.
5. **Nada cambia de rótulo.** El texto del control es el mismo, palabra por
   palabra.
6. **Nada cambia de momento.** Aparece, desaparece, se deshabilita y se
   confirma exactamente en las mismas condiciones.
7. **Ante una duda de ubicación, gana el espejo.** Si la convención de IntelliJ
   sugiere un lugar y la extensión usa otro, se usa el de la extensión — salvo
   que el de la extensión sea físicamente imposible en el IDE, y en ese caso se
   elige el equivalente más cercano y se deja escrito por qué.

**Excepción única y explícita: el anclaje del tool window.** La extensión
declara su vista en la barra de actividad izquierda de VS Code; el plugin
mantiene el tool window anclado a la **derecha**, que es la convención de
IntelliJ para paneles auxiliares y donde la izquierda ya está ocupada por
Project. Es una decisión de producto tomada a conciencia, no un descuido: el
tool window se descubre por su botón rotulado en la barra lateral, así que el
lado no afecta a "no sé dónde encontrar las cosas". El invariante rige **dentro**
del panel y entre superficies del IDE; no sobre en qué borde de la ventana lo
ancla la plataforma.

## Superficie a parificar (lo que el panel de VS Code ofrece hoy)

Esta es la referencia normativa de la feature: **los controles que el panel de
la extensión efectivamente pinta**, situación por situación, en su orden. No es
la lista idealizada del contrato (que marca `both` para acciones que el webview
no dibuja); es lo que el revisor ve.

| Situación | Controles del panel, en orden |
|---|---|
| `cli-missing` / `cli-outdated` | comando de instalación copiable (**Copy**), **Other install options**, `stderr` visible |
| `no-review` sin base | **Set the base branch** (principal), párrafo explicativo, línea del remoto, **Change remote** |
| `no-review` con base | inventario arriba: por review, **Continue** (solo guardadas) y **Discard** / **Discard orphan**; debajo **Start a review** (principal); al pie, plegadas: *Other actions* (**Compare revisions**, y en una fila **Walkthrough: Init** + **Walkthrough: Build**), *Settings* (**Change the base branch**, **Change remote**), *Support* (**Star on GitHub**) |
| `finish-pending` | aviso, y en una fila **Clean** (principal) + **Undo finish** |
| `out-of-range` | **How to fix it**, `stderr` visible |
| `error` | **How to fix it**, `stderr` visible |
| `review` modo walk | barra de identidad; notas; entrada; *why*; **open in editor** (solo con *why* presente); fila **File** + **Diff**; fila **◀** + **▶** |
| `review` modo step | barra de identidad; notas; entrada; fila **Diff**; fila **◀** + **▶** |
| `review` modo whole | barra de identidad; notas; título con la cuenta de archivos; fila **Diff** (todos); una fila por archivo que abre su diff |
| `finish-conflict` | barra de identidad; banner con fila **Undo** + **Continue**; notas; entrada **sin** fila de navegación |
| barra de título de la vista (todas) | **Refresh**; y en review: **Finish** (no en solo lectura), **Save**, **Cancel**, **Preview edits** |

Marcas y estados que acompañan a esos controles, en el mismo lugar que allá:
badges `key` / `uncovered` / `edits` en la cabecera de la entrada, `current` /
`orphan` en la fila del inventario, marca de "último abierto" en la lista de
whole, notas de solo lectura / solo claves / base movida / walkthrough degradado
entre la barra y el cuerpo, deshabilitado por acción en curso, deshabilitado en
los extremos de la secuencia, y retiro completo de la navegación con el finish
trabado.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reconocer el panel viniendo de VS Code (Priority: P1)

Un revisor que usó la extensión abre el plugin por primera vez. Sin leer nada,
encuentra cada control donde lo tenía: la navegación debajo de la entrada,
cerrar la review arriba, las herramientas al pie. Lo único que nota distinto es
que los botones son los de IntelliJ.

**Why this priority**: es el requisito explícito de la feature y la condición
que gobierna a todas las demás historias. Si esto no se cumple, tener los
controles no alcanza: el revisor igual no los encuentra.

**Independent Test**: poner las dos pantallas equivalentes lado a lado (misma
situación, mismo modo, mismo repositorio) y verificar que la lista de controles
y su orden coinciden uno a uno; que la única diferencia sea el aspecto.

**Acceptance Scenarios**:

1. **Given** la misma situación en los dos clientes, **When** se comparan los
   dos paneles, **Then** aparecen los mismos controles, con los mismos rótulos,
   en el mismo orden y en los mismos grupos.
2. **Given** un control que en la extensión es el principal de su pantalla,
   **When** se mira el panel del plugin, **Then** ese control se distingue como
   el principal.
3. **Given** un control que en la extensión se acciona con un clic, **When** el
   revisor lo usa en el plugin, **Then** se acciona con un clic.
4. **Given** el tool window del plugin abierto, **When** el revisor compara la
   disposición interna con la del panel de la extensión, **Then** coincide
   bloque por bloque, aunque el tool window esté anclado al otro borde de la
   ventana.
5. **Given** cualquier control, **When** se lo compara con su par, **Then** el
   rótulo es idéntico palabra por palabra.

---

### User Story 2 - Leer y avanzar sin salir del panel (Priority: P1)

El revisor tiene una review activa en modo walk. Lee la entrada, el *why* y
decide mirar el archivo o el diff; después avanza. Todo ocurre dentro del tool
window: abrir el archivo, abrir el diff y moverse por la secuencia son controles
que están ahí, debajo de lo que acaba de leer.

**Why this priority**: es el uso dominante del producto y el gesto que más se
repite en una sesión.

**Independent Test**: con una review walk activa, completar un recorrido de
principio a fin usando únicamente el panel, sin abrir el menú ni la terminal.

**Acceptance Scenarios**:

1. **Given** una review en modo walk parada en una entrada, **When** el revisor
   mira el panel, **Then** debajo del *why* hay una fila con abrir el archivo y
   abrir el diff, y debajo otra fila con anterior y siguiente.
2. **Given** una review en modo step, **When** el revisor mira el panel,
   **Then** la fila de apertura tiene un solo control (el diff del commit), y
   la de navegación queda igual.
3. **Given** el cursor en la primera entrada, **When** el revisor mira el
   control de "anterior", **Then** está visible pero deshabilitado; ídem el de
   "siguiente" en la última.
4. **Given** una acción en curso, **When** el revisor intenta volver a
   accionar, **Then** los controles están deshabilitados hasta que termine.
5. **Given** una entrada con *why* presente, **When** el revisor quiere leerlo
   completo, **Then** justo debajo del texto hay un control para abrirlo en el
   editor; sin *why* presente, ese control no está.
6. **Given** una entrada marcada como esencial, no anotada o con ediciones
   guardadas, **When** se dibuja, **Then** la marca aparece en la cabecera de
   la entrada, junto al número.

---

### User Story 3 - Cerrar, pausar o abandonar la review (Priority: P1)

Terminada la lectura, el revisor cierra la review, la guarda para después, la
cancela o revisa sus ediciones — desde la barra del propio tool window, que es
donde la extensión pone esas acciones. Si el finish quedó a medias o trabado, el
panel se lo dice **y le ofrece la salida ahí mismo**.

**Why this priority**: es el otro extremo del ciclo, y el que más riesgo tiene
si se hace desde el lugar equivocado.

**Independent Test**: con una review activa, cerrarla desde la barra del tool
window; con un finish pendiente, resolverlo desde el aviso; con un finish
trabado, deshacerlo o continuarlo desde el banner.

**Acceptance Scenarios**:

1. **Given** una review activa, **When** el revisor mira la barra de la vista,
   **Then** encuentra refrescar, cerrar, guardar, cancelar y ver ediciones, en
   ese orden.
2. **Given** una review de solo lectura, **When** mira esa barra, **Then**
   cerrar no está disponible, y la nota del panel explica que se sale con
   cancelar.
3. **Given** un finish pendiente, **When** mira el panel, **Then** el aviso que
   explica dónde quedaron las ediciones trae debajo, en una fila, limpiar
   (principal) y deshacer.
4. **Given** un finish trabado en conflicto, **When** mira el panel, **Then**
   el banner —arriba, debajo de la barra de identidad— ofrece deshacer y
   continuar, y la fila de navegación **no está** (no alcanza con estar
   deshabilitada).
5. **Given** cualquier acción destructiva del panel, **When** el revisor la
   activa, **Then** se le pide confirmación antes de ejecutarla, con el mismo
   criterio que en la extensión.

---

### User Story 4 - Arrancar desde el estado vacío (Priority: P1)

Sin review activa, el panel es el punto de entrada: si falta configurar la base
lo pide como acción principal; si ya está configurada ofrece arrancar; y si hay
reviews guardadas o restos, las lista arriba con sus propios controles.

**Why this priority**: es la primera pantalla de todo usuario nuevo, y hoy es
donde el panel manda al menú por texto en vez de ofrecer el control.

**Independent Test**: en un repositorio sin base configurada, llegar a tener
una review activa usando solamente el panel.

**Acceptance Scenarios**:

1. **Given** un repositorio sin base configurada, **When** el revisor abre el
   panel, **Then** elegir la base es la acción principal, seguida del párrafo
   que explica para qué sirve, la línea del remoto y el control para cambiarlo;
   y no hay texto que lo derive a otro menú.
2. **Given** un repositorio configurado y sin review activa, **When** abre el
   panel, **Then** arrancar una review es la acción principal.
3. **Given** reviews guardadas o restos de reviews, **When** abre el panel,
   **Then** las ve listadas **arriba** del bloque de arrancar, con su modo y
   posición, y cada fila trae sus controles: continuar solo si es reanudable,
   descartar si es guardada u huérfana.
4. **Given** una review listada que no admite ningún verbo, **When** el revisor
   la mira, **Then** el panel explica por qué, en el mismo lugar y por el mismo
   gesto que en la extensión.

---

### User Story 5 - Recorrer la lista de archivos en modo whole (Priority: P2)

En una review sin walkthrough, el panel lista los archivos del rango y cada uno
abre su diff con un clic; arriba de la lista hay un control para abrir todos
juntos, y queda marcado el último que se abrió.

**Why this priority**: whole es el modo por defecto cuando no hay walkthrough, y
hoy el plugin muestra los archivos como texto inerte y trunca a los primeros 50.

**Independent Test**: en una review whole con más de 50 archivos, abrir el diff
de un archivo del final de la lista con un clic.

**Acceptance Scenarios**:

1. **Given** una review whole, **When** el revisor mira el panel, **Then** ve
   el título con cuántos archivos toca el rango, debajo el control de "todos",
   y debajo la lista completa, sin cortes ni resúmenes.
2. **Given** esa lista, **When** hace **un clic** en una fila, **Then** se abre
   el diff de ese archivo.
3. **Given** esa lista, **When** usa el control de "todos", **Then** se abren
   todos los cambios del rango juntos.
4. **Given** que ya abrió un archivo antes, **When** vuelve al panel, **Then**
   esa fila está marcada como la última abierta.
5. **Given** un rango que no toca ningún archivo, **When** mira el panel,
   **Then** lo dice explícitamente en vez de mostrar una lista vacía.

---

### User Story 6 - Salir del paso en falso (Priority: P2)

Cuando el estado no permite trabajar —falta la CLI, está vieja, el cursor quedó
fuera de rango, o la lectura del estado falló— el panel muestra el camino de
salida como control, no como instrucción.

**Why this priority**: son las pantallas donde el revisor está más perdido, y
donde un botón vale más que un párrafo.

**Independent Test**: con la CLI ausente del entorno, copiar el comando de
instalación desde el panel; con el cursor fuera de rango, ver la explicación de
la CLI desde el panel.

**Acceptance Scenarios**:

1. **Given** la CLI ausente o vieja, **When** el revisor mira el panel,
   **Then** ve el comando recomendado con su control de copiar al lado, debajo
   la línea de esperar o recargar, y debajo el acceso a las otras formas de
   instalación.
2. **Given** que copió el comando, **When** el control responde, **Then**
   recibe la misma confirmación visible y transitoria que en la extensión.
3. **Given** un cursor fuera de rango o un error de lectura del estado,
   **When** pide ayuda desde el panel, **Then** vuelve a ver el mensaje que la
   CLI ya emitió, que es el que nombra el arreglo.

---

### User Story 7 - Herramientas y configuración al pie (Priority: P3)

Comparar dos puntas, crear o rearmar un walkthrough, cambiar la base o el
remoto, y apoyar el proyecto: al pie del panel en el estado vacío, agrupados en
las mismas tres secciones y plegados por defecto.

**Why this priority**: son acciones ocasionales; su valor está en que existan
sin robarle espacio a "arrancar una review".

**Independent Test**: desde el estado vacío, cambiar la base y lanzar un
compare sin abrir el menú.

**Acceptance Scenarios**:

1. **Given** el estado sin review activa, **When** el revisor mira el pie del
   panel, **Then** encuentra las mismas tres secciones, con los mismos títulos,
   en el mismo orden, plegadas.
2. **Given** ese pie, **When** despliega una sección y el panel se redibuja
   (por ejemplo por una acción en curso), **Then** la sección sigue desplegada.
3. **Given** la base ya configurada, **When** mira la sección de configuración,
   **Then** ve el valor vigente de base y remoto junto al control que los
   cambia, en ese orden.

---

### User Story 8 - El panel avisa que está trabajando (Priority: P3)

Al navegar, el panel no deja en pantalla la entrada anterior con controles que
ya no le corresponden: muestra que está cargando conservando su silueta, y
recién dibuja la entrada nueva cuando la tiene.

**Why this priority**: sin esto los controles nuevos pueden accionarse sobre
datos viejos; es la contracara necesaria de tener botones en el panel.

**Independent Test**: navegar en una review con una CLI lenta y verificar que no
se puede accionar sobre la entrada anterior.

**Acceptance Scenarios**:

1. **Given** una navegación en curso, **When** la respuesta tarda, **Then** el
   panel indica la carga conservando la silueta —incluidos los controles,
   deshabilitados— sin saltar de alto.
2. **Given** una navegación en curso, **When** el revisor intenta accionar
   sobre lo que quedó dibujado, **Then** no ocurre nada.
3. **Given** una respuesta inmediata, **When** el panel se actualiza, **Then**
   no aparece un parpadeo de carga.

---

### Edge Cases

- ¿Qué pasa si el tool window está muy angosto para una fila de dos controles?
  Los controles se apilan conservando el orden y sin salirse de su grupo;
  ninguno se muda a otra parte del panel ni desaparece.
- ¿Qué pasa si el tool window se acopla abajo (horizontal)? El contenido
  scrollea; la disposición relativa se conserva.
- ¿Qué pasa con el escalado de fuente grande o alto contraste? Los rótulos no
  se cortan ni se superponen, y los controles conservan su foco visible.
- ¿Qué pasa si el revisor ya movió el tool window de lugar? Se respeta su
  elección: el espejo aplica al valor por defecto, no a lo que el usuario
  reacomodó.
- ¿Qué pasa si el repositorio no es un target único (cero o varios)? El panel
  no ofrece controles que no puedan ejecutarse: explica la situación como hoy.
- ¿Qué pasa con una review de solo lectura? Cerrar no se ofrece; la nota
  explica que la salida es cancelar.
- ¿Qué pasa con la lectura restringida a entradas clave? La nota lo dice y la
  navegación recorre solo esas entradas.
- ¿Qué pasa si la base se movió y quedan menos entradas que las registradas?
  La nota lo dice y los extremos de la secuencia se calculan sobre el total
  vigente.
- ¿Qué pasa si el walkthrough no cubre el rango? La nota de degradado convive
  con los controles del modo que efectivamente quedó activo.
- ¿Qué pasa con un inventario largo o una lista de archivos larga? El panel
  scrollea; no se trunca contenido.
- ¿Qué pasa si el *why* no existe, falla o todavía carga? Cada caso tiene su
  texto propio, y el control de abrirlo en el editor solo aparece cuando hay
  algo que abrir.
- ¿Qué pasa con una entrada sin asunto o con una CLI que no reporta asuntos?
  El panel degrada al dato que sí tiene, sin dejar huecos.

## Requirements *(mandatory)*

### Functional Requirements

**Paridad de ubicación (no negociable)**

- **FR-001**: El panel del plugin MUST ofrecer, en cada situación, un control
  equivalente para cada control que el panel de la extensión ofrece en esa misma
  situación, y MUST NOT ofrecer ninguno que la extensión no ofrezca ahí.
- **FR-002**: Los controles MUST conservar el orden de la extensión, de arriba
  abajo y de izquierda a derecha, incluida la composición de las filas.
- **FR-003**: Los controles MUST conservar la agrupación de la extensión: lo
  que allá está en una misma fila, bloque, banner o sección plegable, acá
  también.
- **FR-004**: El control principal de cada pantalla MUST distinguirse como tal,
  y los secundarios como secundarios, siguiendo la jerarquía de la extensión.
- **FR-005**: Los rótulos de los controles y los títulos de las secciones MUST
  ser idénticos a los de la extensión, palabra por palabra.
- **FR-006**: El gesto de activación MUST ser el mismo: lo que allá se acciona
  con un clic, acá se acciona con un clic.
- **FR-007**: Ninguna acción MUST mudarse de superficie: lo que en la extensión
  está en el cuerpo del panel va en el cuerpo del panel; lo que está en la barra
  de título de la vista va en la barra del tool window; lo que está sólo en la
  paleta de comandos se queda sólo en el menú del plugin.
- **FR-008**: El tool window MUST conservar su anclaje por defecto a la derecha
  (excepción explícita al corolario 7) y MUST NOT sobreescribir la ubicación si
  el usuario ya la movió.
- **FR-009**: Los controles MUST usar los widgets nativos del IDE y respetar su
  tema, tipografía, iconografía y escalado; el panel MUST NOT imitar la
  apariencia del webview.
- **FR-010**: El panel MUST NOT contener textos que deriven al usuario a otra
  superficie para ejecutar una acción que el panel ya ofrece como control.

**Lectura y navegación**

- **FR-011**: Con una review legible, el panel MUST ofrecer abrir la entrada
  actual en una fila propia debajo de la entrada: en modo walk el archivo y el
  diff; en modo step, solo el diff.
- **FR-012**: Con una review en modo walk o step, el panel MUST ofrecer ir a la
  entrada anterior y a la siguiente, en una fila propia debajo de la anterior.
- **FR-013**: Los controles de navegación MUST estar deshabilitados —visibles,
  no ocultos— cuando el cursor está en un extremo de la secuencia.
- **FR-014**: Con un finish trabado en conflicto, el panel MUST retirar la fila
  de navegación por completo.
- **FR-015**: El panel MUST mostrar las marcas de la entrada actual (esencial,
  no anotada, con ediciones guardadas) en la cabecera de la entrada, sin
  requerir ninguna acción.
- **FR-016**: Cuando la entrada tiene explicación, el panel MUST ofrecer
  abrirla en el editor inmediatamente debajo del texto; cuando no la tiene,
  falló o está cargando, MUST decir cuál de los tres casos es y MUST NOT
  ofrecer ese control.

**Listado de whole**

- **FR-017**: En modo whole, el panel MUST mostrar la cuenta de archivos del
  rango, debajo el control de abrir todos los cambios, y debajo la lista
  completa de archivos, sin truncar.
- **FR-018**: Un clic en un archivo del listado MUST abrir el diff de ese
  archivo.
- **FR-019**: El panel MUST marcar el último archivo abierto.
- **FR-020**: Un rango sin archivos MUST decirse explícitamente.

**Estado vacío e inventario**

- **FR-021**: Sin base configurada, el panel MUST ofrecer elegirla como acción
  principal, seguida de la explicación de para qué sirve, del valor del remoto y
  del control para cambiarlo.
- **FR-022**: Con base configurada y sin review activa, el panel MUST ofrecer
  arrancar una review como acción principal.
- **FR-023**: El panel MUST listar las reviews del repositorio **arriba** del
  bloque de arrancar, con su modo, posición y marcas, y ofrecer en cada fila
  continuar (solo las reanudables) y descartar (guardadas u huérfanas).
- **FR-024**: Cuando una fila del inventario no admite ningún verbo, el panel
  MUST explicar por qué, por el mismo gesto que la extensión.
- **FR-025**: El panel MUST agrupar al pie, en tres secciones plegables con los
  títulos y el orden de la extensión, las herramientas, la configuración (con
  los valores vigentes) y el apoyo al proyecto; plegadas por defecto, y MUST
  conservar lo desplegado entre redibujos.

**Cierre del ciclo y diagnóstico**

- **FR-026**: Con un finish pendiente, el panel MUST ofrecer limpiar y deshacer
  en una fila debajo del aviso que explica dónde quedaron las ediciones.
- **FR-027**: Con un finish trabado, el panel MUST ofrecer deshacer y continuar
  en el banner que anuncia el problema, debajo de la barra de identidad.
- **FR-028**: Sin CLI o con CLI vieja, el panel MUST ofrecer copiar el comando
  recomendado al portapapeles con confirmación visible y transitoria, y llegar
  a las otras formas de instalación.
- **FR-029**: Con el cursor fuera de rango o con un error de lectura del
  estado, el panel MUST ofrecer volver a mostrar el mensaje que la CLI ya
  emitió.

**Comportamiento transversal**

- **FR-030**: Las acciones del ciclo de vida de la review MUST vivir en la
  barra del tool window, en el orden de la extensión y con sus mismas
  condiciones de disponibilidad.
- **FR-031**: Mientras hay una acción en curso, los controles que mutan estado
  MUST estar deshabilitados y MUST NOT ejecutarse.
- **FR-032**: Toda acción destructiva accionada desde el panel MUST pedir
  confirmación, en el mismo momento y con el mismo alcance que en la extensión.
- **FR-033**: Durante una navegación, el panel MUST indicar la carga
  conservando su silueta, MUST impedir accionar sobre lo dibujado, y MUST NOT
  mostrar indicación de carga cuando la respuesta es inmediata.
- **FR-034**: El panel MUST NOT derivar estado por su cuenta: todo lo que
  muestra y todo lo que habilita MUST provenir del modelo derivado del
  porcelain de la CLI.
- **FR-035**: Los controles MUST ser alcanzables y accionables por teclado, con
  foco visible, y MUST exponer un nombre accesible cuando el control es solo un
  ícono.
- **FR-036**: El canónico multi-cliente MUST registrar, por situación, qué
  controles pinta el panel y en qué orden, y la verificación automática del
  repositorio MUST fallar cuando los dos clientes se separen en cualquiera de
  las dimensiones del invariante rector.

### Key Entities

- **Situación**: el estado del panel en un momento dado (sin CLI, CLI vieja,
  sin review, finish pendiente, review, finish en conflicto, fuera de rango,
  error). Determina qué se dibuja y qué controles aplican.
- **Modelo del panel**: la proyección del estado de la review a lo que el panel
  muestra (modo, origen, posición, entrada actual, archivos, notas, ocupado).
  Ya existe y esta feature no lo redefine: lo consume.
- **Control del panel**: un elemento accionable dibujado en el panel, con su
  situación, su posición en el orden, su grupo, su jerarquía, su rótulo, su
  condición de disponibilidad y la acción a la que rutea. Es la unidad que el
  canónico registra y que la verificación compara entre clientes.
- **Fila del inventario**: una review del repositorio con sus marcas y los
  verbos que admite.
- **Entrada**: la unidad de lectura (archivo en walk, commit en step) con su
  posición, marcas y explicación.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Comparadas las pantallas equivalentes de los dos clientes,
  **100%** de los controles coincide en existencia, rótulo, orden, grupo,
  jerarquía y condición de aparición. Diferencias admitidas: cero.
- **SC-002**: Un revisor que usó la extensión encuentra en el plugin, **al
  primer intento y sin ayuda**, los controles de navegar, abrir el diff y
  cerrar la review.
- **SC-003**: Un revisor que nunca usó ninguno de los dos clientes completa una
  sesión entera —configurar la base, arrancar, recorrer todas las entradas,
  abrir archivos y diffs, y cerrar la review— **sin abrir el menú del plugin ni
  una terminal**: 0 usos de esas superficies.
- **SC-004**: **0** textos del panel que remitan a otra superficie para
  ejecutar una acción que el panel ofrece.
- **SC-005**: **0** acciones mudadas de superficie respecto de la extensión, y
  **0** acciones agregadas al panel que la extensión no pinte.
- **SC-006**: **0** clics sin efecto: ningún control accionable produce una
  ejecución imposible (extremos de la secuencia, acción en curso, review de
  solo lectura, fila del inventario no reanudable).
- **SC-007**: En una review whole de 300 archivos, **el 100%** de los archivos
  es alcanzable y se abre con un clic desde el panel.
- **SC-008**: Al navegar, el revisor recibe una señal de que el panel está
  trabajando **antes de los 200 ms** cuando la respuesta no es inmediata.
- **SC-009**: El panel es legible y operable en tema claro, oscuro y alto
  contraste, y con escalado de fuente hasta 200%, sin texto cortado ni
  controles superpuestos, conservando el orden y la agrupación.
- **SC-010**: Todos los controles del panel son alcanzables con teclado
  únicamente, en un orden que sigue la lectura de la pantalla.
- **SC-011**: La documentación de producto (README y landing) describe el panel
  con las mismas palabras para los dos clientes: **0** aclaraciones del tipo
  "en IntelliJ está en otro lado".

## Assumptions

- **La referencia es el panel real de la extensión, no el contrato en
  abstracto.** El contrato marca `both` para acciones que el webview no pinta
  (el registro de invocaciones, el preview en formato resumido, el olvido de
  marcadores, el salto a una entrada por nombre); esas se quedan en el menú del
  plugin, que es el equivalente de la paleta de comandos. Agregarlas al panel
  sería inventar superficie y romper el invariante en la otra dirección.
- **Las tres decisiones de ubicación quedan cerradas por el invariante**, no
  por preferencia: el ciclo de vida va en la barra del tool window porque allá
  está en la barra de título de la vista; el pie plegable va dentro del panel y
  no en un menú de engranaje porque allá está dentro del panel; y el bloque de
  apoyo al proyecto se incluye porque allá está. Ninguna se revisa en
  `/speckit-clarify` salvo que cambie el invariante mismo.
- **El anclaje por defecto del tool window NO se espeja**: se queda a la
  derecha, decidido explícitamente. Es la única excepción al corolario 7 y está
  acotada al borde de la ventana donde la plataforma ancla el panel; nada de lo
  que pasa **dentro** del panel queda cubierto por ella.
- **Los diálogos nativos del IDE son el equivalente de los *quick picks*** de
  la extensión: mismo momento, mismo contenido, misma confirmación. La
  plataforma decide dónde se dibuja la ventana; eso es estilo, no ubicación.
- **Ninguna acción nueva se implementa**: las 27 ya existen en el plugin; esta
  feature las conecta a controles del panel. Si al conectarlas aparece un hueco
  de comportamiento (por ejemplo, un verbo que hoy pide por diálogo un dato que
  la extensión ya tiene en el modelo), se resuelve reusando el modelo para
  igualar el gesto, no agregando invocaciones a la CLI.
- **El menú Tools → git review no se recorta**: duplicar una acción en menú y
  panel es exactamente lo que ya hace la extensión con la paleta.
- **La CLI mínima sigue siendo la del canónico** y no cambia por esta feature.
- **El escenario de prueba manual es el sandbox del repositorio**, que ya
  produce reviews en los modos y situaciones que la tabla necesita, y permite
  la comparación lado a lado de los dos clientes sobre el mismo repositorio.

## Dependencies

- El plugin de IntelliJ IDEA entregado por la feature `009-plugin-intellij`
  (panel, servicio de estado, las 27 acciones, asistentes de start y compare).
- El canónico multi-cliente `contracts/client-product-surface.yaml` y su
  verificación automática, que esta feature extiende con la dimensión de
  controles del panel y su orden.
- El panel de la extensión de VS Code como referencia de producto observable:
  es la fuente de verdad del invariante rector.
- La CLI de `git-review-workflow` como única fuente de verdad del estado.
