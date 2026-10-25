# Descubrimiento orgánico y primera medición web

Fecha: 25 de octubre de 2026.

## Objetivo

Ayudar a quienes revisan PRs de agentes a orientarse entre los cambios: por dónde empezar,
por qué cambió cada archivo y qué merece atención. El recorrido guiado es la propuesta
principal; ejecutar y corregir el PR en el editor completa ese flujo. La adopción se
comprobará con uso y repetición, no sumando descargas como personas.

## Alcance de esta primera entrega

- La landing y ambos README presentan primero el recorrido de lectura y su contexto para
  revisar cambios de agentes. La ejecución y la extracción de correcciones completan la
  propuesta. Se conservan las demos y el estilo visual existente.
- `.agents/product-marketing.md` fija el público, el problema y la jerarquía de comunicación.
  AGENTS, npm, los cuatro README de clientes y las fichas siguen ese criterio. El tagline
  compartido se actualiza desde el contrato, sin cambiar acciones ni comportamiento.
- Una guía completa en inglés y su traducción en español tienen URLs propias, HTML estático,
  canonical propio y `hreflang` recíprocos. Las enlazan la landing y ambos README.
- El sitemap propio enumera las tres páginas. No se crea un `robots.txt` bajo el prefijo:
  debe anunciarse desde el sitio principal o presentarse directamente en Search Console.
- La tarjeta social se regenera desde `scripts/og/card.html`, con el mismo mensaje principal.
- La instrumentación web usa el snippet público de Umami aportado por Ezequiel, compartido
  con el resto de `ezevillo.com` y separado por la etiqueta `git-review-workflow`. El tracker
  limita la recolección a ese hostname; las pruebas bloquean su carga. Se cuenta copia solo
  después de que la escritura al clipboard termina bien; la reproducción se cuenta una vez
  por interfaz y carga de página. Los clics usan atributos reconocidos por Umami.
- CI y la comprobación de un release validan rutas, assets, fragmentos, canonical, traducciones
  y sitemap. La verificación de navegador cubre idiomas, tamaños y eventos reales de la página.

## Criterio visual

Las guías reutilizan IBM Plex Mono para títulos/comandos e IBM Plex Sans para lectura, fondo
`#0B0E14`, texto `#DCE2ED`, verde `#4CC46B` y foco amarillo `#E6B455`. El contenido ocupa una
columna de lectura con índice lateral, que pasa arriba en móvil. El ejemplo de estado compara
qué contiene el diff staged durante y después de la revisión; representa una distinción del
producto, sin agregar una animación o un diagrama decorativo.

## Decisiones

El mensaje principal parte del cuello de botella que señaló Ezequiel: entender y revisar
los cambios de los agentes. El walkthrough hace concreto ese valor con un orden, un motivo
por archivo y las entradas importantes. Lo escribe el autor, un agente o el propio revisor;
la herramienta no genera ni verifica automáticamente esas explicaciones. La guía de revisión
local sigue respondiendo esa búsqueda específica sin definir por sí sola el pitch de portada.

Una revisión que termina en observaciones, sin corregir código, también aprovecha el recorrido.
Se eliminan las frases que reservaban la herramienta para quien edita o ejecuta el PR y las
afirmaciones de que el agente conoce por sí solo el razonamiento correcto. El contexto central
distingue capacidades verificables de hipótesis de adopción que todavía hay que medir.

HTML estático permite leer e indexar cada traducción sin ejecutar JavaScript. Dos URLs de guía
evitan depender del selector de idioma de la portada para descubrir la versión española.
El checker usa solo Node y no agrega un generador de sitio ni dependencias de build.

Los eventos son señales de descubrimiento e intención. Un clic de instalación o una copia de
comando no comprueba instalación. No se agregó telemetría de la CLI, los IDEs o la TUI, ni se
usan repositorios o ramas para identificar personas. Eso exige un diseño e implementación
separados y consentimiento del usuario de la herramienta.

## Antes de publicar

- [ ] Ezequiel revisa los textos, guías y vistas locales.
- [x] Ezequiel aportó el snippet público de Umami; se integra en las tres páginas con una etiqueta
  del proyecto dentro de la medición común del dominio.
- [ ] Tras publicar, comprobar que las visitas y eventos aparecen al filtrar esa etiqueta.
- [ ] El sitio principal anuncia el sitemap y se consulta el estado en Search Console.
- [ ] Las fichas publicadas se actualizan por su mecanismo de publicación, con aprobación previa.
- [ ] Se decide cuándo publicar la landing. En esta tarea no se crean tags, pushes ni despliegues.

El usuario autorizó alinear los textos y hacer un commit local. No se crean tags, pushes ni
despliegues: no dispone de tokens de Netlify para publicar ahora. Los cambios de archivos de
workflow no son una autorización para ejecutarlos contra producción.
