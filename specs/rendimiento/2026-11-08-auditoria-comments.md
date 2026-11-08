# Auditoría de Comments frente a producción en Windows

El costo principal observado aparece al mantener la sesión, incluso sin
documentos de comentarios. Dentro de la CLI actual, esa sesión vacía agrega
aproximadamente 1,28 s a Save y 2,14 s a Continue frente a una review antigua
sin sesión. Las dos notas pequeñas agregan bastante menos. En IntelliJ,
navegación y Save mejoran frente al publicado; Continue resulta más lento.
Conviene priorizar custodia, metadata y la secuencia de Continue antes de
publicar Comments. No se implementaron cambios de producto en esta auditoría.

## Alcance

Ezequiel pidió comprobar cuánto agrega Comments antes de publicarlo, incluyendo
una comparación real con el plugin publicado. Se ejecutaron ambos plugins en
IntelliJ y se preparó un contraste separado de la CLI. Esta auditoría no cambia
producto, formatos, controles de custodia ni instalaciones del usuario.

Referencia publicada verificada el 8 de noviembre de 2026:

- Plugin **0.4.0**, descargado del Marketplace y verificado en `plugin.xml` y en
  el log de carga del IDE. SHA-256 del ZIP:
  `a32cdc860d954bb617817b757d5166477f66254608ed60586dcb24a4a4b9eba0`.
- CLI **0.9.0**, comprobada contra `latest` de npm y la integridad SHA-512 del
  paquete. Sus 18 archivos de `bin/` coinciden byte por byte con el tag `v0.9.0`.
- Actual: plugin **0.5.7**, CLI **0.10.9**, producto en `492877b`, checkout
  `a7517f0`. No se usó el auxiliar nativo experimental. SHA-256 del ZIP actual:
  `926fc3424c248bcd8a2a67beafad51e33464e23f25f05d964f89faba447bd1db`.

Fuentes de distribución:
[Marketplace, versión publicada](https://plugins.jetbrains.com/plugin/download?pluginId=com.ezevillo.gitreview&version=0.4.0)
y [metadata de npm](https://registry.npmjs.org/git-review-workflow/latest).

## Comparación en IntelliJ

Mismo host IntelliJ 2026.1/JBR, configuración y caché aisladas, misma ruta y
repositorio semilla. Tres archivos de texto cambiados, walkthrough del autor
con tres entradas —la CLI incorpora también el propio sidecar— y una edición
privada en disco. Sin red ni pruebas concurrentes. Las dos ventanas del usuario
permanecieron abiertas, sin reemplazar plugins ni cambiar sus perfiles.

Cada acción se lanzó desde el panel real. Un wrapper igual para ambas versiones
registró inicio, fin, argumentos y exit code de cada invocación; no modificó
stdout. Se verificaron la rama, el cursor, la limpieza de main después de Save,
el diff privado conservado y la restauración exacta con Continue. Local y Shared
se compararon byte por byte en los casos actuales.

El indicador comparable de la tabla es la **secuencia de llamadas principales
de la CLI disparada por el IDE**, desde su primera invocación hasta el final de
la última respuesta principal. Excluye espera humana, consultas `--why` y
`comments status` secundarias. No mide el último paint ni el clic completo.
Las consultas solapadas no se suman como si fueran secuenciales.

| Caso | Publicado | Actual | Muestras sin calentamiento |
| --- | ---: | ---: | --- |
| Next/Prev | 7,30 s | 1,74 s | 2 publicadas; 3 actuales |
| Save sin documentos de comentarios | 7,62 s | 4,46 s | 2 por versión |
| Save con Local y Shared guardados | No disponible | 5,40 s | 2 actuales |
| Continue sin documentos de comentarios | 8,71 s | 12,34 s | 1 por versión |

Son medianas de una muestra pequeña, sin alternancia entre versiones: primero
se probó la publicada y luego la actual. No justifican un porcentaje universal
de mejora. Sí muestran que la optimización del cliente se conserva y que
**Continue requiere atención**. La comparación histórica incluye todos los
cambios entre releases; por sí sola no atribuye una diferencia a Comments.

Save actual sin documentos tardó 4,53 y 4,40 s en la secuencia principal. Con
contexto confirmado y Local/Shared existentes fueron 5,94 y 4,86 s: hay variación
y este contraste también incluye la confirmación del contexto, no sólo dos
escrituras de Markdown. El lock del cliente se liberó a los 4,864 y 4,857 s en
el caso vacío; con notas, a los 6,264 y 5,203 s. En todos esos casos Comments
todavía se estaba consultando en segundo plano al liberar el lock.

La navegación pasó de siete invocaciones a dos: la mutación con respuesta
principal y la consulta secundaria de comentarios. Save pasó de ocho a dos.
La consulta secundaria actual de Comments sí consume trabajo y puede completar
después, pero su duración no es una espera obligatoria del botón.

### Documento pendiente

Se confirmó el problema del filtro amplio: **un archivo de código pendiente,
con Local y Shared sin cambios, provoca `comments paths --porcelain`**.
La consulta agregó 0,693 s de CLI; la secuencia principal completa fue 5,554 s
y el lock se liberó a los 5,972 s. Es un caso, no un recargo constante.
Los documentos de comentarios permanecieron idénticos y el código pendiente
no fue guardado por ese hook. Sólo se guardaron las ediciones que ya estaban
en disco, comprobadas también en el ref privado.

Para mantener pendiente ese buffer sintético se desactivó el autosave por
inactividad/desactivación únicamente en el perfil aislado. Al cerrar la prueba
se descartó ese buffer sintético cargando el contenido de disco; no se tocó
código del usuario.

La edición pendiente de Local **no quedó medida**: el IDE mostró
`Non-Project Files Protection`. Se canceló sin habilitar permisos de edición.
La muestra figura abortada y no entra en las medianas. No se presenta el ensayo
con código pendiente como una medición del flush de Local.

### Continue

La llamada actual de Continue ocupó 7,362 s dentro de una secuencia principal
de 12,342 s: quedan **4,980 s fuera del verbo**, entre preflight, refresco
principal y coordinación. El cliente todavía ejecutó version/status/list/config
antes y version/status después, además de las consultas secundarias.

`continue` todavía no ofrece la combinación de validación dentro del verbo y
respuesta principal opcional que ya utilizan Next/Prev y Save. En la CLI,
`restore_meta` también sigue leyendo y escribiendo cada clave individualmente.
La custodia hace varias pasadas de `comments_transfer_preflight`; sin el
snapshot por fase de los cierres, `review_config_read` vuelve a invocar Git.
Estos son sitios concretos para evaluar, conservando las relecturas frescas en
las fronteras de concurrencia.

## Contraste nativo de la CLI

Cuatro variantes del mismo repositorio semilla, una ronda de calentamiento y
cuatro medidas por variante, alternando el orden por ronda. Sin el IDE de la
auditoría abierto ni suites nuestras concurrentes. Las ventanas originales del
usuario permanecieron abiertas. Git Trace2 habilitado en todas las variantes.

- **Publicado:** review creada y operada con CLI 0.9.0.
- **Actual sobre review antigua:** creada con 0.9.0 y operada con 0.10.9, sin
  metadata ni sesión de comentarios.
- **Actual, sesión vacía:** creada con 0.10.9, sin Local ni Shared.
- **Actual con notas:** creada con 0.10.9, contexto confirmado y Local/Shared
  preparados, una observación pequeña en cada uno.

Save devuelve salida humana en todas las variantes; en las actuales se agrega
el guard capturado fuera del intervalo. No es el Save `--porcelain` del IDE.
Se midió también, por separado, la secuencia Save + status/list/config frescos.
Continue se midió sin IDE. Preparación y verificaciones quedan fuera de los
intervalos. Las cifras son medianas; entre paréntesis, mínimo–máximo.

| Variante | Save | Continue | Save + tres informes |
| --- | ---: | ---: | ---: |
| Publicado 0.9.0 | 3,94 s (3,90–4,06) | 5,40 s (5,14–5,44) | 5,78 s |
| Actual sobre review antigua | 3,27 s (3,17–3,45) | 6,12 s (6,08–6,30) | 5,01 s |
| Actual, sesión vacía | 4,54 s (4,52–4,57) | 8,25 s (8,13–8,54) | 6,30 s |
| Actual con Local/Shared | 4,83 s (4,69–4,98) | 8,59 s (8,36–9,36) | 6,65 s |

Dentro de la misma CLI actual, una sesión vacía agrega aproximadamente
**1,28 s en Save y 2,14 s en Continue** frente a la review antigua sin sesión.
Confirmar el contexto y tener ambas notas agrega otros **0,29 s y 0,34 s**
respectivamente en este fixture pequeño. Son diferencias entre medianas, no
una tarifa por documento o comentario ni el costo total causal de toda la
funcionalidad. La variante antigua todavía ejecuta controles comunes nuevos;
la comparación entre releases contiene además otras optimizaciones.

Los recuentos Trace2 son estables en las cuatro rondas medidas. Incluyen el
Git exterior que invoca `review`:

| Variante | Procesos Git de Save | De ellos, config | Procesos Git de Continue | De ellos, config |
| --- | ---: | ---: | ---: | ---: |
| Publicado | 49 | 35 | 57 | 34 |
| Actual sobre review antigua | 36 | 16 | 67 | 45 |
| Actual, sesión vacía | 45 | 21 | 89 | 63 |
| Actual con Local/Shared | 45 | 21 | 89 | 63 |

Esto respalda concentrarse en la coordinación de metadata y custodia:
Continue llega a **63 procesos config**, frente a los 21 de Save con la misma
sesión. El conteo no atribuye todos los segundos a config ni demuestra por sí
solo cuánto ahorraría agruparlos. Da un blanco concreto para un experimento
con el mecanismo por fases que ya existe, sin cambiar de lenguaje ni soporte.

Los 16 ciclos medidos —cuatro por variante— y los cuatro calentamientos terminaron con las
verificaciones previstas: Save deja main limpio; Continue restaura exactamente
el diff privado y el cursor; la sesión se conserva y las dos preparaciones
mantienen sus bytes. La variante antigua sigue sin sesión de comentarios.
Las cuatro fixtures terminan pausadas. No es una prueba nueva de todas las
carreras/fallos del protocolo, ni de Finish/Cancel.

Antes de la tanda válida se corrigieron dos supuestos del harness: releer la
sesión después de confirmar el contexto y aceptar status inactivo con stdout
vacío y exit 2. Se reinició la tanda; los ensayos interrumpidos no entran en
ninguna mediana. Los resultados no se mezclan con las mediciones anteriores
del auxiliar C: cambian fixture y superficie de salida.

## Qué conviene hacer después

**Sí conviene enfocar Comments antes de publicarlo**, especialmente su costo
de sesión sin uso y la reanudación. La carga de escribir dos notas pequeñas no
explica la mayor parte de la diferencia observada.

1. **Continue:** evaluar metadata agrupada por fase y copia de claves con el
   mecanismo existente; mantener identidad, locks, includes y relecturas en las
   fronteras de publicación. Extender a este verbo la validación interna y el
   retorno principal opcional, aplicando el contrato a los cuatro clientes.
   En el IDE hay 4,98 s observados fuera del verbo; no se promete eliminar todo
   ese tiempo. Medir la operación completa y verificar restauración exacta,
   fallos y concurrencia antes de adoptar el cambio.
2. **Save/Continue sin documentos:** reducir lecturas/procesos de custodia
   conservando la sesión exclusiva y la detección de claims huérfanos. La
   diferencia de 1,28/2,14 s mide el blanco observado, no un ahorro garantizado.
   Eliminar sesiones o controles sin reemplazar sus garantías no está validado
   por esta auditoría.
3. **Clientes con código pendiente:** hacer que la información de propiedad
   que produce la CLI permita descartar buffers ajenos sin otra consulta,
   cuando la identidad vigente lo permita; conservar el fallback autoritativo
   ante estado desconocido o cambiado. Definir antes su vigencia y guardas.
   La consulta medida de 0,69 s pone una escala al beneficio de ese caso, muy
   distinta de prometer retirar varios segundos de cada Save.

La implementación queda pendiente. Esta auditoría no incorpora Rust, SQLite,
un daemon ni cambios de protocolo. La siguiente decisión puede apoyarse en
estos blancos medidos y no en una estimación de velocidad por lenguaje.

## Evidencia y límites

Evidencia local bajo
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/comments-audit/`:

- `ui-cases.json`, `ui-summary.json`, `cli-calls.tsv`, `ui-inputs.jsonl`:
  acciones, verificaciones y tiempos originales, incluidos calentamientos.
- `ide/log-prod/idea.log`, `ide/log-current/idea.log`: versiones cargadas,
  invocaciones y liberación del lock actual.
- ZIP publicado, paquete npm, metadata e integridades; copias exactas de ambas
  CLI y plugins. `ui-control.py` y `analyze-ui.py` documentan el cálculo.
- `native-result-path.txt` apunta a la tanda válida, con `summary.json`,
  `samples.json`, fixtures y trazas por operación. `native-benchmark.py`
  documenta el contraste; los logs de los intentos iniciales y de la tanda
  válida se conservan en `%TEMP%/git-review-comments-audit/`.
- `datos/2026-11-08-comments.json`, junto a este informe en el repositorio,
  conserva las muestras, medianas, rangos y recuentos utilizados.
- `prod-ui-fixture` y `current-ui-fixture`: repositorios del ensayo preservados.
  La fixture anterior de otra investigación se restauró a su ruta original.

El host aislado informó fallos de su daemon nativo de loopback al iniciar.
Se esperó la estabilización y se excluyeron calentamientos. No se diagnosticó
a Defender como causa ni se cambió su configuración. Los tiempos dependen de
esta máquina y de sus procesos abiertos; no son un SLA. No se midieron Finish,
Cancel, PRs grandes, muchos comentarios ni otros IDEs.

El código confirma el mismo filtro inicial amplio en VS Code y Visual Studio:
`commands/comments.ts`, `host/SessionCommentSave.kt`,
`GitReview.Host/SessionCommentSave.cs` y `VsHostActions.cs`. La TUI no tiene
buffers de editor que guardar con ese hook. El costo interno de la CLI afecta
a los cuatro clientes; los tiempos del IDE aquí corresponden a IntelliJ.
