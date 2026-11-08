# Consulta acotada de rutas y custodia

## Alcance y diseño

Ezequiel autorizó continuar por el inventario previo al cierre. Se conserva
POSIX y se agrega `comments paths --porcelain`, disponible por la capacidad
comments-paths de status. Sólo devuelve el guard de la review mostrada,
sesión y dos rutas privadas de edición. No reconstruye identidad/captura,
consulta historia, escanea prosa ni calcula revisiones de documentos.

Los tres IDE la usan en cierres de una sesión activa cuando hay buffers
modificados o su estado es desconocido. Una confirmación positiva de todos los
documentos guardados sigue evitando cualquier consulta. La limpieza de ramas
y recuperación posterior a Finish conservan el inventario anterior. Legacy
se informa explícitamente y sólo ese sobre válido vuelve al inventario completo.
Un error, guard distinto o respuesta incompleta bloquea el cierre y refresca,
sin guardar buffers ni repetir la acción. Los clientes no construyen rutas.

Se comparte `comments_preflight_branch`. Sus cuatro campos de manifest se leen
en una sola pasada que conserva contexto vacío, tabs y backslashes, y rechaza
duplicados incluso cuando el valor es vacío. No se cachea esa lectura entre
fases: los límites de custodia de las mutaciones siguen consultando config y
gitdir de nuevo, con los mismos locks y comprobaciones de publicación.
La TUI no tiene buffers de editor y recibe el ahorro de este preflight común.

Los paths usan el encoder literal existente, una sola vez para el directorio
común. Se decodifican una sola vez en el cliente; `+` conserva su valor literal.
Se rechazan rutas no regulares y enlaces antes de emitir el sobre.
Contrato completo: `contracts/comments-paths.md`; decisión §31.

Versiones locales: CLI 0.10.8, IntelliJ/VS Code 0.5.7 y Visual Studio 0.4.7.
La TUI conserva 0.2.5. Sin cambio del mínimo CLI: la capacidad es opcional.

## Verificación

- Suite completa: 1554 casos Bats, código 0, con los skips habituales de los
  instaladores PowerShell fuera de Windows/pwsh. Luego se agregó y verificó
  un caso de encoding con porcentaje, espacios, plus y Unicode.
- 40 casos de rutas/custodia/cierres/transferencia y respuestas Save con Bash
  3.2. Se repitió el archivo de rutas (ocho casos) con el caso de encoding.
- Windows nativo: igualdad de rutas/guard en whole, step, walk y compare y
  rechazo de campos de custodia duplicados, incluido contexto vacío.
- Snapshot sin efectos: no se escriben objetos, config, índice, refs ni prosa.
  Consulta step bajo un wrapper que rechaza historia y hash de documentos.
- Las pruebas de cada IDE ejercitan query acotada, guard distinto, truncado,
  legacy explícito, decode literal y guardado exclusivo de buffers propios.
  VS Code también conserva explícitamente el inventario de housekeeping.
- 399 pruebas IntelliJ, buildPlugin y verifyPluginStructure; 557 unitarios
  VS Code con un pendiente previo y 123 integraciones reales; 424 Domain/92
  Host y VSIX nativo MSBuild/net472; Go fmt/vet/tests/golden.
- ShellCheck completo, contrato de producto y 62 comprobaciones de contrato/
  reparto (un skip habitual fuera del runner de CI). Diff y UTF-8 verificados.

Logs, snapshots y paquetes:
`C:/Users/ezevi_30ey2ks/AppData/Local/Temp/git-review-comment-paths/`.

## Comparación en Windows

Dos operaciones de calentamiento y cuatro muestras alternadas por variante,
Trace2 en ambas, mismo fixture con Local y Shared, suites detenidas. El caso
anterior usa CLI 0.10.7, `comments status --porcelain --all` y Save con guard y
`--porcelain`. El nuevo usa paths y el mismo Save con respuesta final.
Guard inicial, preparación, Continue y aserciones quedan fuera del intervalo.
No hay flush de editor ni medición del clic o paint de IntelliJ.

| Tramo | 0.10.7 | 0.10.8 |
| --- | ---: | ---: |
| Consulta previa | 2.24 s | 0.87 s |
| Save con estado final | 7.14 s | 6.70 s |
| Recorrido completo | 9.40 s | 7.59 s |
| Procesos Git del recorrido | 68 | 61 |

Reducción de consulta: 61.2 %.
Reducción del recorrido: 19.2 %
(1.81 s de mediana). Las medianas de tramos
no se suman para calcular la del total: son las muestras completas las que se
ordenan. Se contrastaron rutas exactas, informes finales byte por byte, Local y
Shared intactos, misma sesión y restauración de diff/cursor al retomar.
El fixture terminó pausado con toda su prosa.

Estos datos no son un nuevo tiempo total de IntelliJ ni garantizan el ahorro
en otros repositorios. Save sigue concentrando la mayor parte del costo. El
próximo perfil debe identificar cómo agrupar sus operaciones de Git y metadata
sin perder el origen recuperable durante el cierre. No se implementó ese corte.

Evidencia, baseline, script, muestras y SHA-256 del código medido:
`C:/Users/ezevi_30ey2ks/.codex/visualizations/2026/11/04/01a1a8ee-2d7a-7dc3-8eab-a6b1de179fec/comment-paths/`.

Código local sobre main, sin push, tags ni publicación. Las ventanas originales
no se tocaron. ZIP para prueba manual:
`jetbrains-plugin/build/distributions/git-review-workflow-0.5.7.zip`.
