# Specification Quality Checklist: El borrador del revisor, escrito por un agente

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-18
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`

### Sobre los marcadores que quedaban abiertos (cerrados 2026-08-19)

Los dos `[NEEDS CLARIFICATION]` se resolvieron en `/speckit-clarify` y ya no
quedan marcadores en la spec. Ver `## Clarifications`, sesión 2026-08-19.

1. **FR-019 — recuperar las instrucciones sobre un borrador ya instalado.**
   Sobreviven dentro del archivo como bloque reconocido del formato: la
   construcción lo preserva y la lectura lo filtra (FR-013a). Se agregaron
   FR-013a, SC-014 y SC-015, y se ajustó FR-007 por el lado del autor, cuyo
   sidecar sí se commitea.
2. **FR-025 — forma del estado del panel con borrador pendiente.** Es un bloque
   propio arriba del cuerpo `no-review`, que sigue entero debajo. La analogía
   con "falta configurar la base" —la única sub-disposición que hoy reemplaza el
   cuerpo— no se sostiene: sin base no hay nada más que hacer en ese panel, con
   un borrador a medio escribir sí.

### Otras tres decisiones tomadas en la misma sesión

Salieron de leer el código, no de los marcadores, y las tres cambiaban el
contrato o la disposición:

3. **Superficie de reporte sin review activa (FR-020, FR-021).** El escenario 7
   de la US3 pedía la ruta del borrador en el informe de estado, que fuera de
   una rama de review no emite un solo registro por contrato. Se movió a la
   superficie de configuración y arranque, la única que el panel ya consulta sin
   review y sin nombrar rama.
4. **Varios borradores a la vez (FR-021, FR-026).** El namespace admite N y el
   revisor está parado en la base, así que no hay "esa rama": se reportan y se
   muestran todos, una fila por borrador.
5. **Qué cuenta como entrada anotada (FR-022, SC-013).** El esqueleto deja dos
   marcas de posición por entrada y el progreso es un número solo: cuenta sólo
   la entrada que tiene las dos resueltas.

### Sobre "no implementation details"

La spec nombra conceptos del dominio (rango de la review, árbol de trabajo,
directorio de git, salida y entrada estándar) porque el producto **es** una CLI
de git y esos son los términos del problema, no de la solución. No nombra
banderas concretas, nombres de archivo internos, claves de configuración,
nombres de funciones ni identificadores de acciones de los clientes: eso queda
para `/speckit-plan`.

### Dependencias verificadas contra el código (2026-08-18)

- Ampliar la matriz de acciones del contrato multi-cliente obliga a mover a la
  vez el conteo fijo del verificador automático (dos lugares), las órdenes
  declaradas por la extensión de VS Code, el menú del plugin de JetBrains y los
  archivos de dominio de la extensión de Visual Studio. Recogido en FR-034 y en
  la última suposición.
- El listado de reviews legible por máquina **no** emite hoy ninguna marca de
  borrador, aunque el listado para personas sí la muestra. FR-023 lo cubre.
- Las situaciones del panel se derivan hoy únicamente del código de salida del
  informe de estado, así que un estado persistente de borrador pendiente exige
  que la CLI lo reporte primero. FR-021 lo cubre, y por eso la CLI va en la
  primera fase.

### Dependencias verificadas contra el código (2026-08-19)

- El informe de estado **no emite ningún registro** fuera de una rama de review:
  la guarda del código de salida 2 corre antes del bloque legible por máquina.
  El escenario 7 de la US3 era imposible tal como estaba escrito; FR-020 y
  FR-021 lo reparten entre las dos superficies.
- El listado legible por máquina deriva cada fila de una rama de review, así que
  un borrador sin review no tiene dónde aparecer ahí. FR-023 sigue siendo sobre
  las filas que sí existen; FR-021 es otra superficie.
- La superficie de configuración y arranque ya se invoca sin rama en cada
  refresco del panel sin review, junto al informe de estado y al listado: los
  registros de borrador de FR-021 no agregan una invocación.
- La prosa previa a la primera entrada se filtra de comentarios **dos veces**
  —al reescribir el archivo y al mostrársela al revisor al entrar en la
  review—, con el mismo filtro. Por eso FR-013a tiene que decir las dos cosas
  por separado: conservar al escribir, filtrar al leer.

## Correcciones posteriores al análisis cruzado (2026-08-19)

Re-medidas o re-verificadas contra el código y contra git, y propagadas a todos
los artefactos. Se registran acá porque tres de ellas contradicen afirmaciones
que llegaron a estar escritas en varios documentos a la vez.

- **`git diff <tree>..<tip>` NO «sale 0 con salida vacía»** — esa medición
  comparaba un árbol contra sí mismo. Re-medido con git 2.52.0 en Linux y en
  Windows: el comando funciona. La prohibición de `..` **se mantiene**, con dos
  fundamentos distintos y verificados: `git log`/`rev-list` con un `lower` de
  tipo tree imprimen la historia entera con exit 0 (el único fallo específico
  del tree, y el silencioso), y `git diff <a>..<b>` con SHAs completos y sin
  `--` muere en Windows con el cwd profundo, **con cualquier tipo de extremo**.
  La regla pasó de ser una excepción para el caso tree a ser la forma única en
  los dos lados.
- **La reescritura regenera el bloque, no lo arrastra.** El contrato se
  contradecía a sí mismo. Regenerar entrega el beneficio de Q1 —las
  instrucciones sobreviven a la construcción— y elimina el costo que Q1 había
  aceptado, con menos código.
- **`awk` sin argumentos de archivo se cuelga**, y **no reporta nada para un
  archivo de cero bytes**. Las dos las resuelve la misma regla: la enumeración
  manda y `awk` sólo cuenta.
- **El bloque registra los flags con los que se generó.** Sin eso, *Validate and
  start* falla siempre sobre cualquier borrador hecho con `--delta`, `--local` u
  `--offline`.
- **El asistente no abre el borrador**, y por eso no necesita su ruta antes de
  que exista el registro que la trae.
- **Las reglas de validación son ocho, no siete**, y están enumeradas una sola
  vez en `research.md` § Las ocho reglas.
- **Versiones decididas**: CLI `0.7.0`; los tres clientes `0.2.0`.

**Cobertura conocida y aceptada**: FR-008 («el producto no ejecuta nada de lo
que el bloque describe») queda verificado por revisión de código y no por un
`@test`. Es una invariante de diseño sobre lo que el código *no* hace; un test
que la afirmara tendría que instrumentar el entorno de forma que probaría el
instrumento, no la regla. Se registra en vez de inventarle una prueba.
