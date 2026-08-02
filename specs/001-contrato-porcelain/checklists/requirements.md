# Specification Quality Checklist: Contrato de salida legible por programas

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-02
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

### Resultado de la validación

Todos los ítems pasan. Detalle de las decisiones que costaron más:

**"No implementation details"** — Se hicieron dos pasadas. La primera versión
nombraba comandos concretos (`git review status --porcelain`,
`git review walkthrough list`) y proponía un formato clave-valor. Todo eso se
sacó: son decisiones de `/speckit-plan`. Los requisitos quedaron redactados como
capacidades ("el sistema DEBE exponer la secuencia completa...") en lugar de
superficies. Se conservaron dos nombres internos (`walk_normalize`,
`changed_paths`) sólo en la sección de motivación, porque el porqué del proyecto
no se entiende sin señalar la regla concreta que se estaría violando.

**"Written for non-technical stakeholders"** — Es un producto de línea de
comandos cuyo usuario es una persona desarrolladora, así que el vocabulario del
dominio (review, walkthrough, commit, path) se mantiene. El criterio aplicado fue
que ninguna sección exija leer el código para entenderse.

**"Success criteria are technology-agnostic"** — SC-007 se reescribió: decía
"responde en menos de 200 ms", que es una métrica de sistema. Quedó expresada
como ausencia de demora percibida al navegar.

**"Scope is clearly bounded"** — Reforzado con la sección *Qué NO es esto*, a
pedido explícito: esta feature termina en los comandos, la extensión de editor
queda afuera.

### Preguntas abiertas (no bloquean la validación)

La especificación no tiene marcadores `[NEEDS CLARIFICATION]`. En su lugar, las
dos decisiones de alcance sin resolver están planteadas al final del documento,
en *Preguntas abiertas*, con opciones e implicaciones:

- **Q1**: si la secuencia de lectura se puede consultar fuera de una review activa.
- **Q2**: si el modo step expone su secuencia con el mismo detalle que walk.

Ambas afectan cuánta superficie se construye, no si la feature tiene sentido.
Conviene resolverlas antes de `/speckit-plan` — con `/speckit-clarify` o
respondiéndolas directamente.

**Resueltas**: Q1 = A (la secuencia sólo se consulta dentro de una review
activa), Q2 = C (step expone su secuencia y qué pasos tienen ediciones
bancadas).

### Revisión posterior a `/speckit-analyze`

El análisis cruzado encontró un hueco que la validación original no vio: el
edge case *"cursor fuera de rango"* estaba identificado en el spec pero ningún
requisito obligaba a señalizarlo, así que un consumidor habría quedado atado a
buscar frases en inglés justo en el caso más frecuente (un `git commit` de más
sobre una review walk). Se agregó **FR-023**.

De paso quedaron ajustados tres requisitos que estaban bien redactados pero
eran ambiguos sobre su alcance:

- **FR-017** y **FR-023** ahora dicen explícitamente que la señal es la misma
  en todo verbo que detecte la situación, no sólo en las superficies de
  consulta.
- **FR-021** distingue lo que no puede cambiar (el **texto** que lee la
  persona) de lo que sí cambia a propósito (los códigos de salida).
- **SC-008** se reformuló en el mismo sentido: su letra anterior ("sin
  modificaciones en las aserciones sobre salida humana") habría prohibido
  tocar dos aserciones de exit code, forzando a emitir el código nuevo sólo
  bajo `--porcelain` — es decir, dos contratos de exit code distintos según el
  flag, que es peor de lo que evitaba.
