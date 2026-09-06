# Demo de las extensiones — Implementation Plan

**Goal:** Producir una demo comercial de VS Code de 40 segundos en inglés, con música instrumental original, tres GIFs breves y un reproductor en la landing.

**Architecture:** Capturar VS Code real con la extensión del checkout en un contenedor y un repositorio de ejemplo descartable. Ejecutar las acciones de la extensión y comprobar el estado de git. Editar las capturas con FFmpeg y conservar el guion y los generadores para repetir la producción.

**Tech Stack:** Docker, VS Code Extension Development Host, Node.js, Xvfb, FFmpeg, HTML y CSS existentes.

## Global Constraints

- Trabajar sobre `main`, sin push ni publicación.
- No modificar la sesión del IDE ni los repositorios personales del usuario.
- No presentar previews estáticos como interacciones reales.
- Mantener los dos README y la copy bilingüe de la landing sincronizados.
- Usar el logo existente y la paleta de la landing: tinta #0B0E14, texto #DCE2ED, verde #4CC46B y ámbar #E6B455.
- Textos integrados en inglés y música instrumental original, sin locución; lectura comprensible también sin sonido.
- El alcance inicial aprobado es VS Code; el sistema de producción debe documentar cómo extenderlo a los otros IDEs sin atribuirles capturas de VS Code.

## Guion aprobado y dirección visual

Un PR con un error de límite en un control de intentos. El revisor sigue el orden de lectura, entiende la condición, cambia una comparación, ejecuta las pruebas y extrae su corrección. Tipografía de títulos sans, código monoespaciado; capturas grandes y encuadres que mantienen visible el panel. El acento verde acompaña el resultado y el ámbar señala el motivo de lectura. Cierre con el logo y la invitación a revisar en el IDE habitual.

## Tasks

- [x] Preparar `scripts/marketing/`: entorno reproducible, repositorio de ejemplo y controlador de captura. Verificar que el test del ejemplo falla antes de la corrección y pasa después, y que la rama de correcciones contiene solamente la edición del revisor.
- [x] Producir `docs/media/`: un MP4 en inglés con música, un póster y tres GIFs. Revisar capturas y fotogramas finales; comprobar duración, dimensiones, decodificación y peso con FFmpeg/ffprobe.
- [x] Integrar el video en `docs/index.html`, con controles nativos, carga diferida y sin autoplay. Conservar el enlace a la demo de consola. Agregar muestras a ambos README y al README de VS Code con enlaces absolutos en el cliente.
- [x] Documentar regeneración en `CONTRIBUTING.md`; verificar contrato de clientes y assets existentes, sintaxis, enlaces locales y diseño responsive de la landing.

La autorización del usuario permite ejecutar el plan completo sin nuevos checkpoints de aprobación. No se crean commits automáticos.

## Verificación

- Grabación real: tres tests en verde; solamente `src/rate-limit.js` staged en `review-fixes/rate-limit`, con la comparación corregida.
- Video H.264 1920×1080 de 40 segundos con pista AAC estéreo de 48 kHz, reproducido en Chromium.
- Tres GIFs de 960 px y 6/9/8 segundos; decodificación completa sin errores.
- Landing comprobada a 390, 768 y 1440 px, sin overflow horizontal ni errores de JavaScript; ambas lenguas muestran el mismo video y póster en inglés.
- Contratos de clientes y logo, comprobación de sintaxis de scripts y ShellCheck en verde.

## Ajuste solicitado después de la revisión

El usuario aprobó el montaje y pidió música de fondo comercial y solamente la versión en inglés. `music.mjs` compone una pista original a 120 BPM con percusión, bajo, acordes y melodía sintetizados, sin samples externos. La resolución acompaña el logo a los 34 segundos y la música se desvanece al terminar. El montaje normaliza la mezcla a aproximadamente −18 LUFS; el verificador exige audio AAC estéreo, 40 segundos y pico verdadero por debajo de −1 dBTP. Se retiran los dos assets españoles y las referencias públicas a ellos. La landing y los README conservan sus idiomas respectivos.
