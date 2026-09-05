# Deduplicación del selector de rama base

## Problema

`git review config --porcelain` emite deliberadamente una candidata `local` y otra `remote` cuando
el mismo nombre de rama existe en ambos espacios. El origen es necesario para el asistente de
inicio, que lo pregunta en un paso posterior, pero no forma parte del valor de
`reviewworkflow.base`: allí sólo se guarda el nombre.

Los asistentes de inicio y la TUI ya pasan las candidatas por `branchPickerItems`, que conserva una
sola fila por nombre y prefiere la marcada como actual. Los selectores Set/Change the base branch de
JetBrains, VS Code y Visual Studio usan la lista porcelain cruda, por lo que muestran dos filas
visualmente idénticas.

## Diseño aprobado

Los tres clientes IDE reutilizarán `branchPickerItems` antes de construir las filas del selector de
rama base. La normalización seguirá estas reglas ya existentes:

- una sola entrada por nombre de rama;
- si una de las copias está marcada como actual, conservar ésa;
- rama actual primero y luego orden estable por nombre según el cliente;
- devolver a la CLI únicamente el nombre elegido.

No se cambia el contrato porcelain, porque las dos filas por origen son información válida para el
paso de origen de Start review. Tampoco se modifica la TUI, que ya normaliza este selector.

## Verificación

Cada cliente afectado tendrá una regresión que alimente el selector de base con copias local y
remota del mismo nombre y observe una sola opción. Se correrán las suites de JetBrains, VS Code y
Visual Studio, además de las comprobaciones de compilación correspondientes.

