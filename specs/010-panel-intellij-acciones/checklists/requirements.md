# Specification Quality Checklist: Panel del plugin de IntelliJ con la superficie de acciones del panel de VS Code

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-08
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

- La spec nombra superficies de producto (panel del tool window, barra de la
  vista, menú del plugin) porque son parte de lo que el usuario ve y decide, no
  del cómo. No nombra lenguajes, toolkits ni APIs: la elección de widgets queda
  para `/speckit-plan`.
- La referencia normativa es el panel **real** de la extensión de VS Code, no
  la matriz `surface:` del canónico: el canónico marca `both` para acciones que
  el webview no pinta, y copiarlas al panel del plugin sería inventar
  superficie (documentado en *Assumptions*).
- La spec se rige por un **invariante rector explícito** ("mismo lugar, otro
  estilo") con siete corolarios. Las decisiones de ubicación no son
  preferencias revisables: se derivan de él. Lo único revisable en
  `/speckit-clarify` sería el invariante mismo.
- El **anclaje del tool window** es la única excepción explícita al invariante:
  la extensión declara su vista a la izquierda en VS Code y el plugin la
  mantiene a la derecha, por decisión del autor. Está acotada al borde de la
  ventana; no cubre nada de lo que pasa dentro del panel.
- Los requisitos de paridad son verificables por comparación entre clientes, no
  por juicio estético: existencia, rótulo, orden, grupo, jerarquía y condición
  de aparición de cada control (FR-001 a FR-008, SC-001).
- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
