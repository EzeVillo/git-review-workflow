# Validación del contexto de una review

## Continuación desde el inventario

Con reviews guardadas, `list --porcelain` agrega un par de registros:

```text
capability<TAB>continue-state
continue-guard<TAB><token>
```

El testigo opaco, hexadecimal de 40 o 64 caracteres, pertenece al inventario:
gitdir absoluto, rama y HEAD actuales, refs guardados con sus OID y snapshot
de metadata review. Es un dominio distinto del guard de una review activa.
Puede invalidarse por otra modificación de esa metadata; no cambia la regla
de independencia de los guards activos. No incluye buffers, texto de comentarios,
índice ni working tree. Status fuera de una review conserva stdout vacío y exit 2.

El cliente captura ese token al abrir la confirmación de Continue. Sólo con
ambos registros únicos y válidos envía
`git review --expect-state <token> continue --porcelain <source>` y omite la
prelectura principal. Otros verbos conservan sus reglas actuales. Continue
comprueba el inventario dentro del verbo, antes de los efectos: una diferencia
sale con 4, stdout vacío y el stderr habitual `error: review state changed`.
Las guardas de limpieza, destinos y custodia continúan vigentes y frescas en
cada frontera. Sin capacidad/token, los clientes mantienen el camino anterior.

`continue --porcelain [source]`, con o sin guard, devuelve:

```text
continue-state<TAB>1
<status completo de la review resultante, incluido su nuevo guard>
continue-state<TAB>complete
```

La respuesta usa el mismo emisor de status y metadata fresca después de la
mutación, una vez liberada la custodia. No ejecuta otro verbo. Sin la opción,
se conserva la salida humana y no se calcula ese informe. Si el informe final
falla, la mutación exitosa sigue devolviendo 0 y no emite el marcador completo:
el cliente refresca sin repetir Continue. Un sobre ausente, duplicado,
incompleto o sin un único estado de review/guard válido usa el mismo fallback.
La publicación principal y los detalles secundarios conservan sus generaciones.

## Review activa

`status --porcelain` agrega, durante una review activa, un registro:

```text
guard<TAB><token>
```

El token es opaco, hexadecimal minúsculo de 40 o 64 caracteres. No es una
credencial ni se calcula en los clientes. Está ligado al gitdir, rama, HEAD y
metadata de la review activa, incluidos cursor y estado de cierre. No incluye
el índice, working tree, texto de comentarios ni buffers del editor. Los cambios
de una review diferente no lo invalidan. No se persiste como autorización de
una sesión posterior.

El resto del reporte y sus códigos de salida permanecen iguales. El registro
es aditivo, no ensancha `state`, y no aparece en salida humana ni en `--why`.
Fuera de una review el reporte mantiene su comportamiento anterior, incluido el
código 2 y stdout vacío: allí los clientes siguen consultando inventario y config.

Una acción que se refiere a ese contexto se invoca así:

```sh
guard=$(git review status --porcelain | awk -F '\t' '$1 == "guard" {print $2}')
git review --expect-state "$guard" next
```

El prefijo funciona tanto a través de `git review` como invocando el dispatcher
directamente. Se envía como argumentos separados; no es una cadena de shell.
La CLI comprueba el contexto dentro de la invocación, antes de iniciar efectos:

- Coincidencia: se ejecuta normalmente y conserva stdout, stderr, stdin y código
  de salida de la operación. Su timeout y política de red dependen del verbo real.
- Diferencia: código 4, stdout vacío y `error: review state changed` en stderr.
  El verbo no se ejecuta. El cliente refresca el estado completo, muestra su
  mensaje `STALE` habitual y no reintenta la acción.
- Token inválido o argumentos incompletos: código 1, sin ejecutar el verbo.
- Error de lectura del contexto: error de la CLI, sin ejecutar el verbo.

El cliente conserva el token del modelo que originó el gesto, incluso mientras
espera una confirmación. No sustituye ese valor por el de otro modelo posterior.
Un registro ausente, inválido o duplicado no habilita la ruta rápida: se conserva
la validación anterior, incluida la prelectura donde ya existía. La presencia de
un `guard` válido permite utilizar el prefijo sin exigirlo a las CLI anteriores.

El control se usa para mutaciones de la review, no para `status`, `list`, config
de lectura, `--why`, Preview o validaciones `--check`. Comments conserva sus
guards específicos de contexto y revisión del documento; el guard general no
los sustituye ni agrega una comprobación redundante a esos comandos.

Esta comprobación es una precondición optimista en la invocación. No es un lock
global ni una transacción frente a un checkout externo concurrente. Los locks,
guards del índice, metadata, documentos y recuperación propios de cada verbo
siguen siendo obligatorios. No se elimina una guarda del verbo por haber enviado
un token coincidente.

## Respuesta de navegación

En modo walk o step, status anuncia `capability<TAB>navigation-state`. La
presencia de `guard` por sí sola **no** anuncia esa capacidad. Un cliente anterior
ignora el registro, y un cliente nuevo conserva la ruta previa si no está.

Con esa capacidad, Next/Prev aceptan `--porcelain`. Validan el contexto esperado
usando su snapshot inicial de config, rama y HEAD, antes de cargar o recuperar
el recorrido. El dispatcher entrega el token al verbo; no carga otro snapshot.
Save y Cancel sin argumentos también validan su lectura dentro del verbo.
Sus lecturas estables de metadata se agrupan por fase; la custodia vuelve a
consultar config y gitdir antes/después del lock y antes de transferir o borrar.
Los demás verbos conservan la validación genérica del dispatcher.

En éxito, la respuesta comienza por `state` y contiene el mismo reporte completo
que status, incluido el guard actualizado, más:

```text
navigation<TAB>moved|unchanged
notice<TAB><texto operativo, sólo cuando el cursor no se movió>
```

El emisor de status y el de navegación son una misma función. La navegación
reutiliza la secuencia ya cargada y refleja la escritura exitosa del cursor en
el snapshot de metadata; en step incorpora además el nuevo HEAD y los bancos.
No ejecuta otro status ni vuelve a analizar el walkthrough. El índice, los
edits y los cierres conservan sus guardas anteriores.

El cliente sólo consume como respuesta una salida exitosa con un único `state`,
un único `navigation` reconocido, capacidad y guard válidos, modo walk/step y
sin cierre en conflicto. Si falta algo, consulta el estado completo. Un error
o un código 4 nunca se presentan como navegación exitosa ni se reintentan.

La respuesta reemplaza la lectura principal posterior; no es un parche local
del cursor. El cliente publica ese reporte, libera la mutación y completa
Comments y explicación por separado. Toda respuesta secundaria lleva la
generación de su estado principal: una lectura o acción posterior la invalida.
Mientras se consulta Comments, su estado es pendiente y conserva la vigilancia
de documentos anterior; un error no se convierte en ausencia.

### Porqué incluido en la navegación walk

La respuesta puede agregar el porqué de la entrada actual, obtenido del mismo
documento y pasada de AWK que emite el inventario. No se agrega otra lectura de
Git ni otro proceso de parsing al camino principal. Step y status ordinario
conservan su superficie anterior.

```text
why<TAB>present<TAB><cantidad de líneas>
why-line<TAB>1<TAB><texto escapado>
why-line<TAB>2<TAB><texto escapado>
```

La ausencia comprobada se expresa como `why<TAB>absent<TAB>0`, sin `why-line`.
La cantidad es decimal canónica, sin ceros iniciales; `present` exige al menos
una línea. El ordinal físico es consecutivo desde 1 y cada registro tiene tres
campos. El texto escapa `\` como `\\`, tab como `\t` y CR como `\r`; otros
bytes se conservan. Decodificar cada línea y agregar LF reproduce exactamente
la salida de `status --why` para esa entrada. La eliminación de marcadores y
líneas vacías iniciales/finales usa el mismo scanner en ambos caminos.

Un cliente antiguo ignora estos registros nuevos. Un cliente nuevo los usa sólo
en una respuesta de navegación válida y conserva su interpretación habitual
del texto. Si el bloque falta, está duplicado, tiene escapes desconocidos o
truncados, ordinales incorrectos o un conteo incoherente, consulta `status --why`
por separado. Esto no invalida un estado principal válido ni repite la acción.
Una lectura fallida del documento omite el bloque; nunca se presenta como
ausencia de prosa. Comments sigue siendo una consulta independiente.

### Buffers antes de cerrar o guardar

En los tres IDE, sólo una confirmación positiva del host de que **todos** los
documentos están guardados permite omitir el inventario previo de Comments.
Si hay cualquier documento modificado, la respuesta es desconocida o el host
falla, se conserva `comments status --porcelain --all` y el guardado selectivo
de los documentos de la sesión afectada. Un fallo de consulta o guardado impide
continuar. No se guardan archivos de código ni documentos de otra sesión por
este atajo, y las guardas de custodia y cierre de la CLI siguen vigentes.
La TUI no tiene buffers de un editor que deba guardar.

### Transferencia de custodia

Save y Continue publican el manifest de custodia desde un único candidato
hermano. La sesión, contexto, propietario, gitdir y ruta se fijan al prepararlo.
Inmediatamente antes de publicar se releen origen y destino y se contrasta
la revisión de bytes del manifest. Una sesión distinta no se adopta aunque
sea válida; un conflicto o fallo de rename conserva original y candidato.
Esta escritura interna de metadata no reconstruye el estado de lectura de
Comments. Los documentos Local/Shared mantienen sus guardas propias.

### Refrescos observados durante una operación

En los tres IDE, los watchers conservan las señales mientras el lock de
mutación está ocupado. La lectura principal de la operación cubre las señales
recibidas antes de su inicio. Las posteriores quedan pendientes para un
refresco al liberar el lock; si no hubo lectura principal, tampoco se pierden.
Los refrescos observados no corren en paralelo entre sí. Comments sigue siendo
asíncrono y no alarga el lock. Una lectura que ya había comenzado conserva las
guardas de generación para no publicar resultados obsoletos.

La TUI conserva su política de señales diferidas y su ventana posterior al
lock. Estas políticas coordinan invocaciones; no derivan ni almacenan estado
de producto fuera de la CLI.

## Respuesta opcional de Save

`status --porcelain` anuncia `capability<TAB>save-state` durante una review.
Los clientes que reciben esa capacidad y un guard válido pueden invocar
`git review --expect-state <guard> save --porcelain`. Sin la opción, Save
conserva su salida humana y no calcula el informe final. La capacidad es
independiente de navigation-state y no se infiere de una versión o del guard.

La salida exitosa tiene este sobre, con tabs literales:

```text
save-state<TAB>1
status<TAB>2
list<TAB><registro de list --porcelain>
config<TAB><registro de config --porcelain>
save-state<TAB>complete
```

Hay una o más filas `list` seguidas por las filas `config`; el contenido tras
el primer tab es el registro original, sin otra capa de escapes. Se conservan
los parsers existentes. El `status 2` declara que HEAD ya no está en una review;
`finish-pending` se resuelve desde el inventario igual que en una lectura normal.
Los informes se generan con los mismos emisores públicos, después del cambio
de rama y de liberar custodia. Comparten una lectura nueva de metadata, rama y
config efectiva; nunca reutilizan el snapshot anterior a Save para este estado.
No se invoca status, list o config como otro verbo. Comments completa aparte.

El receptor exige inicio, código, orden de secciones y final únicos, al menos
una rama guardada y exactamente un remoto efectivo. Una salida humana, vacía,
truncada, duplicada o incompatible usa el refresco normal. Sólo se consume una
respuesta con exit 0 sin timeout ni error de proceso; nunca se repite Save.

Un error del guardado conserva sus códigos anteriores, sin respuesta exitosa.
Si el guardado terminó pero falla el informe, Save conserva exit 0, escribe la
nota de lectura por stderr y omite el final. El receptor refresca el estado;
la falta del informe no significa que deba intentar guardar nuevamente.
Si HEAD terminó en otra review por un cambio concurrente, también se omite el
informe y se relee. Esto no promete una transacción global contra Git externo.
