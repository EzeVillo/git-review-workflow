# Coordinación de watchers y lecturas de cierre

## Alcance autorizado

Ezequiel pidió comenzar con los dos próximos cortes de rendimiento: coordinar
las señales de los watchers con las operaciones y reducir procesos de metadata
en Save/Cancel. Se implementó sobre los cambios locales anteriores y se probó
sin commit, push, publicación ni reemplazo de los plugins del usuario. Después
de ver los resultados autorizó commitear; no pidió push ni publicación.

## Diseño

Los tres IDE guardan las señales mientras una mutación está ocupada. La lectura
principal posterior consume sólo las recibidas antes de empezar. Una señal que
llega después permanece pendiente y solicita otra lectura al liberar la
mutación. Las lecturas observadas no corren en paralelo entre sí; tampoco se
espera Comments para liberar una operación. La TUI ya difiere señales de
archivos con su lock y ventana posterior; se conserva su contrato existente.

Save y Cancel cargan metadata de rama por lotes. Cuando reciben un contexto
esperado lo validan dentro de la misma operación, antes de escribir. La custodia
de Comments sigue consultando tanto el gitdir como una snapshot nueva de config
en cada preflight: antes y después del lock, y antes de transferir o descartar.
La copia de claves estables de Save usa el lote de su fase; las escrituras
siguen pasando por Git. No se edita `.git/config` directamente ni se reutiliza
una snapshot entre procesos, operaciones o límites de custodia.

## Criterios de aceptación

- Señales propias durante Save no lanzan status/why/Comments en paralelo con
  el verbo; los cambios externos posteriores a la lectura final no se pierden.
- Las ráfagas y trabajos ya encolados se reúnen, incluidos cierres fallidos
  que no llegan a consultar estado principal.
- Save/Continue conserva cursor, código, borrador y Local/Shared; Cancel
  restaura la rama y descarta sólo su pasada.
- Un propietario o destino que cambia entre preflights sigue rechazándose;
  un fallo de snapshot nunca degrada a una custodia sin comprobar.
- Comparación de llamadas de CLI en Windows contra `baseline.tar` de CLI 0.10.4,
  y prueba del plugin nuevo en la instancia aislada ya autorizada.

## Versiones locales

CLI 0.10.5, IntelliJ/VS Code 0.5.5 y Visual Studio 0.4.5. La TUI conserva 0.2.4:
su coordinación ya existe y recibe el ahorro del backend compartido. Los mínimos
de CLI siguen siendo compatibles; no se agregan flags ni registros públicos.

## Verificación automatizada

- CLI: 1537 casos Bats en Docker, con los skips habituales del entorno. Los
  siete casos nuevos comprueban efectos sobre Git, preservación de Local,
  relecturas de propietario y destino y fallos de snapshot antes de efectos.
- Bash 3.2: sintaxis de los scripts y 25 casos dirigidos. Windows nativo:
  tres casos de cierre y custodia, todos con código 0.
- IntelliJ: 395 tests, dominio sin IntelliJ y verificación de proyecto,
  estructura y ZIP. Se comprobó la versión 0.5.5 en el plugin.xml empaquetado.
- VS Code: 550 tests unitarios y un pendiente preexistente; 123 pruebas de
  integración con el extension host real.
- Visual Studio: 424 tests Domain, 87 Host, rebuild nativo del VSIX net472
  y 30 fixtures WPF. El manifiesto interno del VSIX indica 0.4.5.
- TUI: formato, vet y todas las pruebas Go, incluidos los golden.
- ShellCheck y 62 pruebas de contratos y reparto de CI.

Los resultados no equivalen a una ejecución de CI remota: no se hizo push.
Los tests y builds que podían correr en contenedor se ejecutaron allí; las
comprobaciones de Windows, MSBuild y WPF se realizaron nativamente.

## Medición de la CLI en Windows

Se comparó el snapshot local anterior (CLI 0.10.4) con 0.10.5, sobre el mismo
repositorio sintético para cada operación. Después de dos calentamientos se
alternaron ocho muestras: cuatro por versión. Trace2 estuvo habilitado en
ambas. La preparación, consulta del guard, Continue y aserciones quedan fuera
del intervalo medido. No se ejecutaron las suites ni se arrancó el IDE de
prueba durante las muestras medidas.

| Operación con guard | Mediana anterior | Mediana nueva | Reducción | Procesos Git |
| --- | ---: | ---: | ---: | ---: |
| Save con Local | 11,56 s | 7,69 s | 33,5 % | 117 → 57 |
| Cancel sin buffers | 3,36 s | 2,64 s | 21,4 % | 30 → 18 |

Se comprobó después de cada cierre la rama main limpia y la ausencia de la
rama activa. Save/Continue conservó bytes de Local, sesión, diff y cursor;
Cancel restauró los bytes de base. Son tiempos de la CLI, no del clic del
IDE. Trace2 agrega overhead y cuatro muestras no caracterizan todos los
repositorios; los procesos Git tampoco cuentan los comandos externos de sh.

Script, snapshot anterior, muestras, trazas y resumen:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/closing-performance/`.

## Prueba real de IntelliJ 0.5.5

Se probó el ZIP en la instancia aislada previamente autorizada, con el mismo
fixture sintético y CLI 0.10.5. No se reemplazaron ni reiniciaron las dos
instancias del usuario. El log confirma la carga del plugin 0.5.5.

Save recibió un Local modificado en el editor y todavía ausente en disco.
Conservó el inventario previo de custodia, guardó el marcador y preservó los
bytes anteriores, incluso la ausencia de salto final. El panel mostró la
review pausada; se verificaron main limpio y la misma sesión propietaria.
Durante el verbo no hubo ninguna otra invocación de la CLI: el refresco del
watcher que competía en 0.5.4 desapareció. El refresco principal ocurrió después.

Continue recuperó la review y Cancel con buffers limpios omitió el inventario
`--all`. El panel volvió a sin review. Se comprobaron main limpio, ausencia de
la rama activa y bytes idénticos a los blobs de base, sin normalizar CRLF.

| Acción real | CLI | Hasta liberar el lock |
| --- | ---: | ---: |
| Save con Local modificado | 9,990 s | 14,544 s |
| Cancel con buffers limpios | 3,406 s | 6,061 s |

**Estas dos muestras no demuestran una mejora total del IDE.** En la prueba
anterior de 0.5.4 se observaron 13,519 s para Save y 4,773 s para Cancel, también
una sola muestra por acción. No son pares controlados y no permiten atribuir
la diferencia al cambio. La reducción de procesos y tiempo se comprobó en la
comparación alternada de la CLI; en la UI se comprobó el comportamiento, la
conservación de datos y la ausencia de consultas competidoras. Save sigue
siendo lento y ese problema no se declara resuelto.

La duración del lock excluye el tiempo de decisión en el modal y no mide el
paint del EDT. Comments terminó por separado. La instancia propia se cerró al
terminar; los logs y aserciones están en `ui-summary.json`, `ui-plugin-calls.log`
y los archivos `ui-055-*` del fixture.

ZIP local: `jetbrains-plugin/build/distributions/git-review-workflow-0.5.5.zip`.
SHA-256: `286A48C6C872AF4236BA18F388A71EF38E0BE81CF6F11E1F85ED03CBDF22A964`.

## Integración local y siguiente paso

Por autorización posterior de Ezequiel, el código quedó commiteado en main:

- `4a98ddd`: respuesta de navegación y lecturas de cierre en la CLI.
- `8ba00fc`: reutilización de respuestas, detalles asíncronos, buffers y watchers
  en los clientes.

Los contratos, decisiones y mediciones se conservan en un commit de
documentación posterior. No se hizo push ni se crearon tags. Los documentos
de pruebas locales y auditorías ajenos a este cambio quedan fuera.

El siguiente trabajo debe partir de la latencia restante:

1. Desglosar Save en fases internas, incluyendo escrituras de metadata y
   custodia de Comments. En el caso real, el verbo ocupa 9,990 de 14,544 s;
   mejorar sólo el refresco no alcanza. Trace2 cuenta Git, pero se necesitan
   también tiempos por fase para distinguir el costo de los comandos de sh.
2. Optimizar la fase dominante en la CLI compartida y repetir una comparación
   alternada con los mismos datos. Mantener las comprobaciones frescas de
   propietario, destino, índice y recuperación.
3. Evaluar una respuesta de cierre con el estado final para reunir las
   consultas posteriores de status/list/config. En Save costaron cerca de
   2,2 s en la prueba; ese sería un ahorro adicional y debe medirse separado.

La aceptación siguiente requiere una comparación pareada del tiempo total en
IntelliJ, con buffers limpios y modificados. La reducción de procesos por sí
sola no reemplaza esa medición.
