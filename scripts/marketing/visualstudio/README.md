# Captura de Visual Studio

La pieza usa Visual Studio 2026 Insiders, el VSIX compilado desde este checkout
y la CLI real. El proyecto C# y el perfil `/rootsuffix Marketing` son exclusivos
de la grabación. Las acciones de inicio, lectura y cierre se accionan en el panel
real; la corrección se escribe y guarda en el editor.

Los tres tests xUnit se ejecutan en Docker con .NET 8, según la regla del repo.
El archivo `bin/Test results.txt` contiene stdout sin modificar y se abre en el
IDE para mostrar el resultado. No representa el Test Explorer ni una ejecución
iniciada desde ese control.

## Preparación y grabación

1. Ejecutar `prepare.cjs` con Node y git en el contenedor de marketing, pasando
   un directorio nuevo montado desde `demo/marketing/visualstudio/project`.
   Genera `RateLimit.sln`, la rama autora `rate-limit` y su walkthrough.
2. Compilar el VSIX según `visualstudio-extension/CONTRIBUTING.md` e instalarlo
   únicamente en el perfil de captura. Lanzar el IDE con ese perfil y el proyecto;
   añadir `bin/` de este checkout al PATH del proceso para que encuentre la CLI.
3. Mostrar **View → Other Windows → git review**, abrir `src/RateLimiter.cs`,
   ampliar el editor al 160 % y desactivar CodeLens en el perfil de captura.
4. Ajustar la ventana a 1446 × 924 y el panel derecho a unos 480 px. El recorte
   `1440:798:3:66` excluye los menús y las barras de estado localizados del host;
   conserva el editor y el panel originales, en inglés. Revisarlo si cambia el
   tamaño o la escala de pantalla. Mantener la ventana visible al grabar.
5. Ejecutar `record.ps1 -WindowTitle '<título observado>' -Ffmpeg '<ffmpeg.exe>'`
   desde una terminal con stdin interactivo. Detener con `q`; el límite de
   seguridad es 900 segundos, configurable con `-DurationSeconds`. La grabación
   inicia un nuevo `chapters.json`. No reutilizar una carpeta con una toma que se
   quiera conservar.
6. Usar `mark.ps1 <nombre>` al registrar `before`, `reading`, `reason`, `edit`,
   `tests`, `finish` y `result`. El asistente usa la rama actual, **Offline** y
   **Walkthrough (recommended)**. Abrir la política, avanzar al archivo clave y
   cambiar únicamente `>` por `>=` en la condición.
7. Ejecutar `dotnet test --logger 'console;verbosity=normal'` dentro del contenedor
   .NET 8 con el proyecto montado. Comprobar exit 0, guardar stdout en
   `bin/Test results.txt` y abrir ese archivo en el editor. Usar la misma caché
   NuGet del contenedor en restore y test; un `obj/` generado por Windows no
   sustituye el restore dentro de Linux.
8. Volver al código y elegir **Finish → A separate branch** en el panel.

## Evidencia y composición

Ejecutar `check-before.sh` en la imagen .NET SDK con `/fixture` (proyecto, sólo
lectura), `/output` (carpeta de captura) y el script montados. Clona la rama
autora en un directorio temporal, exige exactamente un test fallido y dos
aprobados, y conserva la salida en `before-tests.txt`. La copia corregida no
se modifica.

Ejecutar `verify.cjs` en la imagen de marketing con los mismos mounts: exige
la rama `review-fixes/rate-limit`, sólo `src/RateLimiter.cs` staged, ninguna
edición pendiente, la rama autora intacta y los tres tests aprobados. Escribe
`verification.json`.

Al terminar, elegir los cinco recortes reales en `cuts.json`, como listas
`[inicio_en_segundos, duración_original, duración_final]`. Sus duraciones
finales deben ser `6, 6, 5, 5, 7`; la intro y el cierre completan 40 segundos.
Quitar esperas y material ajeno al IDE. Extraer `reason.png` de la toma real
con FFmpeg y revisar todos los cortes antes de ejecutar:

```sh
sh scripts/marketing/run.sh --render visualstudio
sh scripts/marketing/run.sh --verify
```

Los GIF se extraen de las escenas ya montadas para incluir la edición y los
resultados aunque haya pausas largas entre las interacciones. La música es la
partitura original compartida. Sólo los archivos de `docs/media/` se publican;
la toma, los capítulos, la evidencia y los frames de inspección quedan ignorados.
