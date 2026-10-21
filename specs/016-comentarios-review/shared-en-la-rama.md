# Shared pertenece a la rama

Decisión del 2026-10-19: fuera de una review, Comments va en una sección del
pie entre Walkthrough y Compare y lee Shared desde `.review/comments.md` de la
rama actual. Agregar comentarios requiere una review; Compare conserva sólo Local.
Si también hay una preparación guardada, el panel principal muestra el Shared
del repositorio. Continue vuelve a la preparación guardada sin modificarla.

Al iniciar una review se prepara una copia privada del Shared propio del PR.
Los documentos heredados de la base integrada no se incorporan a la nueva
sesión. Local y la preparación de Shared siguen siendo documentos independientes.

Finish entrega el documento completo, incluidos los borrados individuales, y
lo stagea junto con las correcciones. Sólo después de la entrega y publicación
correctas elimina la preparación editable de Shared. Los resultados privados
conservan Local y metadata de recuperación, sin otra copia editable de Shared.
Una entrega fallida conserva su preparación para reintentar.

Undo revierte la entrega y devuelve el Shared actual a la preparación, sin
resucitar comentarios borrados. Cancel descarta la pasada completa y respeta
el documento que ya traía la rama. Save/Continue conserva la preparación y su
límite original de descarte; Finish/Undo tampoco redefine ese límite.

Verificación: ramas descargadas sin estado privado, documentos heredados,
borrados parciales y del último comentario, ciclos Finish/Undo/Finish y
Finish/Undo/Cancel, pausas y reanudaciones, fallos de entrega y ediciones
concurrentes. El contrato y sus cuatro clientes verifican el orden del pie.

## Verificación realizada el 2026-10-20

- Suite general Bats: 1.420 casos. Cinco omisiones previstas por el entorno
  (npm, permisos efectivos de root, PTY y PATH de Windows). Cuatro comprobaciones de empaquetado necesitaron
  repetir `tests/packaging.bats` con el índice Git original en la copia de
  prueba; los doce casos de ese archivo pasan, salvo el smoke npm omitido.
- Los siete casos de `tests/comments-repository-shared.bats` pasan, incluidos
  los dos añadidos después de la suite general. También pasan las consultas
  Prepare y los reintentos de Finish relacionados.
- VS Code: compilación TypeScript, 512 pruebas unitarias aprobadas, una
  pendiente ya declarada y 20 integraciones de comentarios aprobadas.
- JetBrains: `./gradlew test`, 368 pruebas aprobadas.
- Visual Studio: 411 pruebas de dominio y 68 de host aprobadas en Linux;
  `build-vsix.ps1` genera el VSIX net472 en Windows.
- TUI: `gofmt -l .` vacío, `go vet ./...` y `go test ./...` aprobados. Los
  únicos golden modificados son las seis variantes de la pantalla de
  comentarios pendientes, por el cambio de posición y de foco inicial.
- Contrato: checker de los cuatro clientes aprobado y 43 pruebas del
  verificador aprobadas. Shellcheck y `git diff --check` sin errores.
