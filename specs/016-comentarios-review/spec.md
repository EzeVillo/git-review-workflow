# Feature Specification: Comentarios portables de una review

**Feature Branch**: `main` — rama actual; esta especificación no crea una rama de implementación.

**Created**: 2026-10-18

**Status**: Draft — aclaraciones cerradas; lista para planificación técnica.

**Input**: User description: "Anotar preguntas, pedidos y observaciones durante una review o comparación; repasarlos y renumerarlos. Un local y un compartido por PR, independientes y accesibles a la vez. Continuar el compartido existente en el mismo PR y empezar de cero en otro. Sin estados ni respuestas obligatorias. Cuadro de entrada en los clientes. save conserva ambos; abortar descarta lo nuevo y respeta lo previo. finish deja el compartido en la rama resultante. Se retira Ctrl+click y se evita guardar instantáneas de código; estudiar calcular el diff con base y head de cada observación. Si el histórico está disponible debe abrirse, incluso tras borrar el archivo actual; si falta, informar no encontrado. Guardar los comentarios de una comparación sólo localmente. Acceso desde panel, sin botón de instrucciones a agentes. CLI y cuatro clientes. Comunicar todas las decisiones pendientes por el chat."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Anotar mientras se entiende el PR (Priority: P1)

Como revisor, quiero registrar una pregunta, observación o pedido cuando aparece,
con una ubicación cuando corresponda, y seguir leyendo. Quiero poder modificar
o borrar después lo que escribí, usando mi editor habitual.

**Why this priority**: Conservar las dudas sin exigir resolverlas en el momento
es el propósito principal de la función.

**Independent Test**: En una review activa, crear un documento local y escribir
tres comentarios, dos sobre el mismo archivo y uno general; editar uno, borrar
otro y comprobar el contenido restante y que el código revisado sigue intacto.

**Acceptance Scenarios**:

1. **Given** una review activa sin comentarios, **When** el revisor crea sus
   comentarios locales, **Then** obtiene un documento editable separado del código.
2. **Given** ese documento, **When** agrega dos preguntas sobre distintas líneas
   de un mismo archivo, **Then** se conservan ambas como entradas independientes.
3. **Given** una duda sobre varios componentes, **When** agrega una entrada
   general, **Then** puede escribirla sin inventar un archivo o una línea.
4. **Given** un comentario que perdió sentido al seguir leyendo, **When** lo
   borra, **Then** desaparece del documento y del recuento después del refresco.
5. **Given** una selección en un IDE, **When** agrega un comentario desde esa
   selección, **Then** elige explícitamente Local o Compartido, escribe en un
   cuadro de entrada y la ubicación se completa sin copiarla a mano.
6. **Given** un documento local, **When** escribe y guarda comentarios,
   **Then** no cambia el estado de archivos, el índice ni el código de la review.
7. **Given** dos documentos con contenido diferente, **When** agrega, abre o
   renumera uno, **Then** el otro permanece disponible y sin modificaciones.
8. **Given** un cuadro de comentario abierto, **When** cancela la entrada,
   **Then** no se agrega una entrada vacía ni se altera ninguno de los documentos.
9. **Given** capturas sucesivas destinadas a Local, Repositorio y Local,
   **When** guarda cada comentario, **Then** el local contiene la primera y
   tercera entradas y el compartido la segunda; no hay destino global de sesión.
10. **Given** uno de los documentos todavía inexistente, **When** agrega otra
    entrada, **Then** puede elegir cualquiera de los dos destinos y se crea
    sólo el elegido al confirmar el comentario; el destino anterior no se
    reutiliza automáticamente ni se deduce de qué archivo ya existe.

---

### User Story 2 - Repasar y renumerar el documento (Priority: P1)

Como revisor, quiero releer mis comentarios en conjunto, eliminar los que ya no
sirven, mover bloques y dejar una numeración consecutiva con una sola acción.

**Why this priority**: El repaso permite devolver una revisión después de
entender el conjunto del PR, en lugar de publicar cada primera impresión.

**Independent Test**: Preparar un documento con entradas numeradas 1, 4 y 9,
dos sobre el mismo archivo, mover físicamente un bloque y renumerar. Comprobar
el orden elegido, la secuencia 1, 2, 3 y la conservación de todos los cuerpos.

**Acceptance Scenarios**:

1. **Given** entradas numeradas 1, 4 y 9 en ese orden físico, **When** renumera,
   **Then** sus números pasan a ser 1, 2 y 3 y los textos se conservan.
2. **Given** números repetidos o desordenados, **When** renumera,
   **Then** prevalece el orden físico de los bloques, no los números anteriores.
3. **Given** un bloque movido manualmente al comienzo, **When** renumera,
   **Then** ese bloque queda primero y recibe el número 1.
4. **Given** un documento ya renumerado, **When** repite la operación,
   **Then** el contenido no vuelve a cambiar.
5. **Given** ejemplos de encabezados dentro de bloques de código,
   **When** renumera, **Then** esos ejemplos se conservan como código.
6. **Given** un documento vacío o una entrada todavía sin cuerpo,
   **When** renumera, **Then** conserva la prosa y no inventa observaciones.
7. **Given** un error que impide interpretar los límites entre entradas,
   **When** solicita renumerar, **Then** recibe un diagnóstico y el original
   queda intacto, sin una reescritura parcial.

---

### User Story 3 - Compartir una revisión como archivo (Priority: P1)

Como revisor, quiero continuar el único documento compartido del PR, conservando
sus entradas anteriores y agregando o editando observaciones. Quiero trabajar en
él durante la review y llevar su resultado al repositorio después del cierre,
mientras mis notas locales permanecen independientes.

**Why this priority**: La portabilidad y la posibilidad de comentar sin hacer
los cambios distinguen este resultado de las correcciones de código actuales.

**Independent Test**: Compartir un documento con comentarios generales y
localizados; abrir la copia en un lector de Markdown sin instalar el producto
y comprobar que contiene todos los comentarios elegidos y sus ubicaciones.

**Acceptance Scenarios**:

1. **Given** un PR que ya contiene el documento compartido, **When** comienza
   a revisarlo, **Then** el documento de trabajo compartido parte de ese contenido,
   disponible para continuar editándolo sin sustituirlo por las notas locales.
2. **Given** ese archivo, **When** otra persona lo abre como Markdown,
   **Then** puede comprender las preguntas sin acceder al borrador privado.
3. **Given** un documento compartido, **When** se edita y renumera,
   **Then** conserva las entradas anteriores que el usuario no borró y aplica
   las mismas reglas de numeración que al documento local.
4. **Given** cambios concurrentes en el documento de destino desde que empezó
   la review, **When** se intenta escribir el resultado compartido, **Then** no
   se sobrescribe esa prosa silenciosamente y se conserva el trabajo preparado.
5. **Given** un resultado compartido preparado, **When** se escribe en el
   repositorio después del cierre, **Then** las notas locales siguen privadas
   y no se realiza commit, push ni envío.
6. **Given** un documento sin comentarios después del repaso, **When** el revisor
   decide terminar sin compartirlo, **Then** puede cerrar normalmente.

El archivo compartido es único por PR. Durante la review su documento de trabajo
permanece junto con las notas locales, separado del código y disponible en
todos los pasos. Tras completar `finish`, el compartido modificado se deja en
la rama resultante, sin commit ni push. El destino se verifica contra el contenido
de partida; cualquier cambio concurrente se conserva y se informa para resolverlo.
Si no se modificó el compartido, no se reescribe por el solo hecho de terminar.
Elegir Repositorio al agregar una entrada significa dirigirla a este documento
compartido; durante la sesión sigue en preparación. La elección se hace por
comentario, no al cerrar la review ni al guardar sus documentos en conjunto.

---

### User Story 4 - Conservar las observaciones durante la review (Priority: P1)

Como revisor, quiero conservar mis comentarios al avanzar, retroceder, pausar,
retomar y terminar una review, aunque no haya hecho correcciones de código.

**Why this priority**: Perder una observación o incorporarla accidentalmente a
una corrección de código invalida el flujo de trabajo.

**Independent Test**: En los modos whole, walk y step, escribir comentarios,
navegar cuando corresponda, pausar, retomar y terminar sin modificar código;
comprobar que el documento sigue accesible y conserva sus entradas.

**Acceptance Scenarios**:

1. **Given** comentarios en step, **When** cambia de commit y vuelve,
   **Then** conserva los comentarios de todos los pasos y sus referencias originales.
2. **Given** comentarios en walk, **When** avanza o retrocede,
   **Then** la navegación no agrega, borra ni filtra entradas.
3. **Given** comentarios locales, **When** pausa y retoma,
   **Then** recupera el documento correcto sin sustituir prosa de otra review.
4. **Given** una review con comentarios y sin ediciones de código, **When**
   termina, **Then** el cierre existente puede completarse y los comentarios
   siguen disponibles sin fabricar cambios de código.
5. **Given** un cierre en conflicto o que se deshace, **When** consulta el
   documento, **Then** las observaciones originales siguen disponibles.
6. **Given** una review terminada, **When** limpia sus ramas auxiliares,
   **Then** conserva el documento local de comentarios.
7. **Given** notas locales y comentarios compartidos en preparación, **When**
   guarda y continúa la review, **Then** recupera ambos documentos y conserva
   sus diferencias sin mezclarlos ni publicar el compartido.
8. **Given** comentarios agregados en una sesión que se aborta o descarta,
   **When** confirma esa operación destructiva existente, **Then** se descarta
   el trabajo de la sesión; nunca se elimina del PR el documento previo por ese motivo.
9. **Given** notas locales de una pasada anterior, **When** aborta la pasada
   nueva sin guardarlas expresamente, **Then** recupera el contenido de partida;
   si el documento se creó en esa sesión, desaparece su trabajo no guardado.
10. **Given** una comparación con comentarios, **When** usa Guardar comments,
    **Then** conserva los documentos como resultado local independiente de
    esa sesión, sin publicar archivos, guardar cambios de código ni cerrar
    implícitamente la comparación.
11. **Given** comentarios guardados expresamente en una comparación, **When**
    aborta después, **Then** se conserva ese resultado local y se descartan
    solamente los cambios posteriores que no volvió a guardar.

Se crean observaciones durante reviews y comparaciones; fuera de ellas se pueden
consultar los resultados conservados. Una nueva pasada del mismo PR continúa
su documento; otro PR comienza de cero, aunque herede un archivo de la base.
Las comparaciones no tienen `finish`: Guardar comments conserva únicamente
los documentos de forma local y permite salir después sin perder ese resultado.
La propuesta de interacción guarda sin cerrar, acorde con el nombre del control.

---

### User Story 5 - Acceder desde la CLI y los cuatro clientes (Priority: P2)

Como usuario de la CLI, VS Code, JetBrains, Visual Studio o la TUI, quiero
acceder al mismo documento y renumeración desde mi entorno habitual. En los IDE
quiero iniciar una entrada desde la selección.

**Why this priority**: El usuario confirmó que la primera entrega incluye las
cinco superficies. La prioridad indica dependencia del documento y sus
operaciones; no difiere ningún cliente a otra entrega.

**Independent Test**: Abrir y renumerar un documento desde cada cliente,
comprobar el mismo resultado y agregar desde una selección en los tres IDE.
En la TUI, abrir el documento en el editor configurado.

**Acceptance Scenarios**:

1. **Given** un documento existente, **When** se abre desde cualquier cliente,
   **Then** se abre el archivo correspondiente a esa review.
2. **Given** el mismo contenido guardado, **When** se renumera desde cada
   superficie, **Then** el documento resultante es el mismo.
3. **Given** cambios sin guardar en un IDE, **When** solicita renumerar o
   compartir, **Then** se guarda únicamente ese documento antes de operar;
   si no puede guardarse, la operación se detiene.
4. **Given** una edición externa guardada, **When** el cliente refresca,
   **Then** refleja la presencia y cantidad actuales de comentarios.
5. **Given** una operación exitosa cuyo resultado ya muestra el panel,
   **When** se actualiza, **Then** muestra el resultado sin notificarlo por duplicado.
6. **Given** la TUI con editor configurado, **When** abre los comentarios,
   **Then** utiliza ese editor y puede volver al panel al terminar.
7. **Given** ambos documentos presentes, **When** consulta el panel,
   **Then** puede acceder a Local y Compartido sin que la presencia de uno oculte al otro.
8. **Given** un cierre completado, **When** vuelve al panel, **Then** los
   documentos disponibles no se abren automáticamente ni se ofrece copiar una
   instrucción para un agente.

---

### User Story 6 - Volver al código que motivó un comentario (Priority: P1)

Como lector, quiero poder consultar desde el cliente el diff de una observación
anterior del mismo PR usando los extremos registrados y la historia que tenga git. El alcance evita
enlaces Ctrl+click, copias de código, fragmentos generados e instantáneas adjuntas.

**Why this priority**: Un documento puede contener observaciones de distintos
heads del mismo PR. Usar siempre el head actual puede cambiar el sentido de una
observación anterior. El usuario aceptó las referencias ligeras por entrada en D17.

**Independent Test**: Con historia disponible, crear una entrada cuando el PR
está en H1 y otra en H2, avanzar a H3 y comprobar desde el cliente los diffs
de ambas sin recuperar archivos adjuntos. Eliminar el archivo actual y repetir
la consulta histórica; probar además una referencia realmente ausente.

**Acceptance Scenarios**:

1. **Given** entradas con las referencias originales B1/H1 y B2/H2, **When**
   consulta su diff desde H3, **Then** cada una usa sus propios extremos, no H3.
2. **Given** un archivo ausente del árbol actual pero presente en una revisión
   histórica disponible, **When** consulta esa entrada, **Then** git permite
   mostrar aquella versión; la ausencia actual no se toma como pérdida de historia.
3. **Given** una revisión o contenido histórico realmente no disponible,
   **When** consulta la entrada, **Then** recibe No encontrado o un diagnóstico
   equivalente, sin sustituir silenciosamente el head actual.
4. **Given** una entrada manual sin referencias, **When** la lee, **Then**
   sigue siendo válida como comentario; el producto no inventa su head original.
5. **Given** una entrada sobre cambios sin commit, **When** se conserva,
   **Then** su ubicación no se presenta como una versión histórica reproducible
   que git no contiene; no se crea una instantánea de código para conseguirlo.

H1, H2 y H3 representan actualizaciones del código del PR, no ediciones ni
renumeraciones del documento de comentarios.

Cada entrada capturada sobre una versión de git conserva las referencias
resueltas de base/head y su ubicación; el diff se calcula cuando se pide.
Se retiran Ctrl+click y el inicio de sesiones históricas completas. El usuario
confirmó en D17 esos identificadores mínimos, sin copia de código ni del diff.
Copiar manualmente un bloque entre Local y Compartido conserva también sus
referencias; no se agrega un control dedicado para esa operación, según D15.

### Edge Cases

- Varios comentarios sobre el mismo archivo, línea o fragmento: conservar todos.
- Comentarios generales, de archivo completo y de una línea o rango.
- Archivo comentado eliminado, renombrado o fuera del rango actual: conservar la observación.
- PR actualizado que ya no contiene el fragmento: conservar el texto y no atribuirlo silenciosamente a otra versión.
- Comentarios de un paso intermedio que no aparece en el tip final.
- Código con ediciones sin commit: permitir el comentario sin prometer reproducción histórica de un contenido que no existe en git; no crear instantáneas de código.
- Documento vacío, con sólo preámbulo o cuerpos incompletos: admitir el trabajo en curso.
- Numeración con saltos, repetida o fuera de orden: renumerar por posición física.
- Encabezados con apariencia de entrada dentro de código cercado: conservar como código.
- Listas, enlaces, encabezados internos, citas y ejemplos de código: conservar su contenido y significado.
- Rutas con espacios, acentos, separadores o caracteres especiales: no confundir ubicación con numeración.
- Rutas escritas como texto: nunca ejecutarlas como comandos ni recorrer directorios al importar o borrar.
- UTF-8 con BOM o finales CRLF: reconocer las mismas entradas; el contrato delimitará la normalización admitida.
- Documentos local y compartido distintos: conservar ambos accesibles, sin prioridad ni fusión implícita.
- Cambio de rama o selección durante una acción: no escribir sobre otra review con información vieja.
- Cambios sin guardar o cambios simultáneos: conservar la versión reciente o rechazar la escritura sin pérdida.
- Worktree enlazado o segunda copia de trabajo: no apropiarse del documento privado de otra sesión.
- Colisión al pausar o retomar: rechazar la sustitución de prosa de otra review.
- Fallo de escritura, permisos insuficientes o estructura ilegible: conservar el original e informar qué no pudo hacerse.
- Documento compartido con cambios existentes: preservar las modificaciones ajenas al pedido.
- CLI insuficiente: los clientes deben informar la actualización requerida antes de intentar una acción incompatible.
- Review abortada o guardada que se descarta: restaurar lo previo o lo guardado expresamente y descartar el trabajo posterior; no borrar el documento versionado del PR.
- Archivo heredado de un PR diferente: iniciar un documento nuevo para este PR y no continuar aquel historial por defecto.
- Force-push, clon superficial o limpieza de objetos: si faltan las versiones, informar No encontrado; no transportar ni retener objetos sólo por escribir un comentario.
- Consultar el diff histórico con otra review activa: no cambiar de rama ni reemplazar trabajo por esa consulta.
- Contenido sin guardar: no guardar otros archivos ni atribuir el buffer a un commit que no lo contiene.
- Comparación sin rama escribible: Guardar comments conserva los documentos sólo en el gitdir y sin guardado de código ni salida implícita.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El producto DEBE conservar comentarios en un documento Markdown editable por personas o agentes.
- **FR-002**: Cada comentario DEBE contener texto libre y admitir una ubicación principal opcional: general, archivo, línea o rango.
- **FR-003**: DEBE permitir varios comentarios sobre la misma ubicación, sin deduplicarlos.
- **FR-004**: El formato NO DEBE exigir estados, clasificación, identificadores permanentes ni secciones de respuesta.
- **FR-005**: El revisor DEBE poder editar, mover y borrar entradas directamente en el documento.
- **FR-006**: La numeración DEBE representar la posición actual; no promete identidad entre versiones renumeradas.
- **FR-007**: Renumerar DEBE producir la secuencia consecutiva 1..N según el orden físico de los bloques.
- **FR-008**: Renumerar DEBE conservar cuerpos, ubicaciones, preámbulo y orden, incluyendo entradas sobre el mismo archivo.
- **FR-009**: Repetir la renumeración sobre un documento normalizado DEBE ser idempotente.
- **FR-010**: Renumerar NO DEBE generar observaciones para archivos sin comentarios, eliminarlas por cambios del PR ni interpretar su significado.
- **FR-011**: El producto DEBE distinguir entradas reales de ejemplos de encabezados dentro de bloques de código.
- **FR-012**: DEBE admitir documentos sin entradas y trabajo en curso; un fallo que impida preservar los bloques DEBE dejar el original intacto.
- **FR-013**: DEBE ofrecer un documento local y uno compartido independientes, con las mismas reglas de edición y numeración y acceso simultáneo.
- **FR-014**: Crear o modificar la versión privada NO DEBE cambiar archivos ni índice, ni aparecer como corrección de código al terminar.
- **FR-015**: Escribir el documento compartido en el repositorio DEBE conservar el documento local separado; la elección explícita de Compartido no permite incluir notas locales por defecto.
- **FR-016**: La copia DEBE ser comprensible como Markdown sin tener instalado el producto.
- **FR-017**: Compartir NO DEBE realizar commit, push, envío a personas ni publicación en un proveedor.
- **FR-018**: Antes de escribir un resultado compartido DEBE comprobarse el destino contra el contenido de partida; cambios concurrentes distintos DEBEN conservarse y requerir resolución, sin sobrescritura silenciosa. Escribir sobre la versión de partida sin cambios ajenos no exige una confirmación adicional.
- **FR-019**: Los comentarios DEBEN funcionar en whole, walk y step y conservarse al navegar.
- **FR-020**: Pausar y retomar DEBE conservar ambos documentos, evitar colisiones y no escribir el compartido en el repositorio por el hecho de guardar la sesión.
- **FR-021**: Terminar, reanudar o deshacer un cierre y limpiar ramas auxiliares DEBE conservar los comentarios locales.
- **FR-022**: Una review con comentarios y sin correcciones DEBE poder terminar con el cierre existente.
- **FR-023**: Un archivo eliminado, renombrado o fuera de rango NO DEBE causar la eliminación del comentario ni impedir terminar.
- **FR-024**: Una referencia al código NO DEBE afirmar que corresponde a una versión distinta de la observada; debe describir el contexto capturado y diagnosticar diferencias o ausencia de datos según FR-046 a FR-049.
- **FR-025**: El usuario DEBE poder abrir ambos documentos durante y después de la review desde el panel, sin apertura automática al terminar.
- **FR-026**: La primera entrega DEBE incluir CLI, VS Code, JetBrains, Visual Studio y TUI.
- **FR-027**: Las cinco superficies DEBEN operar sobre los mismos documentos y producir la misma renumeración.
- **FR-028**: Los tres IDE DEBEN permitir iniciar una entrada desde selección o posición actual, elegir Local o Compartido y escribir texto en un cuadro de entrada que admita varias líneas y cancelación.
- **FR-029**: La CLI DEBE aceptar texto por argumento o entrada estándar y permitir componerlo con el editor configurado cuando no se proporciona; la TUI DEBE ofrecer captura sin depender de un editor gráfico.
- **FR-030**: Los clientes DEBEN obtener del producto la ruta, presencia y recuento; no interpretar su contenido para deducir ese estado.
- **FR-031**: Los clientes DEBEN actualizar la información al guardar o refrescar y tras sus operaciones; la vigilancia seguirá las capacidades vigentes de cada cliente.
- **FR-032**: Antes de reescribir desde un IDE DEBE guardarse únicamente el documento afectado; si falla o se cancela, la operación se detiene.
- **FR-033**: Una acción sobre contexto obsoleto NO DEBE modificar comentarios de otra review o destino.
- **FR-034**: Controles y mensajes DEBEN respetar las reglas del panel: controles de fila en su fila, confirmación de pérdidas irreversibles, resultado visible sin aviso duplicado y detalle técnico accesible.
- **FR-035**: Un fallo DEBE informar qué no pudo hacerse y preservar la prosa; problemas del documento NO DEBEN bloquear verbos existentes que no lo modifican.
- **FR-036**: Las operaciones básicas sobre comentarios locales DEBEN funcionar sin red ni consultas a proveedores de PR.
- **FR-037**: Entregar el archivo a un agente DEBE permitir pedir respuestas o cambios en texto libre; el producto no ejecuta un agente ni interpreta la conversación.
- **FR-038**: Toda definición pendiente DEBE estar identificada en el registro de decisiones y comunicarse en el chat; una recomendación no cuenta como respuesta.
- **FR-039**: La planificación DEBE respetar las aclaraciones cerradas D15 y D17: copia manual entre documentos y referencias mínimas por entrada, sin reincorporar almacenamiento de código ni integración Ctrl+click.
- **FR-040**: La documentación, formato y comportamiento de los clientes DEBEN describir el mismo flujo y sus traducciones requeridas.
- **FR-041**: Durante la review ambos documentos DEBEN permanecer disponibles aunque cambie el commit del modo step; sus cambios no se deben bancar como correcciones de ese commit.
- **FR-042**: El documento compartido DEBE partir del que ya traiga el PR revisado y conservar las entradas previas que el revisor no modifique ni borre; se continúa editando en pasadas posteriores.
- **FR-043**: Cada comentario nuevo DEBE elegir explícitamente Local o Repositorio/Compartido, también desde CLI y aunque uno de los documentos todavía no exista. DEBE poder alternarse el destino en capturas consecutivas, sin preferencia global, deducción por archivos existentes ni reutilización automática de la elección anterior. Confirmar crea únicamente el documento elegido si falta; cancelar no crea documentos.
- **FR-044**: Abortar o descartar DEBE descartar el trabajo de comentarios posterior al contenido previo o guardado expresamente, respetando ese resultado y el documento ya versionado en el PR.
- **FR-045**: Se DEBE poder crear comentarios mediante el producto durante una review normal o una comparación; fuera de esas sesiones DEBE poder leerse, editarse y prepararse el resultado de documentos existentes.
- **FR-046**: Cada entrada capturada sobre una versión de git DEBE conservar base/head resueltos, ruta, lado y línea/rango pertinentes y permitir consultar ese diff desde el cliente calculándolo al pedirlo. No se exige integración de enlaces en Markdown; las entradas manuales sin esos datos siguen siendo válidas sin promesa histórica.
- **FR-047**: El contexto histórico DEBE seguir apuntando al código observado después de renumerar, actualizar el PR o cambiar de rama; no DEBE depender sólo del número de entrada ni del nombre móvil de una rama.
- **FR-048**: Si faltan la revisión o contenido requeridos, DEBE informarse No encontrado o equivalente sin borrar el comentario ni sustituir el head actual. Un archivo borrado actualmente DEBE seguir consultable si existe en una versión histórica disponible.
- **FR-049**: La captura sobre código anterior o eliminado DEBE ofrecerse cuando el host puede suministrar ese contexto; las limitaciones por cliente deben declararse y seguir permitiendo comentarios sobre código actual o generales.
- **FR-050**: La primera entrega NO DEBE agregar un botón específico para copiar instrucciones a un agente.
- **FR-051**: Consultar un diff NO DEBE iniciar otra sesión ni cambiar de rama; Ctrl+click e inicio de reviews históricas completas quedan fuera de esta entrega.
- **FR-052**: La consulta histórica NO DEBE requerir instantáneas, parches guardados, fragmentos generados, bundles, refs de retención nuevas ni transporte de objetos; calcula el diff con referencias y objetos ya disponibles.
- **FR-053**: Guardar comments en una comparación DEBE conservar únicamente sus documentos como resultado local que sobreviva a la salida, respetando su independencia, sin preparar un archivo versionado ni guardar las ediciones de código.
- **FR-054**: Tras guardar comments DEBE poder continuarse la comparación y guardar de nuevo; abortar después descarta sólo lo posterior al resultado guardado. La acción no cierra implícitamente la sesión.
- **FR-055**: Tras un `finish` exitoso, el documento compartido modificado DEBE dejarse en la rama de resultado verificando el destino contra su contenido inicial; Local permanece privado y no se hacen commit ni push.
- **FR-056**: Una review de otro PR DEBE empezar su documento de comentarios desde cero; una nueva pasada del mismo PR DEBE continuar el suyo, sin confundir un archivo heredado de la base con comentarios actuales.

### Key Entities *(include if feature involves data)*

- **Documento local**: Observaciones privadas editables asociadas al trabajo de revisión; puede tener dudas para una IA u otro texto libre. Su contenido es independiente del documento compartido.
- **Documento compartido del PR**: Un único documento versionable que continúa el contenido que ya traiga el PR. Durante la sesión se trabaja sobre su preparación sin publicarlo ni mezclarlo con el local.
- **Comentario**: Texto libre con posición visible y ubicación opcional. Dos comentarios pueden compartir ubicación. Su existencia expresa que se quiere conservar; no tiene un estado de resolución.
- **Ubicación**: Referencia general, de archivo o línea/rango. Para código anterior o eliminado se usan las capacidades declaradas del host según D11.
- **Referencia de versión**: Identificadores ligeros de base/head resueltos, lado y ubicación. Permite calcular diferencias al consultar, sin contener código ni garantizar disponibilidad de objetos inexistentes.
- **Contexto de review**: Trabajo al que pertenece el documento local, necesario para recuperarlo tras navegación, pausa o cierre sin apropiarse de otro documento.
- **Resultado compartido**: Documento preparado para escribir después del cierre en el repositorio o como archivo; no es una copia automática de las notas locales.
- **Resultado local guardado**: Documentos de una comparación conservados expresamente fuera de su sesión; sobreviven al descarte posterior sin guardar código ni mezclar sus contenidos.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: El usuario puede registrar, reformular y borrar una observación sin modificar una línea del código revisado.
- **SC-002**: Un documento de 100 entradas con eliminaciones y bloques movidos queda numerado consecutivamente en una acción, conservando el 100% de los cuerpos restantes en el orden elegido.
- **SC-003**: Repetir la renumeración sin editar produce exactamente el mismo documento.
- **SC-004**: Crear → navegar → pausar → retomar → terminar → limpiar conserva el 100% de las observaciones no borradas, en los tres modos de review.
- **SC-005**: Un destinatario sin el producto puede leer todas las observaciones y ubicaciones en un único archivo compartido.
- **SC-006**: Las cinco superficies permiten abrir y renumerar el documento y producen el mismo resultado para el mismo contenido guardado.
- **SC-007**: En los tres IDE, iniciar desde una selección conserva archivo y rango sin copiarlos a mano.
- **SC-008**: Ninguna operación sustituye silenciosamente prosa concurrente ni deja un documento parcialmente escrito en los casos de fallo definidos.
- **SC-009**: Una review sólo con comentarios puede cerrarse y entregar el documento sin correcciones de código ficticias.
- **SC-010**: Crear, abrir y renumerar comentarios locales completa sus recorridos de aceptación sin acceso a red.
- **SC-011**: En los tres modos, una secuencia de capturas Local → Repositorio → Local deja cada entrada únicamente en su destino elegido; abrir y renumerar conserva el 100% del contenido del otro documento, aunque inicialmente sólo existiera uno.
- **SC-012**: Con referencias y objetos disponibles, consultar desde el cliente entradas escritas contra H1 y H2 después de avanzar a H3 muestra los diffs originales sin código adjunto; un archivo ausente en H3 sigue consultable si existía en la revisión guardada.
- **SC-013**: Guardar y retomar recupera los dos documentos completos; abortar o descartar elimina el trabajo de esa sesión conforme a la política acordada, sin borrar el documento versionado previo del PR.
- **SC-014**: Guardar comments en una comparación conserva el 100% de las entradas guardadas tras abortarla, sin crear cambios en el working tree ni guardar ediciones de código.

## Assumptions

### Acuerdos confirmados en la conversación

1. Los comentarios viajan en un archivo y son independientes del proveedor del PR.
2. Hay documento local y documento compartido independientes, accesibles a la vez y sin precedencia entre ellos.
3. Preguntas, pedidos y observaciones usan texto libre; se editan o borran al repasar.
4. No se incorporan estados de comentarios ni sección obligatoria de respuesta.
5. La numeración se recompone después de borrar o mover y representa el orden actual.
6. El documento se abre durante y después de la review desde el panel; una lista permanente no está exigida. Se retira Ctrl+click y se ofrece consulta de diff desde el cliente con referencias ligeras.
7. Ambos documentos acompañan `save`/`continue`. Terminar y limpiar conserva el resultado; abortar descarta lo nuevo respetando el contenido previo o guardado expresamente.
8. El documento compartido se prepara durante la review y se escribe después del cierre. Las notas locales no se incorporan por ese motivo.
9. La ubicación puede ser general o localizar código; los IDE inician entradas desde una selección.
10. La primera entrega incluye **CLI y los cuatro clientes**, confirmado el 2026-10-18 en D01.
11. Se usa `comments` como familia pública, dentro de las dos opciones admitidas por el usuario; Local y Compartido distinguen los documentos sin imponerles una finalidad.
12. Hay un único documento compartido por PR, que puede existir antes de empezar y se continúa editando.
13. Los IDE usan un cuadro de entrada para capturar texto; en CLI se admiten texto explícito, stdin y editor configurado.
14. La consulta histórica usa git y las versiones disponibles, guardando sólo referencias de base/head por entrada. Se aceptan versiones No encontradas y se mantiene la consulta de antepasados existentes. Se retiran Ctrl+click y las reviews históricas completas de esta entrega.
15. No se agrega botón para copiar instrucciones a un agente; se interpreta la respuesta «n» como «no».
16. D16 confirmada: el compartido se prepara en la rama al completar `finish`, con protección ante cambios concurrentes.
17. D19 y D20 confirmadas: otro PR comienza desde cero; abortar una nueva pasada respeta el contenido local previo.
18. D21: Guardar comments conserva localmente los documentos de una comparación. Se elige guardar sin cerrar como interacción inicial por el significado del control; no se guarda código.
19. D15 confirmada: para llevar una entrada entre Local y Compartido alcanza copiar y pegar el bloque; no se agrega botón.
20. El destino se elige al guardar cada comentario nuevo y puede intercalarse libremente; Repositorio y Compartido designan el mismo documento. Guardar la sesión o conservar documentos no reclasifica las entradas.

### Límites de esta especificación

- Describe comportamiento y aceptación; la evidencia técnica está en [research.md](research.md).
- El [registro de decisiones](decisiones-pendientes.md) conserva las preguntas y respuestas. Las recomendaciones históricas no sustituyen las respuestas posteriores; no quedan preguntas abiertas en esta revisión.
- Se excluyen sincronización automática, hilos, publicación en proveedores y ejecución de agentes.
- Se excluyen enlaces Ctrl+click, instantáneas de código, transporte de objetos, apertura de sesiones históricas completas, lista permanente y decoraciones. Se permite elegir/consultar el diff desde el cliente, calculándolo con git.
- Se mantienen extracción de correcciones y marcadores delta. El ciclo agrega custodia y descarte de comentarios, guardado local de comparación y preparación del compartido tras el cierre.
- Markdown es el intercambio acordado. La gramática y los registros para clientes se definirán en contratos durante la planificación, después de resolver las decisiones que los afectan.
- Advertir sobre ubicación o versión describe el código, sin introducir un estado del comentario.
- No se fija como mínimo de un cliente una versión de CLI todavía no publicada; rige la secuencia de release del monorepo.
- La constitución de Spec Kit sigue siendo una plantilla sin completar. Rigen las instrucciones de `AGENTS.md`; los ejemplos de esa plantilla no se convierten en reglas.

### Clarifications

#### Session 2026-10-18

- Q: ¿La primera entrega incluye sólo la CLI o también los clientes? → A: **CLI y los cuatro clientes**. D01 resuelta; incorporada en US5 y FR-026.
- Respuestas del segundo intercambio: creación durante review/compare; `comments` o `notes`; un compartido por PR que se continúa; escritura posterior al cierre; Local y Compartido independientes; sin preferencia entre ellos; `save` conserva ambos y el descarte los elimina; cuadro de entrada; lado anterior cuando sea posible; enlaces al diff original, advertencias y posible review histórica; acceso desde panel; sin botón de copia para agentes.
- D07 se reformuló: ya no se presupone copiar documentos completos entre versiones equivalentes. D15 aclaró el traslado de entradas individuales y quedó respondida con copia/pegado habitual.
- Última simplificación: retirar Ctrl+click y guardado de código; calcular diferencias con git. D16, D19 y D20 aceptadas; D18 acepta faltantes y exige antepasados disponibles; D21 incorpora Guardar comments sólo local.
- Q: ¿Se aceptan identificadores originales de base/head por comentario, sin guardar código ni diffs? → A: **Sí, guardar esas referencias mínimas**. D17 cerrada.
- Q: ¿Copiar y pegar una entrada entre Local y Compartido o agregar un botón? → A: **Copiar y pegar el bloque**. D15 cerrada.
- Aclaración posterior: H1/H2 representan versiones del código. Cada comentario elige Local o Repositorio al crearse, incluso si el documento elegido aún no existe; se puede alternar sin un destino global de review.
- No quedan decisiones de producto abiertas en el registro actual. Formato, argv, registros de clientes y descomposición de implementación corresponden al plan técnico.
