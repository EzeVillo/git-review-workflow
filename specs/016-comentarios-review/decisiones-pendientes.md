# Definiciones de producto: comentarios de review

Actualizado: 2026-10-18. Referencia: [spec.md](spec.md).

Las respuestas numeradas 1..13 del usuario corresponden a D02..D14 del primer
cuestionario. D01 se respondió antes. Una recomendación sigue siendo una
propuesta; no se registra como respuesta. El último intercambio y las dos
respuestas asíncronas cerraron las aclaraciones D15..D21. Durante la implementación
se confirmó además D22, sobre la revisión `unreadable`. No quedan preguntas de
producto abiertas en este registro. Los detalles mecánicos quedan para el plan.

## Decisiones iniciales y respuestas

### D01 — Superficies de la primera entrega

- **Estado**: Resuelta.
- **Respuesta**: «CLI y los cuatro clientes».
- **Consecuencia**: CLI, VS Code, JetBrains, Visual Studio y TUI entran juntos.

### D02 — Contextos donde se crean observaciones

- **Estado**: Resuelta en el alcance principal.
- **Respuesta**: La utilidad es durante una review o, como mucho, una comparación.
- **Consecuencia**: Captura mediante el producto en reviews y comparaciones;
  fuera de ellas se pueden consultar y editar documentos existentes y preparar
  el resultado. No se agrega un gestor genérico de notas para cualquier rama.
  Compare incorpora Guardar comments sólo local en D21, sin habilitar `finish`.

### D03 — Nombre público

- **Estado**: Resuelta por elección de diseño dentro de las opciones admitidas.
- **Respuesta**: «comments o notes».
- **Elección**: `comments` / `Comments` para la familia pública. Local y
  Compartido distinguen los destinos. No se interpreta el texto para decidir
  si una observación es para una IA o para el autor.

### D04 — Organización del documento compartido

- **Estado**: Resuelta: un documento compartido por PR.
- **Respuesta**: El archivo puede existir antes de comenzar y se le sigue sumando.
- **Consecuencia**: La preparación compartida parte del documento de la versión
  revisada y conserva lo que no se edita o borra deliberadamente. No empieza
  vacía ni se sustituye por el documento local. El producto sigue siendo
  universal y no consulta una API para averiguar un número de PR.
- **Derivada resuelta**: D19 empieza de cero cuando se trata de otro PR.

### D05 — Momento de incorporación al repositorio

- **Estado**: Resuelta; D16 confirma la escritura al completar el cierre.
- **Respuesta**: Preferencia por después del cierre, pero debe poder verse
  durante toda la review; se delega la elección de la solución más simple.
- **Diseño propuesto**: Mantener los dos documentos de trabajo en el gitdir
  durante la sesión y escribir el compartido después de completar el cierre.
  Se presenta como diseño, sin confundirlo con una implementación existente.
- **Motivo**: En step, los cambios del working tree se bancan por commit y se
  materializa otro árbol al navegar. Un documento general no debe desaparecer
  ni convertirse en una edición de un paso. Local y Compartido siguen siendo
  las únicas dos superficies; la preparación compartida es detalle de custodia.

### D06 — Relación entre Local y Compartido

- **Estado**: Resuelta; sustituye la propuesta de precedencia.
- **Respuesta**: Pueden ser diferentes; uno podría contener dudas para una IA
  y el otro comentarios. Ambos disponibles todo el tiempo, sin predominio.
- **Consecuencia**: Son documentos independientes. Toda captura elige destino;
  abrir, editar o renumerar uno no afecta ni oculta el otro. No hay fallback ni
  sincronización. Se conserva la independencia también en `save`/`continue`.
- **Aclaración posterior**: Se elige Local o Repositorio al guardar cada entrada,
  no una sola vez para la review. Se puede intercalar L → R → L y elegir un
  documento que aún no existe, sin reutilizar automáticamente el último destino.
  Repositorio es el compartido; durante la review sigue en preparación.

### D07 — Importar el compartido al local

- **Estado**: Reformulada, no respondida con un sí implícito.
- **Respuesta**: El usuario no entendió la pregunta.
- **Explicación**: La pregunta original proponía copiar el archivo compartido
  completo al privado. Presuponía dos versiones del mismo documento, modelo
  que D06 reemplazó. Ya no se propone esa copia como recorrido por defecto.
- **Derivada resuelta**: D15 acepta copiar y pegar entradas individuales sin botón.

### D08 — Volver a revisar la misma rama

- **Estado**: Resuelta la continuidad; D19 distingue otro PR y empieza de cero.
- **Respuesta**: Parece conveniente ir editando el documento, como en D04.
- **Consecuencia**: Una nueva pasada continúa el trabajo existente; no crea
  automáticamente otra colección ni borra entradas anteriores. Sus referencias
  originales no se reasignan al nuevo tip por iniciar otra pasada.

### D09 — Guardar, abortar y descartar

- **Estado**: Resuelta; D20 confirma respetar notas previas.
- **Respuesta**: Borrar al abortar o descartar, pero guardar los comentarios
  cuando se guarda una review y recuperarlos al continuar.
- **Consecuencia**: `save` guarda ambos documentos y `continue` restaura ambos.
  Abortar o descartar elimina el trabajo de esa sesión, sin eliminar por ese
  motivo el documento previo versionado en el PR.
- **Derivada resuelta**: D20 restaura las notas anteriores al abortar una nueva
  pasada. D21 permite conservar expresamente comentarios de compare antes de
  salir, sin guardar su código. Guardar una sesión no equivale a compartirla.

### D10 — Captura del texto

- **Estado**: Resuelta; CLI delegada al criterio de diseño.
- **Respuesta**: Cuadro de entrada en clientes; se pide una recomendación para CLI.
- **Elección propuesta para CLI**: Texto explícito por argumento o entrada
  estándar, y editor configurado cuando no se proporciona texto. La TUI ofrece
  captura adecuada a terminal. El plan definirá argv y la interacción concreta.
- **Consecuencia**: En IDE, cuadro que admite varias líneas y cancelación, con
  destino y ubicación visibles. Cancelar no agrega una entrada vacía.

### D11 — Código anterior o eliminado

- **Estado**: Resuelta con la condición expresada por el usuario.
- **Respuesta**: Incluirlo si los clientes lo permiten; si no, se puede formular
  una pregunta desde código actual o como comentario general.
- **Consecuencia**: Capturar lado anterior cuando el host suministre el contexto.
  Declarar limitaciones por cliente, sin fingir equivalencia entre ambos lados.
  Siempre se mantiene la captura actual y general.

### D12 — Consulta de diferencias y alcance simplificado

- **Estado**: Modificada por el usuario para reducir complejidad.
- **Respuesta anterior**: Ctrl+click y posible inicio de una review histórica.
- **Respuesta vigente**: Retirar Ctrl+click si supone guardar contexto/cambios;
  se considera excesivo. Sigue interesando el diff original cuando un documento
  contiene comentarios de varios heads; se pregunta cómo calcularlo con git.
- **Consecuencia**: Quitar integración de enlaces y almacenamiento de código.
  D17 confirma referencias mínimas por entrada y cálculo al consultar.
  El diseño reducido no incluye iniciar sesiones históricas completas.

### D13 — Presentación después del cierre

- **Estado**: Resuelta.
- **Respuesta**: «desde el panel».
- **Consecuencia**: Acceso manual desde el panel; no se abre el documento
  automáticamente después de `finish`.

### D14 — Botón para copiar una instrucción a un agente

- **Estado**: Resuelta interpretando «n» como «no».
- **Consecuencia**: No agregar ese botón en esta entrega. El archivo se puede
  entregar a un agente por los medios habituales.

## Decisiones derivadas y respuestas posteriores

### D15 — Pasar una entrada de Local a Compartido

- **Estado**: Resuelta después de explicar el caso con un ejemplo.
- **Explicación con ejemplo**: Escribís una duda en Local para consultarla con
  una IA. Después decidís que el autor del PR debería verla en Compartido.
  ¿Alcanza copiar y pegar ese bloque o hace falta un botón que lo haga?
- **Respuesta**: «Copiar y pegar el bloque».
- **Consecuencia**: Se usa la edición habitual, conservando texto y referencias.
  No se agrega un control específico de copiar/mover ni importación de archivos
  completos entre Local y Compartido.

### D16 — Escritura del compartido al terminar

- **Estado**: Resuelta tras la explicación de casos de uso.
- **Respuesta**: «2 ok», aceptando la recomendación de integrar el resultado
  compartido al completar `finish`.
- **Consecuencia**: Si se modificó Compartido, dejar ese resultado en la rama
  de salida; si sólo se escribió Local, no reescribir el compartido. Sin commit
  ni push, sin copiar las notas locales y sin confirmación adicional rutinaria.
- **Protección obligatoria**: Partir del documento del PR al
  comienzo, conservarlo como referencia y comparar el destino antes de escribir.
  Si cambió entretanto, preservar ambas versiones y mostrar la diferencia para
  resolverla; no sustituirlo ni asumir que sólo se añadieron entradas. Preparar
  el archivo no realiza un commit ni un push.
- **Impacto**: Resultado de `finish`, reintentos y conflictos de documento. Si el
  código ya se extrajo pero el documento no se pudo escribir, hay que decir qué
  parte quedó hecha y conservar el documento preparado.

### D17 — Referencias mínimas para varias versiones de un PR

- **Estado**: Resuelta mediante la consulta asíncrona sobre referencias mínimas.
- **Respuesta del usuario**: Un mismo PR acumula comentarios de diferentes
  heads; sería ideal ver cómo estaba entonces sin guardar el código. Pregunta
  si se puede calcular en tiempo real con head y base.
- **Respuesta final**: «Sí, guardar esas referencias mínimas».
- **Aclaración posterior**: Los heads distintos de la tabla son actualizaciones
  del código del PR, no modificaciones del Markdown ni su numeración.
- **Decisión**: Anotar en cada entrada los identificadores resueltos de los
  extremos del diff y su ubicación. Al consultar, calcular el diff con git.
  No guardar código, parches ni fragmentos. La referencia no se cambia al
  renumerar ni cuando avanza el PR.
- **Motivo**: Con sólo la base y el head actuales
  no se puede deducir qué pareja estaba mirando quien escribió una entrada.
- **Límite**: Código sin commit no queda reproducido por dos SHAs; se permite
  comentar su ubicación sin promesa histórica. Los límites calculados por la
  CLI y la captura desde step deben resolverse con sus referencias reales.
  Si los objetos necesarios ya no están, rige D18.
- **Alcance cerrado**: Se consulta el diff desde el cliente; Ctrl+click y
  sesiones históricas completas no forman parte de esta entrega simplificada.

### D18 — Código histórico ausente o sin commit

- **Estado**: Resuelta con tolerancia a faltantes, sin transporte de código.
- **Respuesta**: Aceptar borrado/no encontrado si el contenido no está, pero
  debe funcionar si se trata de una versión antepasada disponible.
- **Consecuencia**: Consultar la historia con git. Que un archivo no exista en
  el árbol actual no significa que su versión antigua falte. Si existe en los
  extremos registrados, se muestra; si la revisión/contenido realmente falta,
  se diagnostica sin sustituir el head actual.
- **Alcance retirado**: Instantáneas de código, fragmentos generados, bundles,
  transporte de objetos y refs adicionales para retener versiones. El cuerpo
  libre puede contener ejemplos escritos deliberadamente por el usuario.
- **Límite**: Un archivo no versionado o un buffer modificado no aparece en una
  versión antigua por registrar un SHA. No se promete reconstruir ese contenido.

### D19 — Documento heredado de otro PR

- **Estado**: Resuelta la política.
- **Respuesta**: Como walk, crear desde cero en otro PR.
- **Consecuencia**: Una pasada nueva del mismo PR continúa el documento. Otro
  PR empieza el suyo; el archivo heredado de la base no se toma automáticamente
  como observaciones propias. No se acumula un historial global entre PR.
- **Impacto**: Un archivo fijo versionado también viaja al hacer merge y a las
  ramas siguientes. No se puede identificar universalmente un PR sólo por su
  número de proveedor ni asumir que un nombre de rama nunca se reutiliza.

### D20 — Abortar cuando ya había notas locales

- **Estado**: Resuelta.
- **Respuesta**: «6 ok», aceptando descartar sólo lo nuevo.
- **Consecuencia**: Restaurar el contenido local de partida; si el documento
  nació en esa sesión, eliminar su trabajo no conservado. El compartido previo
  versionado sigue en el PR. D21 añade la conservación expresamente solicitada
  de comentarios de una comparación: ese resultado local sobrevive al aborto.

### D21 — Conservar resultados de una comparación

- **Estado**: Necesidad concretada; interacción elegida en el diseño.
- **Respuesta**: Un botón Guardar comments que sólo guarde localmente.
- **Diseño**: Conservar los documentos de la comparación como
  resultado local independiente de la sesión, sin escribir archivos versionados,
  guardar código, copiar Compartido sobre Local ni cerrar la comparación.
  La CLI tendrá la misma capacidad; su argv se define en el plan.
- **Continuación**: Se puede seguir comentando y guardar de nuevo. Al abortar
  después se conserva el último resultado guardado expresamente y se descarta
  sólo lo posterior. Se diferencia `save` de review, que conserva la sesión
  completa y su código, de Guardar comments, que conserva únicamente documentos.
- **Interacción elegida**: Guardar sin cerrar por el
  significado del botón. No se introduce una salida implícita de compare.

### D22 — Revisión de un documento ilegible

- **Estado**: Resuelta explícitamente en el chat durante implementación,
  el 2026-10-18.
- **Pregunta**: El contrato exige ambas filas de documento y una revisión de
  bytes; ¿cómo representar un archivo que existe pero no puede leerse?
- **Respuesta**: Usar el valor explícito `unreadable`.
- **Consecuencia**: Informar `present`, revisión `unreadable` y diagnóstico
  `read`, sin inventar count cero ni ocultar la otra fila. Bloquear escritura
  hasta obtener una revisión de bytes válida tras resolver el fallo.
- **Alternativa descartada**: Omitir el campo de revisión en esa fila.

## Reglas que se mantienen

- Sin estados de comentarios, respuesta obligatoria, clasificación ni ids permanentes.
- Orden físico y renumeración; varias entradas válidas por ubicación.
- Dos documentos visibles y editables, sin precedencia, fusión ni sincronización.
- Guardar ambos al pausar; descartar trabajo de sesión al abortar o borrar la guardada.
- Archivo compartido único por PR que continúa el existente; jamás copia implícita de Local.
- No hacer commits, push, envíos ni ejecutar agentes.
- Guardar únicamente el documento afectado antes de reescribirlo desde un IDE.
- CLI como autoridad de rutas, recuentos, referencias y diagnóstico; clientes presentan esa información.
- Markdown legible sin el producto; sin integración Ctrl+click ni código adjunto.
- Diff calculado con git a partir de referencias disponibles; faltantes explícitos, sin sustituir código nuevo.
- `finish` incorpora el compartido modificado; Guardar comments de compare conserva sólo resultados locales.
- Los problemas del documento no bloquean verbos existentes que no lo modifican.

## Estado para continuar

Se incorporaron las respuestas y la simplificación más reciente, incluida la
aceptación explícita de copiar/pegar y de las referencias mínimas. No quedan
preguntas de producto abiertas. La planificación técnica está en [plan.md](plan.md),
con decisiones T01..T12 en [research.md](research.md), modelo y cuatro contratos.
Se definieron formato, argv, porcelain, custodia, comparación de prosa concurrente
y entrega idempotente. La implementación se sigue en [tasks.md](tasks.md) y su
evidencia en [quickstart.md](quickstart.md), sin reabrir D01..D22 ni confundir
los contratos planificados con aceptaciones todavía pendientes.
