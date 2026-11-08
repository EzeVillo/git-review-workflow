# Auxiliar nativo para metadata: experimento aislado

Este directorio permite evaluar un auxiliar pequeño sin cambiar `bin/`, los
clientes, el instalador ni la CLI instalada. No es una nueva dependencia del
producto. La decisión y las mediciones están en
[`specs/rendimiento/2026-11-08-costo-fijo.md`](../../specs/rendimiento/2026-11-08-costo-fijo.md).

## Qué se compara

`make_overlay.py` copia la CLI a un directorio externo y modifica únicamente esa
copia. No acepta un destino dentro del checkout ni sobre una CLI existente.

1. Git sigue leyendo todas las fuentes de config. El subcomando `encode`
   sustituye `od | awk` por un codificador de los mismos bytes, sin cambiar el
   token de validación. Las relecturas siguen ocurriendo en los mismos puntos.
2. Save publica los metadatos de la rama guardada en un lote. La transferencia
   de custodia publica sus tres claves en otro lote, después de sus revalidaciones.
3. Los objetos, refs, índice, checkout, manifest de comentarios y borradores
   siguen usando el código y los comandos originales. Save sigue devolviendo
   el informe final completo. No se cambian los cuatro clientes.

El escritor usa `git_config_lock` y `git_transaction_commit` de libgit2 sobre
el archivo que selecciona Git, con fsync habilitado y un flush explícito del
archivo resultante. Esto no certifica durabilidad equivalente ante un corte de
energía ni hace atómicos a la vez config, refs, Markdown y working tree.

## Compatibilidad y fallos

El auxiliar no intenta reemplazar al parser de Git. Las lecturas de configuración
siguen pasando por Git. Las escrituras con valores de control, claves presentes
en includes o un destino que sea symlink/no regular devuelven **78 antes de
publicar**. Sólo ese código habilita ejecutar el lote mediante los comandos
Git originales. Un lock ajeno, error de commit o fallo posterior a la publicación
son errores finales: nunca se reintentan como si no hubieran escrito.

El plan NUL-delimitado se recibe completo y se valida antes de abrir el archivo.
Las operaciones elegibles se revisan bajo lock antes de encolar la primera
escritura. No se evalúa texto como shell. Los duplicados de claves de destino
se rechazan sin publicar cambios parciales. El encoding de stdout es binario
también en Windows; los guards deben coincidir byte por byte con la CLI anterior.

Se descartó usar `git_config_set_multivar`: el comportamiento de escape de sus
valores difiere del setter simple en la versión probada. Tampoco se intenta
leer un supuesto archivo candidato con la API de lectura durante la transacción:
esa API todavía ve el snapshot anterior. Son motivos para conservar una ruta
acotada y una vuelta explícita a Git, no para agregar escapes propios.

## Compilar en Windows

Requiere MSVC x64 y Python 3.12 o posterior para el benchmark. La prueba usó
headers de **libgit2 1.8.6** y la DLL Win64 del paquete oficial
[LibGit2Sharp.NativeBinaries 2.0.324](https://www.nuget.org/packages/LibGit2Sharp.NativeBinaries/2.0.324).
El nombre de esa DLL es `git2-5853918.dll`. No copiar DLLs al PATH del usuario.
Los headers se obtienen del tag oficial
[`v1.8.6`](https://github.com/libgit2/libgit2/tree/v1.8.6).

SHA-256 de la DLL usada:
`45d0a0959f775776a499aa45119499aae8c512553f0c414b1ab43b6c9df73935`.

Desde la raíz del repositorio, con dependencias previamente extraídas fuera
del checkout:

```powershell
$taskDir = Join-Path $env:TEMP ('gr-meta-' + [guid]::NewGuid())
./experiments/metadata-helper/build-windows.ps1 `
  -Headers C:/ruta/libgit2-1.8.6/include `
  -Library C:/ruta/runtimes/win-x64/native/git2-5853918.dll `
  -Output "$taskDir/native"
python experiments/metadata-helper/make_overlay.py . "$taskDir/candidate"
$env:META_TEST_HELPER = "$taskDir/native/git-review-meta.exe"
python experiments/metadata-helper/test_helper.py
```

El script genera import library y ejecutable en el destino nuevo; no instala
nada. `GIT_REVIEW_META_HELPER` se usa sólo en la copia experimental. No es una
variable pública ni una superficie compatible de la CLI del producto.

## Compilar y verificar en Docker

La imagen de experimentación parte de `git-review-tests`; construir primero
esa imagen con el runner habitual si todavía no existe. Su Dockerfile agrega
compilador C, libgit2-dev y Python. Se debe registrar la versión de libgit2 del
contenedor: no necesariamente coincide con la DLL de Windows.

```sh
docker build -t git-review-native-meta-experiment -f experiments/metadata-helper/Dockerfile .
```

En el contenedor, con una copia del checkout en `/repo` y `/out` escribible:

```sh
cc -std=c99 -D_POSIX_C_SOURCE=200809L -O2 -Wall -Wextra -Werror -pedantic \
  /repo/experiments/metadata-helper/metadata.c -o /out/git-review-meta \
  $(pkg-config --cflags --libs libgit2)
export META_TEST_HELPER=/out/git-review-meta
python3 /repo/experiments/metadata-helper/test_helper.py
mkdir /baseline
cp -a /repo/bin /baseline/
python3 /repo/experiments/metadata-helper/make_overlay.py /repo /candidate
cp -a /candidate/bin/. /repo/bin/
export GIT_REVIEW_META_HELPER=/out/git-review-meta
export META_BASELINE_BIN=/baseline/bin META_OVERLAY_BIN=/repo/bin
python3 /repo/experiments/metadata-helper/test_integration.py
cd /repo
bats tests/config-snapshot.bats tests/save-state.bats tests/close-performance.bats \
  tests/comments-transfer-race.bats tests/comments-paths.bats tests/state-guard.bats
```

Los tests de integración comprueban Save/Continue en whole, step, walk y compare;
misma respuesta final, guard compatible, edición privada, custodia y prosa
exacta; delegación por includes o bytes especiales y ausencia de reintento tras
un error inyectado después del commit. Los tests del auxiliar también cubren
mensajes incompletos, duplicados, rollback, lock ajeno y paths Unicode.

## Medir Save completo

Con las suites detenidas, ejecutar en Windows:

```powershell
python experiments/metadata-helper/benchmark.py . "$taskDir/candidate" `
  "$taskDir/native/git-review-meta.exe" "$taskDir/mediciones"
```

El script archiva `HEAD:bin` como baseline, usa un repositorio descartable,
hace dos calentamientos y cuatro muestras por variante en pares alternados.
Mide `comments paths --porcelain` y Save con guard e informe completo. Conserva
trazas Trace2 separadas, hashes, muestras, medianas y comprobaciones de estado.
Setup, captura del guard, Continue y asserts quedan fuera del intervalo. No
mide buffers del IDE, render del panel ni PRs grandes. El directorio de salida
debe ser nuevo y las dos copias de CLI deben conservarse durante el ensayo.

Que la biblioteca escriba quince claves en milisegundos no significa que Save
tarde milisegundos. Se adopta sólo si el resultado integral y la compatibilidad
justifican distribuir y mantener el binario en las plataformas del producto.
