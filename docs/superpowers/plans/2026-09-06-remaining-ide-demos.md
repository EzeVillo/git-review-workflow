# Demos de JetBrains y Visual Studio — Implementation Plan

**Goal:** Completar la campaña aprobada con demos reales de JetBrains y Visual Studio, solamente en inglés, y commitear los entregables de los tres clientes sobre `main`, sin push.

**Architecture:** Cada IDE se ejecuta con un perfil de grabación y un repositorio de ejemplo aislado. Los clips mantienen el recorrido aprobado: iniciar review, leer el motivo, corregir un límite, correr tres tests y extraer solamente esa corrección. El compositor comparte dirección visual y música original con VS Code, pero consume capturas propias de cada cliente.

**Tech Stack:** IDEs reales, Docker/Xvfb para JetBrains si es viable, Visual Studio experimental en Windows, FFmpeg, Node.js y el sistema de captura existente.

## Global Constraints

- Autonomía ya autorizada; no pedir nuevamente aprobación del guion.
- Trabajar y commitear sobre `main`; no publicar ni pushear.
- No alterar repositorios o sesiones personales para la grabación.
- No representar previews o maquetas como capturas del IDE real.
- Mantener dos README raíz y copy bilingüe de la landing; videos y pósteres solamente en inglés.
- Captura de JetBrains delegada en paralelo; Visual Studio e integración a cargo del agente principal.

## Tasks

- [x] Capturar JetBrains real y verificar tests y rama de correcciones; conservar controlador y evidencia.
- [x] Capturar Visual Studio real y verificar tests y rama de correcciones; conservar controlador y evidencia.
- [x] Generalizar el compositor sin cambiar la pieza aprobada de VS Code. Producir dos videos de 40 segundos con música, dos pósteres y seis GIFs.
- [x] Integrar selección de cliente en la landing y muestras en los README propios; documentar regeneración.
- [x] Verificar audio/video, reproducción y responsive, contratos, scripts y cambios finales.

## Verificación y entrega

Las tres piezas son H.264 1920 × 1080 de 40 segundos, con AAC estéreo de 48 kHz.
La música original mide −17,94 LUFS y −1,68 dBTP. Los nueve GIF se decodifican
correctamente. Chromium reproduce las tres demos en ambos idiomas de la página;
los selectores y enlaces directos funcionan a 390, 768 y 1440 px sin overflow.

JetBrains usa IntelliJ IDEA 2026.1 real con el plugin 0.4.0 y consola Run. Visual
Studio usa el VSIX actual en un perfil aislado del IDE 2026 Insiders. Sus tests
xUnit corren en Docker; la salida intacta se muestra en el editor. El recorte
excluye las barras del host en español. En ambos ejemplos, el test original
falla y la corrección pasa los tres tests; sólo esa línea queda staged en
`review-fixes/rate-limit`, con la rama autora intacta.

Se revisaron los pósteres y los cortes del montaje. Contratos de clientes y
logo, ShellCheck, sintaxis de Node/PowerShell y `git diff --check` pasan.
La revisión independiente detectó el BOM de PowerShell 5.1; el escritor usa
UTF-8 sin BOM y el lector también admite listas de recortes que lo contengan.

La entrega se registra como un commit local sobre `main`, sin push. La carpeta
`demo/marketing/` permanece ignorada y no forma parte del commit.
