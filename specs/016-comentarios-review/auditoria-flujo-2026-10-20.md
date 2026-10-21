# Auditoría del flujo de comentarios — 20 de octubre de 2026

Se contrastó la implementación actual con el chat «Ver si Shared aparece arriba»
(`01a156ee-2db1-7812-9c34-51381a8aa8ea`) y sus aclaraciones posteriores.
El flujo principal está implementado, pero se reprodujeron dos problemas adicionales.
La primera pasada sólo agregó evidencia. La corrección posterior implementa
ambos arreglos en la CLI y lleva las regresiones a la suite habitual.
Las ubicaciones y el SHA-256 de las secciones de hallazgos describen la versión
auditada antes del arreglo.

## Criterios confirmados en el chat

- Comments aparece entre Walkthrough y Compare en el panel principal.
- Una rama descargada permite consultar su `.review/comments.md` sin estado privado.
- Agregar requiere una sesión; Compare permite solamente Local y conserva sus notas.
- Shared del repositorio prevalece sobre la preparación de una review guardada.
- La review prepara el Shared propio del PR y excluye comentarios heredados de la base.
- Save/Continue conserva altas y borrados sin cambiar el límite de descarte.
- Finish entrega el documento completo, lo stagea y después libera su preparación editable.
- Undo recupera la preparación actual, incluidos los borrados; Cancel descarta la pasada
  y conserva los comentarios originales de la rama.

## P1: Finish puede eliminar una preparación Shared que no llegó al índice

Ubicación: `bin/git-review-lib.sh:1687`, dentro de `comments_delivery_stage`.
La liberación posterior está en `comments_release_shared`, línea 1775.

La entrega copia la preparación a `.review/comments.md`, pero luego calcula el blob
a stagear leyendo nuevamente ese archivo del working tree. Si otro editor lo cambia
entre el rename de entrega y ese cálculo, stagea los bytes ajenos y declara éxito.
La publicación registra la revisión de la preparación original y después la elimina,
sin verificar que coincida con el blob efectivamente stageado.

Reproducción determinista: una barrera FIFO detiene el `git hash-object -w` de la
entrega; se reemplaza el archivo del repositorio y se libera la barrera.

Resultado observado:

- Finish termina con código 0.
- El índice contiene `Concurrent replacement after delivery rename.`.
- La preparación original ya no existe.
- El blob de la observación original tampoco existe en los objetos de Git.

Se pierde la observación preparada. La copia externa usada por la prueba es sólo
evidencia del test y no forma parte de los mecanismos de recuperación del producto.

La corrección debe vincular la entrega al contenido preparado: stagear una instantánea
verificada y comprobar su revisión antes de liberar la preparación. Un cambio concurrente
del destino debe conservar ambas versiones y dejar la entrega pendiente.

## P2: Shared del repositorio oculta Local de la review guardada con el mismo contexto

Ubicación: `bin/git-review-lib.sh:127` y el salto de contexto en la línea 748.

Secuencia:

1. La rama trae Shared con una identidad portable.
2. Se inicia su review, se agrega un comentario Local y se ejecuta Save.
3. Se hace checkout de esa rama y se consulta `comments status --porcelain`.

Shared apunta correctamente al repositorio. Sin embargo, Local apunta a
`contexts/<contexto>/local.md`, ausente, en lugar del documento real de
`sessions/<sesión>/local.md`. El recorrido omite la preparación guardada porque su
token coincide con el ya emitido para el repositorio.

Los comentarios Local siguen en disco y Continue los recupera, pero el panel presenta
su ausencia. El problema nace en la CLI, por lo que afecta a los clientes que consumen
esa consulta. Dar prioridad al Shared del repositorio no debe ocultar el Local
independiente de la sesión guardada.

## Verificación ejecutada

En contenedores y repositorios temporales:

- Los 363 casos existentes de `tests/comments-*.bats` pasan, sin omisiones.
- El contrato de los cuatro clientes pasa.
- Las 46 pruebas del verificador del contrato pasan.
- Las reproducciones adicionales dejan dos fallos esperados, correspondientes a P1 y P2.
- Un control adicional con Shared entrante y `Finish --onto-source → Undo → Cancel`
  pasa: descarta los comentarios nuevos y conserva el original de la rama.

Se verificó que el SHA-256 de `bin/git-review-lib.sh` del contenedor coincide con el
archivo del workspace: `0700e0bbb307676f8156cfbba561f69ad0e109d8bba0c7f07a96cf73cda313f0`.
En esta pasada no se ejecutaron los hosts gráficos de los IDE ni las suites completas
de Kotlin, .NET y Go; la comprobación de ubicación en los cuatro clientes es estructural.

## Reproducir

Las reproducciones se incorporaron a `tests/comments-delivery-race.bats` y
`tests/comments-saved-repository.bats`. Además de los dos fallos originales,
cubren ediciones después de staging y publicación, cambios concurrentes del
índice, Local retenido anterior, vacío y ausente, consultas Entries/Diff y
Save/Continue/Finish/Undo/Cancel. Desde la raíz del repositorio:

```sh
./tests/run-docker.sh --print-output-on-failure tests/comments-delivery-race.bats tests/comments-saved-repository.bats
```

Los doce casos pasan después de la corrección. Los tests de concurrencia usan
`timeout`, disponible en la imagen Alpine de pruebas; las barreras FIFO siguen
siendo necesarias, sin sustituirlas por esperas temporizadas.

## Corrección

- Shared se convierte en un blob inmutable desde la preparación antes de tocar
  el destino. Su OID gobierna staging, publicación y el guard de Undo.
- La preparación, el destino y la entrada stageada se comprueban antes de
  liberar Shared. Las divergencias conservan la preparación pendiente y visible.
- Cuando Shared del repositorio comparte contexto con una review guardada,
  Local sale de esa sesión. Se conserva su custodia, sus permisos y la lectura
  del repositorio para Shared. `--all` sigue incluyendo ambas rutas de Shared.
- Las consultas históricas usan la misma resolución; Continue recupera ambas
  preparaciones, sin volver a elegir un resultado Local anterior.
- Shared entrante sin cambios también queda protegido: una edición posterior a
  la decisión de conservarlo no se confunde con la versión original al liberar
  la preparación.

## Verificación de la corrección

- Las doce regresiones pasan, incluidos los reintentos después de cambios
  concurrentes y los ciclos posteriores de Undo/Cancel.
- ShellCheck pasa para la biblioteca, el verbo y los dos archivos Bats nuevos.
- El contrato de los cuatro clientes y las 46 pruebas de su verificador pasan.
- La pasada general ejecutó 1.433 casos, con cuatro omisiones por entorno.
  Cuatro comprobaciones de empaquetado necesitaron restaurar el directorio de
  objetos vacío para reconocer la metadata Git copiada: los doce casos de
  `packaging.bats` se repitieron correctamente, con el smoke npm omitido.
- Quedan dos fallos ajenos a estas modificaciones: `release-notes.bats` rechaza
  el encabezado `[Unreleased]` de `tui/CHANGELOG.md`, y `version-consistency.bats`
  rechaza el de `vscode-extension/CHANGELOG.md`. No se modificaron esos archivos.
- La protección adicional de Shared entrante sin cambios se agregó después
  de iniciar la pasada general. La revisión final completa de comentarios pasó
  sus 375 casos, sin omisiones, sobre el mismo archivo del workspace:
  `88f388a269ef04a27c85150a94e1c9a36dea7c47ad600d645791e5e0aead77fe` (SHA-256).
- `git diff --check` no encuentra errores en los archivos modificados.
