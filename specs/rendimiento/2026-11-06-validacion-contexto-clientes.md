# Latencia de los clientes y validación del contexto de una acción

## Diagnóstico observado

El sandbox de IntelliJ carga el plugin 0.5.1. En su log del 6 de noviembre,
`next` tarda aproximadamente 1,45 s, pero la lectura completa anterior y la
posterior cuestan otros 1,4 s cada una. El refresco publica primero el panel y
después consulta Comments, aunque mantiene la operación ocupada hasta terminar.
Cancel agrega una consulta de custodia de documentos antes de descartar.

El volumen de salida no explica esa latencia: una consulta del sandbox devolvió
298 bytes de estado y 1.029 bytes de comentarios. El costo está en crear procesos,
consultar Git, reconstruir el recorrido y comprobar documentos y revisiones.

| Cliente | Validación previa de una navegación normal | Lectura posterior |
|---|---|---|
| IntelliJ | Vuelve a leer el estado completo, sin Comments | Estado y Comments; espera ambos |
| Visual Studio | Modelo en Next/Prev; prelectura completa en otras mutaciones | Estado y Comments; navegación además repite el refresco |
| VS Code | Contrasta el modelo que ya tiene | Estado y Comments; espera el refresco |
| TUI | Contrasta el modelo que ya tiene | Ya separa estado principal y detalles |

La comprobación evita actuar sobre otra review si la rama o la sesión cambió
desde que se mostró el panel o se abrió una confirmación. No corresponde quitarla.
Pedir todo el panel para comparar su identidad es trabajo innecesario.

## Primer cambio autorizado: validación dentro de la invocación

La CLI publica un testigo opaco `guard` junto al estado. El cliente conserva
ese testigo con el modelo que originó la acción y lo envía mediante
`git review --expect-state <guard> <comando> ...`. La CLI vuelve a calcular la
identidad antes de ejecutar el verbo. Si difiere, devuelve el código 4 sin
ejecutarlo. El cliente recarga el estado completo y muestra su aviso de estado
obsoleto. No reintenta automáticamente una acción sobre una review diferente.

El testigo identifica el gitdir, HEAD, rama y metadata de la review. No incluye
el working tree ni el contenido de los buffers: editar código no debe invalidar
la intención de navegar o guardar.

Este primer corte emite el testigo durante una review activa, incluido un Finish
en conflicto. Fuera de ella se conserva el recorrido anterior: Start, Compare y
los cierres pendientes requieren información de inventario y configuración que
no corresponde reemplazar por la identidad de una review activa.

Los cuatro clientes usan el mismo contrato. Donde ya se hacía una prelectura
completa, el caso coincidente la evita. Donde se contrastaba sólo el modelo,
se agrega comprobación contra el repositorio real. Si una CLI anterior no emite
testigo se conserva el comportamiento anterior; no se inventa un token local.

Esto no sustituye los locks y precondiciones propios de los verbos ni las
revisiones de los documentos Local/Shared. Tampoco convierte una operación Git
externa concurrente en una transacción de la CLI. El objetivo de este corte es
reemplazar la validación costosa, manteniendo las protecciones existentes.

## Cambios de rendimiento que quedan fuera de este corte

- Devolver el estado actualizado desde la mutación y reutilizar su lectura.
- Liberar la navegación al confirmar el estado principal, dejando Comments y
  explicación en segundo plano con rechazo de respuestas antiguas.
- Omitir consultas de guardado de comentarios cuando no hay buffers sin guardar.
- Reducir otros procesos internos de las consultas de la CLI.
- Eliminar el refresco posterior duplicado de navegación en Visual Studio.

El prototipo local de `next/prev --porcelain` se apartó y se conservó como patch
de evidencia. No se integra como parte de la validación.

## Verificación y medición

Se comprobarán coincidencia, cambio de rama/HEAD/metadata, gitdirs distintos,
ediciones permitidas, cierres pendientes y ausencia de efectos al rechazar.
Los clientes deben conservar el testigo de la acción, refrescar ante código 4 y
mantener la compatibilidad con reportes sin `guard`.

### Windows nativo: secuencia de llamadas

Se comparó el código anterior (`47acbcb`) con este cambio en un repositorio
temporal con dos entradas de walk, alternando Next y Prev. Se ejecutaron cuatro
muestras por variante, con el estado inicial ya cargado fuera del tiempo medido.
El flujo anterior hace versión → estado → mutación → versión → estado → Comments;
el nuevo hace mutación con validación → versión → estado → Comments.

| Medición | Anterior | Con validación en la CLI |
|---|---:|---:|
| Mediana hasta completar la mutación | 5,05 s | 2,68 s |
| Mediana de la secuencia completa | 10,11 s | 6,96 s |
| Rango de la secuencia completa | 8,60–10,39 s | 6,51–8,13 s |

La reducción observada del total fue del 31 %. La mutación sin prelectura sigue
teniendo costo: la CLI comprueba el testigo antes de ejecutar el verbo. Se
comprobó que cada muestra moviera el cursor esperado y conservara el diff.

Es una medición de las llamadas bloqueantes de la CLI en Windows, **no de un clic
real en IntelliJ**. No incluye render, explicación ni `GitRepository.update()`.
Las dos instancias de IntelliJ seguían abiertas y había pruebas en Docker en
paralelo; cuatro muestras no caracterizan todos los repositorios ni una máquina
en reposo. La variación del refresco posterior también influye en el total.
La mejora esperada se concentra en IntelliJ y las mutaciones de Visual Studio
que hacían una prelectura, no en clientes que ya la omitían.

Evidencia local: `ide-context-guard/benchmark.py` y `windows-benchmark.json`
en los artefactos del chat. El fixture es independiente del sandbox del usuario.

### Validación funcional

- CLI: coincidencia y rechazo sin efectos al cambiar rama, HEAD, cursor, sesión
  de Comments o gitdir; ediciones de código permitidas; metadata de otras
  reviews; SHA-1/SHA-256; tokens inválidos y compatibilidad de reportes.
- IntelliJ: 382 tests, compilación y estructura del ZIP 0.5.2.
- Visual Studio: 424 tests de dominio, 74 de host, build VSIX 0.4.2 y verificación
  WPF con 30 fixtures.
- VS Code: 534 tests unitarios, un caso pendiente preexistente y 123 casos de
  integración con el host real de la extensión.
- TUI: formato, `go vet` y tests de todos los paquetes.
- Contrato de producto: 52 tests y comprobación de los cuatro clientes; ShellCheck.

Las instancias de IntelliJ abiertas durante el trabajo conservan el plugin
0.5.1 cargado. El ZIP 0.5.2 está generado para las pruebas locales; requiere
recargar el plugin mediante el flujo de desarrollo o instalar el ZIP y reiniciar.
No se publicaron versiones en las tiendas.
