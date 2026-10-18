# Contrato: identidad, custodia y cierre

Normativo para el diseño de [spec.md](../spec.md). Las copias de baseline son
prosa de comentarios; no contienen código del PR ni snapshots de sus archivos.

## Resolver el contexto sin proveedor

Resolver una sola vez en `comments_context_resolve`; los clientes consumen su
respuesta, nunca reconstruyen identidad por branch/path. Obtener el rango
completo `Bfull = merge-base(baseRef, tip)`, separado del lower de start, `--from`
y delta. Conservar origen canónico y destino de integración. Compare usa sus
dos extremos resueltos como contexto de comparación; no presupone base de PR.

1. Leer el marcador de `.review/comments.md` en tip y Bfull. Token de tip
   válido y distinto del de Bfull acredita documento propio del rango.
   Token igual a Bfull o archivo idéntico al de Bfull es heredado: no cargar su
   prosa como comentarios del nuevo PR. Si el archivo cambió en el rango y no
   tiene marcador, conservarlo como semilla del documento del PR y asignar
   contexto al confirmar una mutación; no desechar Markdown manual.
2. Sin marcador portable propio, buscar contextos locales por origen/destino.
   Excluir aquel cuyo último tip ya sea ancestro de la base actual. Continuar
   el único candidato cuyo último tip sea igual o ancestro del tip actual.
3. Con candidatos incompatibles, force-push no demostrable, marcador en
   conflicto con registro local o falta de base completa: `ambiguous`.
   No continuar ni mezclar silenciosamente. Sin candidatos y con rango completo,
   proponer `fresh`. En compare, la pareja exacta y contexto explícito permiten
   recuperar resultados; otras parejas no se unen por nombre de `<b>`.
4. `init/add --new-context` confirma un contexto distinto;
   `--use-context <id>` elige uno existente. Sólo se ofrece cuando hace falta
   resolver o declarar una identidad diferente, incluso si el resolver propone
   continuidad. Se permite antes de editar la pasada; no reasigna ni pierde
   preparación nueva sin conservar. Esta selección no elige el
   destino de los comentarios siguientes.

El contexto usa un token opaco validado y exclusivo, no un id por entrada. Se
genera sin crear refs/objetos de retención; el registro se crea sin sobrescribir
otro token existente. Misma rama e historia aún no integrada pueden representar
dos PR de proveedor indistinguibles: la declaración explícita cubre ese caso.
No se promete inferencia universal de identidad externa.

## Preparación y resultados

Al iniciar una sesión nueva, registrar custodio, contexto y bytes/presencia
de partida. Copiar Local previo aplicable y preparar Compartido desde su fuente
propia. Los archivos que no existen siguen ausentes hasta creación explícita
o primer comentario confirmado; cancelar no los crea. Registrar el baseline
versionado real aunque sea un documento heredado que no se carga como semilla.

Para continuar un Compartido local previamente preparado, comparar fuente S,
resultado R y anterior baseline fuente O por bytes/presencia:

| Condición | Resultado |
|-----------|-----------|
| S = O | Continuar R |
| S = R | Continuar S |
| R = O | Adoptar S |
| S y R cambiaron respecto de O | Conservar ambos y diagnosticar conflicto |

Es una conciliación de versiones del mismo Compartido. Local no interviene.
No hay merge automático ni copia entre documentos. Un documento mal formado se
custodia como bytes y no impide los verbos de código que no lo interpretan.

Cada sesión tiene directorio exclusivo y dos documentos editables. El resultado
durable es una generación completa del par; un manifest distingue ausente,
vacío y presente. Crear toda la generación y cambiar después el puntero `current`
con rename. Un fallo antes de publicar deja accesible la generación anterior;
un reintento no publica una mitad nueva con otra antigua.

## Operaciones y propiedad

| Operación | Política |
|-----------|----------|
| `next/prev` | Nunca banca ni reubica los documentos; nuevas capturas usan el nuevo par de refs |
| `save` de review | Preflight de propiedad; transfiere custodio a review-saved, conservando sesión y baseline |
| `continue` | Valida identidad/owner; transfiere al activo sin sustituir documentos creados durante la pausa |
| `comments save` | Sólo compare: publica ambos como resultado local, avanza checkpoint y continúa |
| `abort` de sesión | Descarta posterior al checkpoint; preserva resultado anterior/guardado expresamente |
| `forget --saved` | Descarta sólo preparación bajo su custodia; respeta resultados anteriores |
| `finish --abort` | Deshace el cierre de código y vuelve con la prosa actual; no descarta toda la pasada |
| `clean` incompleto | Mismo descarte protegido de la sesión que elimina |
| `clean` completado | Conserva resultados de comentarios |
| `clean --fixes-only`, `forget --delta/--draft` | No poseen ni eliminan comentarios |

Una sesión guardada retiene su directorio y cambia de custodio, evitando mover
dos documentos de forma parcial. Guardar una review no avanza por sí solo el
checkpoint de una sesión descartada después. El baseline anterior sigue siendo
el límite de descarte. `save` no publica `.review/comments.md`.

Metadata faltante se lee defensivamente. Una sesión antigua sin claves nuevas
se inicializa al solicitar comments; su consulta sigue siendo read-only. Las
claves comunes nuevas se excluyen expresamente de los guards step/walk.
Un worktree no adopta archivos del gitdir de otro por encontrar sus claves
compartidas en config. Una colisión falla antes de mover ramas o borrar datos.

## Escritura, concurrencia y recuperación

1. Adquirir lock de contexto con `mkdir`, registrar dueño y liberarlo por trap.
   No robar locks cuya vigencia no se pueda demostrar.
2. Resolver otra vez sesión/custodio/cursor/extremos y comprobar tokens.
3. Leer presencia y bytes del original; producir temporal hermano completo.
4. Revalidar bytes/contexto inmediatamente antes de sustituir. Ante diferencia,
   conservar original y candidato recuperable, diagnosticar y no sobrescribir.
5. Reemplazar por rename sólo después de validar todo el procesamiento.

Los IDE guardan únicamente el documento afectado antes de escribirlo mediante
la CLI y abortan si no se guardó. Para `comments save`, validar ambos y guardar
sólo los dos documentos de esa sesión; nunca Save All ni archivos de código.

La exclusión es completa entre escritores cooperantes del producto. Frente a
un editor externo es optimista: POSIX no proporciona compare-and-swap de un
path contra bytes esperados. Se conserva recuperación del original/candidato y
se prueban cambios externos detectables antes del reemplazo. No se promete
inmunidad a una escritura que ocurra entre la última comprobación y rename.

## `finish`: entrega sin repetir extracción

1. Antes de `record_undo`, conservar preparación y baseline. Extraer/replay de
   código mediante los caminos actuales; no escribir comments en la review.
2. Una vez completada la extracción y estando en la rama de salida, si
   Compartido no cambió respecto de su semilla, no escribirlo. Vacío o sin
   entradas puede mantenerse como prosa; no se impone eliminar el documento.
3. Si cambió, comparar destino real con `destination_baseline`. Si ya es igual
   al preparado, tratar como entrega realizada. Si coincide con el baseline,
   escribir el preparado completo sin stage adicional, commit ni push.
   Ante cambios ajenos o destino de tipo inseguro (p. ej. symlink), conservar
   preparado y destino, sin sobrescribir. `prepare --check` proporciona la
   comparación de prosa baseline/preparado/destino. La resolución manual iguala
   preparado y destino al resultado elegido; el reintento reconoce esa igualdad
   y nunca acepta cambios concurrentes como un baseline nuevo implícito.
4. `record_exit` corre después de la entrega para que la snapshot de salida
   reconozca la propia escritura. Si falló la entrega, registrar igualmente
   la salida de código, preservar ambos documentos y marcar entrega pendiente.
   Informar que las correcciones se extrajeron y el documento no se preparó;
   retornar exit 1, no presentar éxito completo ni intentar otra extracción.
5. `finish --resume` reconoce entrega pendiente antes del guard que exige
   `review/*`; `comments prepare --context` reintenta únicamente esa entrega.
   Ambos son idempotentes y se niegan si se cambió de rama/destino.
6. En reintento, actualizar `reviewundoouttree` sólo para el path entregado
   partiendo de la snapshot anterior, o exigir intactos los otros paths.
   Nunca recalcular todo desde el working tree y absorber cambios posteriores.
7. `finish --abort` mantiene sus guardas de divergencia/`--force`, restaura el
   estado anterior al cierre y deja las dos prosas disponibles para seguir.

La entrega usa el archivo de salida real también con `--onto-source`.
Una review sin ediciones de código puede entregar Compartido sin fabricar un
commit de correcciones. Un `finish` en conflicto aún no entrega el documento.
Un problema de parseo histórico no bloquea guardar/entregar sus bytes.

## Fallos que deben probarse

Fallo de I/O en cada fase de publicación del par; pérdida de metadata; dos
CLI concurrentes; edición externa antes del reemplazo; ownership cruzado entre
worktrees; colisión durante pausa; entrega fallida tras código extraído;
reintento desde otra rama; cambios posteriores antes de `--resume`; undo tras
entrega y tras conflicto; nueva pasada con fuente y preparado divergentes.
