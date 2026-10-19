# Contrato: Markdown de comentarios v1

Estado: diseño para implementar. Autoridad: FR-001..FR-024 y FR-039..FR-052 de
[spec.md](../spec.md). La misma gramática sirve para Local y Compartido.

## Documento y entradas

```markdown
# Comments

<!-- git-review-comments v1
context 6adba17e097bfa5202ed331f4f646ad9700bdd10
-->

## 4. src/api.ts — head, lines 12–15

<!-- git-review-comment v1
base 1111111111111111111111111111111111111111
head 2222222222222222222222222222222222222222
base-path src/api.ts
head-path src/api.ts
side head
start 12
end 15
-->

Why does this return before checking the permission?

## 4. General

How does an interrupted operation recover?
```

Los OID del ejemplo son ilustrativos. El preámbulo y el cuerpo son prosa libre.
El encabezado de entrada reservado es `^## [0-9]+\.[ \t]*(.*)$`, en columna
cero y fuera de código/comentarios HTML. La etiqueta puede estar vacía. Los
demás encabezados se conservan como prosa. Un encabezado reservado escrito
como ejemplo debe ir cercado, citado o indentado.

Cada bloque termina ante el siguiente encabezado reservado reconocido o EOF.
El ordinal físico es 1-based y distinto del número visible: números repetidos,
huecos y varias entradas por archivo son válidos. No hay ids de entrada,
estado, clasificación ni respuesta obligatoria. Borrar el bloque lo elimina;
moverlo cambia su posición. No se deduce significado del texto.

El marcador de documento identifica un contexto, no una entrada. Debe ser único
en el preámbulo; ambas versiones usan el mismo token. Un documento manual sin
marcador sigue siendo legible/editable: la custodia local registra su contexto.
Una incorporación explícita puede añadir el marcador sin regenerar la prosa.
Consultar o iniciar una review no modifica por sí solo el archivo versionado.

## Metadata opcional de ubicación

El bloque `git-review-comment v1` debe aparecer inmediatamente después del
encabezado, admitiendo una línea vacía. Las claves se separan del valor por un
espacio; el valor ocupa el resto completo de la línea. El encabezado visible es
una descripción para lectores Markdown: no se parsean rutas a partir de él.

| Campo | Regla |
|-------|-------|
| `base`, `head` | Ambos o ninguno; OID completos SHA-1/SHA-256 resueltos, de commit o tree |
| `base-path`, `head-path` | Ruta relativa a raíz en cada lado existente; distintas para renombres |
| `side` | `base` o `head`, cuando existe ubicación de código |
| `start`, `end` | Ambos o ninguno; enteros positivos inclusivos, inicio ≤ fin |
| `unversioned` | `1` si la ubicación se tomó de código/buffer sin versión reproducible |

Una entrada general puede no tener metadata, o llevar base/head sin paths para
consultar el rango completo. Una entrada de archivo puede omitir líneas. En
adiciones/borrados se omite la ruta del lado que legítimamente no existe. El
lado señalado por líneas debe tener ruta. Una captura versionada valida los
objetos y las coordenadas; una captura manual puede tener objetos ya ausentes.
Eso afecta a su consulta, no a la conservación o renumeración del bloque.

El codec de paths escapa `%`, TAB, CR, LF y `>` como `%25`, `%09`, `%0D`, `%0A`
y `%3E`. Se decodifica una sola vez, sólo esos escapes; el resto de UTF-8,
espacios, dos puntos y backticks se conserva. No es una URI. El writer escapa
primero `%`; valores desconocidos o escapes inválidos se diagnostican. Nunca
se usa el path para construir directorios internos ni como código de shell.

Las rutas obtenidas de git para compararlas con texto escrito pasan por
`changed_paths`; el lector usa `walk_normalize` y el trim vigente. El codec
sólo transporta bytes y no es otra normalización. Todas las consultas usan
argv separados y pathspec literal, incluidos `*`, `?`, `:` y nombres con guion.
El wire TSV mantiene la limitación existente para rutas con TAB/CR/LF: se
diagnostica una ruta no representable antes de emitir un registro ambiguo;
la prosa manual que la contenga se conserva.

Metadata duplicada, una versión desconocida o claves obligatorias incompletas
producen diagnóstico; no autorizan resolver contra HEAD. Claves futuras se
conservan, y la renumeración no necesita interpretarlas. Si el contorno del
bloque es inequívoco, sus números se pueden corregir aunque su referencia
histórica sea inválida. Si los límites no pueden preservarse, no se reescribe.

## Renumeración y fences

Una máquina de estados en awk POSIX reconoce código cercado con backticks o
tildes: apertura con 0–3 espacios y al menos tres caracteres iguales; cierre
del mismo carácter con longitud igual o mayor, seguido sólo por whitespace.
La información de apertura con backticks no puede contener otro backtick.
Una apertura sin cierre hace código del resto; no inventa entradas allí.
Encabezados citados/indentados y dentro de comentarios HTML no son entradas.
Un comentario HTML sin cierre que vuelva ambiguo el contorno produce error.

El lector mantiene vistas normalizada y original de cada línea. Renumerar
cambia exclusivamente los dígitos de los encabezados reales, en orden físico,
por `1..N`. Conserva cuerpos, ubicaciones, metadata, preámbulo, BOM, cada EOL
y presencia/ausencia de LF final. Es idempotente y no ordena por los números
previos. No usa `gensub`, `RT` ni extensiones GNU de `match`.

`add` calcula el siguiente número como cantidad de bloques + 1; no renumera
las entradas anteriores como efecto lateral. Texto vacío/whitespace no agrega
un bloque. Antes de anexar, exige que el documento termine fuera de una fence
o comentario HTML abierto: si no, rechaza sin cambiarlo, para que la nueva
entrada no quede escondida dentro del código. El texto recibido tampoco puede
contener encabezados reservados fuera de fences/citas ni dejar un contenedor
abierto. Se conserva en el compositor ante el diagnóstico y puede corregirse
o cercar el ejemplo. La escritura valida que se agregó exactamente un bloque;
no escapa ni reinterpreta silenciosamente el texto del usuario.

Prosa vacía y entradas en curso editadas manualmente son válidas; esos casos
no impiden abrir, guardar o custodiar el documento. Ni `add` ni `renumber`
filtran por archivos presentes en el diff.

Todas las escrituras siguen el protocolo de temporal, guardas y recuperación
de [lifecycle.md](lifecycle.md). Un error no deja una reescritura parcial.

## Histórico

Los OID guardados nunca se cambian al renumerar, iniciar otra pasada o avanzar
step. Una ubicación `unversioned` no promete reconstruir esas líneas. Si se
guardó también base/head, sólo describen el rango versionado y el cliente lo
explica antes de mostrarlo.

Consultar verifica primero los árboles y blobs registrados. Archivo borrado
actualmente, lado inexistente por adición/borrado y objeto histórico ausente
son hechos distintos. Sólo el último impide reconstruir el contenido requerido.
No se hace fetch, checkout, nueva sesión, nueva ref ni transporte de objetos.
Los visores pueden materializar buffers temporales al consultar; no se guardan
como parte del comentario ni se reutilizan como respaldo histórico.
