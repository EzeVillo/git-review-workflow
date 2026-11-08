# Escalabilidad de Save en Windows

## Pregunta y método

Ezequiel pidió distinguir el costo fijo de los cierres del costo que crece con
muchos archivos. Se perfiló CLI 0.10.8, sin cambiar código de producto, sobre
seis repositorios sintéticos separados. Modo whole, un comentario Local y una
edición sin stage en un archivo. Todos los PR cambian la primera línea de cada
archivo seleccionado; el resto es texto determinista y comprimible.

Por caso: un calentamiento y dos muestras medidas de Save con guard y
`--porcelain`, Trace2 en todas; Continue y las aserciones quedan fuera. Se
comprobaron main limpio al guardar y conservación exacta de diff y prosa/sesión
al retomar. Cada caso terminó pausado, recuperable. No se midieron IDE, flush
ni lectura inicial de status; tampoco filtros, LFS o red. Las suites estaban
apagadas y no se tocaron las ventanas originales.

Son muestras diagnósticas, no percentiles ni garantías. La columna switch es
`exit.t_abs` del propio Git: excluye el costo de arrancarlo desde la shell. El
resto de Git no desaparece de la duración total; no se resta esa columna como
si fuera una medición completa de todos los costos de checkout.

## Resultados

| Archivos del repo | Archivos cambiados por el PR | Tamaño nominal por archivo | Save + estado final | Git switch interno |
| ---: | ---: | --- | ---: | ---: |
| 10 | 10 | 1 KiB | 6.36 s | 0.05 s |
| 1000 | 10 | 1 KiB | 6.26 s | 0.08 s |
| 10000 | 10 | 1 KiB | 6.48 s | 0.19 s |
| 1000 | 1000 | 1 KiB | 7.92 s | 0.99 s |
| 10000 | 10000 | 1 KiB | 15.51 s | 8.97 s |
| 10 | 10 | 1 MiB | 7.03 s | 0.07 s |

Todos los casos ejecutaron **52 procesos Git**, de ellos 21 config y 12
rev-parse. En whole no hay un Git por archivo. El caso de un repo de 10000
archivos con sólo 10 cambiados se parece al pequeño. Cambiar 10000 archivos
sí crece: casi 9 s están dentro del cambio de rama, que restaura archivos.

Esto separa dos problemas. Hay un piso de unos seis segundos que no explica
el tamaño del PR. Además, el modelo actual hace I/O al volver a la rama de
origen; ese trabajo crece con los archivos que realmente debe reemplazar.
El caso de archivos de 1 MiB varió de 6,18 a 7,88 s y usa texto comprimible:
no permite proyectar el costo de binarios grandes ni de filtros externos.

## Próximos cortes propuestos

1. **Eliminar procesos por extracción de metadatos.** Ya se consulta config en
   bloque por fase, pero los consumidores vuelven a extraer campos mediante
   sustituciones de comandos. El siguiente cargador debe dejar los valores
   comunes utilizables en la misma shell. Debe conservar la representación
   canónica del guard, bytes especiales, ausente/vacío y las relecturas frescas;
   nunca evaluar datos como código ni cachearlos entre operaciones.
2. **Agrupar movimientos de referencias de step.** Save ejecuta hoy por cada
   paso con ediciones un rev-parse y dos update-ref. La lista debe traer OID y
   nombre de una vez y producir un lote con controles del valor anterior.
   [update-ref --stdin](https://git-scm.com/docs/git-update-ref) puede preparar
   las modificaciones conjuntamente; no vuelve transaccional el checkout,
   config o Comments ni promete visibilidad indivisible para lectores externos.
3. **Persistencia agrupada de metadatos con recuperación definida.** El origen
   debe seguir completo hasta que el destino tenga código y custodia válidos.
   Medir la mejora de extremo a extremo y probar fallos entre fases antes de
   reemplazar la copia actual. El objetivo es bajar el piso, no sólo el panel.
4. **Separar el costo de pausar del de restaurar miles de archivos.** Para
   evitar ese I/O haría falta un flujo de review en un worktree dedicado, con
   pausa/reanudación sobre ese directorio y sin cambiar el checkout principal
   en cada pausa. Es una evolución del modelo y de los clientes, no parte del
   corte actual. Antes de adoptarla hay que diseñar custodia, reapertura,
   limpieza y recuperación; no se cambia por sorpresa el significado de Save.

La aceptación debe incluir casos pequeños, repo grande con PR pequeño y PR de
1000/10000 archivos. También step con muchos pasos que llevan ediciones. No
se da por resuelto el uso interactivo sólo por mejorar un porcentaje.

## Prueba aislada de copia nativa

Se comprobó en Windows la [copia de rama con configuración y reflog](https://git-scm.com/docs/git-branch):

- Sin destino previo, conserva origen y working tree, incluidos valores con
  LF, tab, backslash y salto final.
- Con config de destino huérfana, conserva claves viejas y duplica reviewsource
  (la antigua queda después de la nueva). No sirve como reemplazo ciego de la
  copia selectiva.
- Con config.lock presente, sale con 128 pero la rama destino ya existe sin
  su config. El origen y working tree siguen intactos; no hay una transacción
  global entre ref/config que podamos presumir.
- Con ref destino existente, rechaza sin alterar el origen.

La prueba descarta aplicar branch -c directamente como un atajo ya validado.
No es una implementación de Save. El perfil y la propuesta quedan separados
de los cambios de comportamiento: **no se modificó código de producto**.

## Artefactos

`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/save-scaling/`.

summary.json contiene cinco casos; summary-large-repo.json el adicional de
10000 archivos con PR de 10. Ambos guardan SHA de HEAD y de la biblioteca,
muestras completas y breakdown de procesos. Los scripts, trazas y copy-probe.json
permiten revisar el método y los efectos reales de la copia nativa.
Sin push, tags ni publicación. CONTRIBUTING.md, PRUEBAS-LOCALES.md y auditorías
ajenos al trabajo permanecen intactos.
