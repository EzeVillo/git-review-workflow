# Presentación de las demos en los README

## Objetivo

Hacer que quien llegue al repositorio entienda el producto en movimiento sin
tener que abandonar el README, y reservar la landing para reproducir las demos
completas de cada IDE.

## Diseño aprobado

Los README raíz en inglés y español reemplazarán el póster estático visible por
el GIF corto de VS Code sobre el orden de lectura. El GIF seguirá siendo un
enlace a la demo completa en la landing. Así, la primera pieza visual comunica
el comportamiento del producto inmediatamente, incluso cuando el bloque
desplegable de ejemplos permanece cerrado.

Debajo se conservarán los enlaces directos para elegir VS Code, JetBrains o
Visual Studio en la landing. El bloque desplegable seguirá alojando muestras de
los tres clientes para quien quiera compararlos, sin cargar la cabecera con tres
animaciones simultáneas. Para evitar repetir el GIF hero dentro del mismo README,
la muestra de VS Code del desplegable se reemplazará por uno de sus otros
momentos del flujo; JetBrains y Visual Studio conservarán sus muestras actuales.

Los README propios de las extensiones mantendrán su identidad por cliente. El
de VS Code completará el mismo bloque desplegable de tres momentos que ya usan
JetBrains y Visual Studio: seguir el orden de lectura, editar y probar, y extraer
solamente la corrección. Sus URLs seguirán siendo absolutas para funcionar en
las fichas empaquetadas de las tiendas.

## Video completo

Los tres MP4 seguirán alojados y reproducidos en la landing mediante el selector
existente. No se requiere YouTube: la landing ofrece reproducción directa sin
branding ni salida a otro sitio, y los archivos actuales son suficientemente
pequeños para servirse desde GitHub Pages. Los pósteres estáticos continúan como
estado previo a la reproducción dentro de la landing.

## Recorrido de terminal

Se eliminarán de ambos README raíz y de la landing todos los enlaces de
marketing al recorrido antiguo de terminal. Esto no elimina ni oculta la CLI o
la TUI de la documentación funcional; solamente evita que una pieza visual
inferior compita con las demos nuevas de los IDE. El video puede permanecer en
YouTube sin referencias desde estas superficies. El póster raíz
`demo-poster.png`, creado para esa pieza y ya sin consumidores, se eliminará.

## Alcance y verificación

Se modificarán `README.md`, `README.es.md`, `vscode-extension/README.md`,
`docs/index.html`, la descripción de la campaña en `CONTRIBUTING.md` y la nota
histórica correspondiente en `decisiones.md`; también se eliminará el póster
raíz obsoleto. No se cambiarán los videos, GIF, scripts de captura ni el
comportamiento del producto. La implementación comprobará que
ambos README raíz se mantengan como traducciones espejo, que no queden enlaces
públicos al video de terminal en esas superficies, que todos los assets
referenciados existan y que la landing conserve sus tres demos y su selector
bilingüe.
