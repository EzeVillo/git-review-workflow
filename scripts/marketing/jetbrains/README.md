# Captura de JetBrains

La demo usa IntelliJ IDEA 2026.1 real en Linux, con el plugin compilado desde este checkout, una copia de la CLI y un repositorio descartable. `CaptureActivity.kt` se agrega únicamente a la copia del plugin del contenedor: no forma parte del artefacto publicable.

El harness invoca `MutationActions` para iniciar y terminar la review, `PanelActionDispatcher` para navegar, las APIs del editor para guardar la corrección y la consola **Run** para ejecutar Node. El panel consulta la CLI real. No se reemplazan estados, controles, salida de tests ni imágenes del IDE.

## Preparación

El contenedor de captura necesita las dependencias de `scripts/marketing/Dockerfile`, Openbox y un JDK 21 en `/opt/openjdk`. Montar el checkout en `/src` y la caché Gradle en `/root/.gradle`. La captura usada en esta entrega vive en `grv-film-jb`.

1. Copiar `jetbrains-plugin/` a `/work/jetbrains-plugin`, excluyendo `build/`, `.gradle/` y `.intellijPlatform/`. Copiar `bin/` y `contracts/` a `/work/` y conservar los permisos ejecutables de la CLI. Normalizar los CRLF de los scripts si el checkout viene de Windows.
2. Copiar `CaptureActivity.kt` a `/work/jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/marketing/`.
3. Ejecutar `node /src/scripts/marketing/jetbrains/prepare.cjs`. Registra la actividad en el descriptor de la copia y genera `/tmp/fixture.cjs` a partir del mismo fixture de VS Code. Sólo parte la firma larga de JavaScript en varias líneas para que se lea completa.
4. Ejecutar `MARKETING_OUT=/src/demo/marketing/jetbrains node /tmp/fixture.cjs`. Crea `/film/rate-limit`, exige que el test de límite falle y escribe `before-tests.txt`. El directorio debe estar libre antes de esta primera ejecución.
5. Desde `/work/jetbrains-plugin`, ejecutar `JAVA_HOME=/opt/openjdk PATH=/opt/openjdk/bin:$PATH sh gradlew buildPlugin -x buildSearchableOptions --console=plain`. La generación de índices de búsqueda no hace falta para la captura.
6. Ejecutar `sh /src/scripts/marketing/jetbrains/launch.sh` y `DISPLAY=:99 openbox` en el contenedor. Completar el arranque inicial del IDE, cerrar avisos de bienvenida y maximizar su ventana a 1440 × 900. No iniciar una prueba de pago. La actividad deja `/tmp/jb-ready` cuando el proyecto está listo.

Si se regenera el repositorio entre tomas, cerrar el IDE y usar una ruta nueva para `idea.system.path`: su caché VFS conserva los identificadores del repositorio anterior. El archivo de propiedades y el perfil son exclusivos de `/film`; no se toca la configuración del usuario.

## Grabación

Con la rama `rate-limit` limpia, el panel resuelto y el IDE maximizado:

```sh
PATH=/work/bin:$PATH node /src/scripts/marketing/jetbrains/capture.cjs
```

El script graba Xvfb a 30 fps y produce `raw.mp4`, `chapters.json`, siete PNG y `verification.json` bajo `demo/marketing/jetbrains/`. El cambio verificado es exclusivamente `attempts > limit` → `attempts >= limit`; los tres tests pasan y `finish` deja la corrección staged en `review-fixes/rate-limit`. La consola del IDE usa el reporter `spec` para que se vean los nombres completos.

Los controles por coordenadas sólo ajustan el alto de la consola y eligen el visor unificado del diff nativo. Dependen de la geometría 1440 × 900 y del tema/configuración capturados. Revisar visualmente `reason.png`, `tests.png`, `finish.png` y `result.png` antes de componer.

La composición final y la música se resuelven con el compositor común. El panel de JetBrains está a la derecha: conservar todo el ancho en los recortes de lectura y edición.
