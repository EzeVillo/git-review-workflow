# Diseño: release minor de los clientes de editor

## Objetivo

Preparar una release minor para los tres clientes de editor que cambiaron desde
`origin/main`, manteniendo sus metadatos de distribución y sus notas de release
en sincronía. La TUI queda fuera de este alcance: todavía no tuvo una release
anterior que deba incrementarse.

## Alcance y versiones

| Cliente | Versión actual | Nueva versión |
| --- | --- | --- |
| VS Code | `0.3.0` | `0.4.0` |
| JetBrains | `0.3.0` | `0.4.0` |
| Visual Studio | `0.2.0` | `0.3.0` |
| TUI | `0.1.0` | Sin cambios |

El CLI también queda fuera de alcance: su `0.9.0` ya tiene sus metadatos y su
sección de changelog propios.

## Implementación

Cada cliente se actualizará con su script de versionado existente para no omitir
archivos empaquetados o fuentes secundarias de verdad. Después se editará el
changelog del cliente para insertar, encima de la versión publicada más reciente,
una sección fechada con la versión nueva.

Las notas se escribirán por comportamiento visible para quien usa el cliente,
no como una lista de commits. Deben cubrir las modificaciones acumuladas desde
la última versión de cada cliente, incluyendo flujos de inicio/finalización,
selección de rama base, actualización del panel y mensajes de confirmación según
corresponda a cada implementación.

No se cambiarán `tui/CHANGELOG.md`, `TUIVersion`, ni los archivos de distribución
de la TUI.

## Validación

Se comprobará que:

1. Cada nueva cabecera de changelog coincide exactamente con la versión
   distribuida por su cliente.
2. La TUI continúa en `0.1.0` y no aparece en el diff de versionado.
3. Las comprobaciones de producto y las pruebas de release aplicables pasan.

