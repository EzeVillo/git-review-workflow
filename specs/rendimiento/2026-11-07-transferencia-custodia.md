# Transferencia de custodia sin reconstruir Comments

## Alcance

Ezequiel autorizó continuar con el perfil interno de Save, optimizar la fase
dominante y contrastar el resultado en Windows e IntelliJ. Se trabaja en main,
con commits después de verificar y sin push ni publicación. Los documentos de
pruebas locales y auditorías ajenos al cambio se conservan fuera.

## Perfil inicial

Sobre el snapshot de CLI 0.10.5 se agregaron marcadores de fase hechos con
`printf` sólo en una copia temporal del verbo. Dos Save de un fixture walk con
Local tardaron 8,80 y 8,71 s. La transferencia de custodia ocupó 3,66 y 3,62 s;
los preflights previos ocuparon 1,61 y 1,56 s. La copia de metadata común ocupó
0,72 y 0,75 s. El primer objetivo es, por lo tanto, la transferencia.

Una tercera ejecución con xtrace de Bash 5 para Windows identificó 31 llamadas
a `comments_field`, 37 procesos awk y 56 comandos Git. Xtrace añadió overhead:
esa muestra se usa para atribuir llamadas, no para comparar velocidad. La copia
de perfil ejecuta el verbo directamente; no mide el clic ni el dispatcher.

`comments_transfer` preparaba un manifest con el nuevo custodio y lo pasaba a
`comments_replace`, la puerta de documentos de comentarios. Esa puerta volvía
a reconstruir dos veces el estado completo de Comments y copiaba el candidato
a otro candidato antes del rename. Para esta escritura de metadata basta con
comprobar la sesión que se transfiere, los dos destinos y los bytes originales.

## Cambio

La transferencia conserva un único candidato hermano del manifest. Fija ruta,
sesión, contexto, propietario y gitdir; después de prepararlo vuelve a consultar
custodia de origen y destino y comprueba que sigue siendo la sesión fijada.
La revisión de bytes se contrasta inmediatamente antes del rename. Una sesión
distinta, aunque sea válida, no se adopta. Los conflictos y fallos de rename
conservan el manifest original y el candidato recuperable.

No se reutiliza metadata entre límites de custodia ni se modifica el guardado
de documentos de comentarios. `comments_replace` mantiene su comportamiento
para Local y Shared. No se agrega un daemon, un caché de contexto ni un flag.

Save tiene ahora seis snapshots de config en el caso con sesión: la nueva es
el preflight de publicación. Se elimina trabajo completo de lectura, no ese
control. El cambio también se aplica a Continue y llega a todos los clientes
desde la CLI compartida. La CLI pasa a 0.10.6; los clientes conservan su versión.

## Regresiones controladas

Las pruebas cambian propietario, destino, bytes o sesión después de escribir
el candidato. Los cambios de propietario, destino o sesión podían completar
Save con el código anterior; la revisión de bytes se rechazaba sin informar
el candidato. También se comprueban fallo de rename y relectura de la sesión
guardada durante Continue, preservando prosa, custodio y recuperación.

El perfil y sus scripts están en:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/save-phases/`.

## Verificación

- Suite completa: 1543 casos Bats en Docker, con los skips habituales. La primera
  copia no tenía índice Git y fallaron cuatro casos de empaquetado; se corrigió
  la preparación con un bundle de main y se repitió toda la suite con código 0.
- Bash 3.2: sintaxis de bin y 40 casos de transferencia, custodia, cierres y
  guardas. Windows nativo: tres regresiones de origen, rename y Continue.
- VS Code: 123 integraciones con el extension host real, ejecutando esta CLI.
- ShellCheck, contrato compartido y sus 62 pruebas de contrato/reparto.

El perfil nuevo sin xtrace dio 6,99 s, con 1,85 s en transferencia. La muestra
con xtrace identificó 43 comandos Git, 33 awk y un único mktemp en el verbo,
frente a 56, 37 y dos en el perfil anterior. No hubo `comments_state` dentro de
la nueva transferencia. Estos perfiles no sustituyen la comparación alternada.

## Comparación alternada de la CLI

Se midieron dos pares de calentamiento y después ocho pares alternados, cuatro
por versión, sobre el mismo fixture. Cada par mide Save con guard y Continue
por separado; consulta del guard, preparación y aserciones quedan fuera. Trace2
estuvo habilitado en ambas versiones. Las suites estaban detenidas y la tercera
instancia aislada del IDE ya había terminado de arrancar antes de medir.

| Operación | Mediana 0.10.5 | Mediana 0.10.6 | Reducción | Procesos Git |
| --- | ---: | ---: | ---: | ---: |
| Save con Local | 7,86 s | 6,14 s | 22,0 % | 57 → 44 |
| Continue | 12,79 s | 8,94 s | 30,1 % | 123 → 85 |

Se comprobó main limpio después de cada Save y la misma sesión exclusiva,
bytes de Local, diff y cursor después de Continue. Son tiempos de CLI en este
fixture, no del clic del IDE ni una garantía para otros repositorios.
`benchmark-summary.json` conserva muestras, comandos, hash del código y método.

## Comparación pareada en IntelliJ

Después del commit de código `5ea915d` se hicieron ocho Save reales en una misma
instancia caliente de IntelliJ 2026.1 con plugin 0.5.5. Un wrapper idéntico para
ambas variantes alternó CLI 0.10.5 y 0.10.6. Hubo dos muestras por versión y
condición: editor limpio y Local modificado. Continue usó siempre 0.10.6 fuera
del intervalo de Save; se esperó el fin de las lecturas secundarias antes de
comenzar la siguiente muestra. Las suites estaban detenidas.

| Save en IntelliJ | Mediana con 0.10.5 | Mediana con 0.10.6 | Reducción |
| --- | ---: | ---: | ---: |
| Editor limpio | 8,84 s | 7,27 s | 17,8 % |
| Local modificado | 10,52 s | 9,24 s | 12,2 % |

Es la duración hasta liberar el lock de la operación: excluye decidir en el
modal y no instrumenta el paint del EDT. En este fixture, la repetición sí
confirma una mejora total de la acción; dos muestras por combinación no
caracterizan otros repositorios ni garantizan ese porcentaje en toda máquina.

Los casos limpios omitieron el inventario previo y los modificados lo
conservaron. Antes de confirmar se contrastó que el marcador se veía en el
editor y todavía no estaba en disco; después se verificaron todos los bytes,
la misma sesión y main limpio. Se conservaron cursor y diff en cada Continue.
No hubo otra invocación de CLI mientras corría Save. El fixture terminó pausado
con toda la prosa de prueba y los archivos base restaurados.

Se habilitó edición sólo para el Local sintético hasta cerrar el IDE. El primer
pegado fue interceptado por la protección del editor: se deshizo y se repitió
antes de la verificación válida. La instancia emitió errores de su daemon
JetBrains al arrancar; las mediciones comenzaron una vez estabilizada, sin
errores del plugin en las acciones medidas. Se cerró sólo la instancia propia
y se restauró su ruta de CLI; las dos ventanas originales siguieron abiertas.

`ui-summary.json` conserva las ocho muestras y sus medianas; `ui-cases.json`
registra las comprobaciones, `ui-plugin-calls.log` y `ui-wrapper-calls.log`
identifican cada invocación y `ui-final-git.json` verifica el estado final.

## Evaluación del refresco posterior

El cliente todavía invoca `--version`, `status --porcelain`, `list --porcelain`
y `config --porcelain` después de Save. En las cuatro muestras con 0.10.6 esas
consultas sumaron 1,95 s de mediana. El resto del intervalo fuera del verbo y
del inventario previo fue aproximadamente 0,32 s. El inventario necesario con
Local modificado costó 1,89 s de mediana.

El siguiente corte puede reunir las lecturas principales en la CLI para
compartir metadata y resolver menos veces el mismo repositorio. No se presume
que desaparezcan los 1,95 s completos: parte corresponde a calcular el reporte
que todavía necesita el panel. Esa superficie debe conservar compatibilidad
y la autoridad de la CLI en los cuatro clientes, y medirse como un cambio
separado. Este corte no agrega una respuesta nueva de cierre.

Código commiteado en main y mediciones registradas por separado. Sin push,
tags ni publicación; los clientes conservan sus versiones y usan CLI 0.10.6.
