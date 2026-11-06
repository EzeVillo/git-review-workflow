# Reparto de CI Windows por duración

## Corrida inicial

Fuente: [CI 41948706723](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723), commit `f211777`, iniciada el 5 de noviembre de 2026 a las 01:28 UTC. Terminó con **23/23 jobs correctos**.

Los tiempos son ejecución del job (`completedAt - startedAt`), incluidos preparación y cierre. No incluyen espera en la cola del runner.

| Job | Duración |
|---|---:|
| [test (windows-latest, 2, 4)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222906) | 134 min 23 s |
| [test (windows-latest, 1, 4)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222829) | 86 min 11 s |
| [test (windows-latest, 3, 4)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987223037) | 84 min 26 s |
| [test (windows-latest, 4, 4)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987223069) | 83 min 42 s |
| [vscode-extension (windows-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222855) | 59 min 39 s |
| [test (macos-latest, 1, 1)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222672) | 42 min 03 s |
| [test (ubuntu-latest, 1, 1)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222942) | 18 min 04 s |
| [vscode-extension (macos-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222875) | 11 min 42 s |
| [jetbrains-plugin (windows-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222943) | 6 min 28 s |
| [visualstudio-extension (windows-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987223028) | 5 min 39 s |
| [tui (windows-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222971) | 4 min 14 s |
| [jetbrains-plugin (ubuntu-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222695) | 3 min 54 s |
| [vscode-extension (ubuntu-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222684) | 3 min 25 s |
| [jetbrains-plugin (macos-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222949) | 2 min 29 s |
| [lint (macos-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222737) | 2 min 12 s |
| [tui (macos-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222786) | 2 min 02 s |
| [tui (ubuntu-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222712) | 1 min 58 s |
| [visualstudio-extension (macos-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222862) | 1 min 40 s |
| [lint (ubuntu-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222739) | 1 min 38 s |
| [lint (windows-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222435) | 1 min 31 s |
| [visualstudio-extension (ubuntu-latest)](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222995) | 0 min 36 s |
| [client-product-surface](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222923) | 0 min 12 s |
| [landing](https://github.com/EzeVillo/git-review-workflow/actions/runs/41948706723/job/126987222838) | 0 min 06 s |

La referencia es `test (macos-latest, 1, 1)`: **42 min 03 s**. Solamente los cuatro grupos Windows de Bats y la integración Windows de VS Code superan ese valor. IntelliJ, Visual Studio, TUI y lint Windows ya cumplen.

También se revisaron los workflows de publicación: sólo Visual Studio y TUI
tienen jobs Windows. Sus últimas corridas exitosas disponibles tardaron
[2 min 21 s](https://github.com/EzeVillo/git-review-workflow/actions/runs/34526605449)
y [1 min 54 s](https://github.com/EzeVillo/git-review-workflow/actions/runs/34487245563),
respectivamente. Son mediciones históricas de otros commits; no justifican
dividir esos jobs de empaquetado. Los demás workflows de publicación ejecutan
únicamente runners Linux.

## Medición y reparto

Se descargaron los logs originales por la API de jobs. Para Bats se contrastaron los nombres y ordinales de los 1.507 casos con sus archivos; el costo sin temporizar del paso se repartió proporcionalmente por cantidad de casos. Para VS Code se midieron los intervalos de inicio y fin de las 18 suites completas, incluidos before/after y limpieza, que cubren 121 tests. Usar sólo los milisegundos impresos por Mocha habría ocultado el costo de las fixtures.

El perfil versionado `.github/ci/windows-timings.json` conserva esos pesos y la corrida de procedencia. `scripts/ci-shards.cjs` ordena los archivos del más costoso al menos costoso y asigna cada uno al grupo menos cargado. Conserva archivos completos para respetar los hooks; los archivos nuevos se incluyen con cinco minutos provisionales.

| Suite Windows | Antes | Grupos nuevos | Estimación por job, con preparación |
|---|---:|---:|---:|
| Bats | 4 grupos, 83–134 min | 12 | 33,68–33,81 min |
| VS Code | 1 grupo, 59,65 min | 3 | 18,54–24,27 min |

El presupuesto de planificación deja un 15 % de margen respecto de la referencia histórica. Los dos minutos fijos de Bats y el minuto de VS Code son estimaciones de preparación, no mediciones adicionales de las suites. Se conserva el smoke independiente de comments status una vez en Windows y en ambos runners Unix.

## Control permanente

Cada corrida espera que terminen todos sus jobs y compara **cada job Windows** con el mayor job Linux/macOS de esa misma corrida. El control exige que todos hayan pasado; una suite fallida o interrumpida no cuenta como una mejora. Los reruns parciales conservan los resultados exitosos anteriores y toman el intento más reciente por nombre. El propio job de reporte se excluye de la referencia.

Los gates comprueban que no falten ni se dupliquen archivos o índices de grupos, que las estimaciones quepan en el presupuesto y que el reporte espere a todos los jobs. No hay cancelación anticipada por presupuesto. La disponibilidad de runners puede agregar cola y no forma parte de esta comparación.

## Verificación

Validación local en contenedor:

- Los doce grupos Bats ejecutaron la selección exacta del workflow: 1.507 casos
  contabilizados, sin fallos, con las omisiones propias de plataforma.
- Las tres integraciones de VS Code pasaron con 26, 44 y 51 tests: 121 en total,
  distribuidos en 1, 8 y 9 archivos sin solapamiento. Compilación, TypeScript y
  532 tests unitarios también correctos; una omisión unitaria preexistente.
- Los 14 tests del reparto y presupuesto pasaron con Node 20. El control nuevo
  rechazó los cinco jobs lentos al recibir los datos reales de la corrida inicial.
- Actionlint, los 52 tests del contrato de producto, su gate y el de logos,
  además de `git diff --check`, correctos.

El tiempo Windows nuevo se verificará con la corrida nativa del commit que
introduce este reparto; las cifras de planificación de arriba son estimaciones.
