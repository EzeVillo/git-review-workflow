# Specification Quality Checklist: Walkthrough del revisor (draft local)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-09
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

### Registro de validación

**Iteración 1** — se detectaron y corrigieron tres fugas de implementación en
el borrador inicial del spec, todas resueltas antes de cerrar el checklist:

1. Rutas y nombres concretos del almacenamiento del borrador (`.git/...`) en
   FR-003 → reformulado como propiedad observable ("fuera del árbol de trabajo
   versionado, no aparece como cambio, no requiere deshacer nada"). El dónde
   exacto es decisión de `/speckit-plan`.
2. Nombres de comandos y flags (`walkthrough draft`, `--build`, `--force`) en
   los FR → reemplazados por la capacidad ("generar el esqueleto", "validar el
   borrador", "pedirlo explícitamente"). La forma de la superficie CLI se fija
   en el plan, respetando la convención de espejar los idioms de git.
3. Vehículos de interfaz por cliente (notificación con botones / diálogo no
   modal) en FR-017 → reformulado como requisito de comportamiento ("aviso que
   permanece disponible hasta que el revisor actúe, sin impedir la edición").
   Qué componente lo materializa en cada cliente es decisión del plan.

**Decisiones de producto resueltas** (2026-08-09): tres preguntas de alcance y
UX planteadas al usuario tras la validación, todas respondidas e incorporadas
al spec.

1. *¿Se distingue un orden de lectura escrito por el revisor de uno del autor?*
   → **Sí, marcado discreto** en todas las superficies que informan el modo
   (FR-014a, SC-009).
2. *¿Puede el revisor pisar el walkthrough del autor?* → **Sí por invocación
   explícita desde la terminal, no ofrecido por el asistente** (FR-005a,
   FR-016a).
3. *¿Qué hace cancelar en el aviso de espera?* → **Vuelve al paso de forma de
   lectura conservando el borrador** (FR-018a, SC-010).
4. *(clarify)* *¿Sobrevive el borrador de una review pausada a la limpieza?* →
   **Sí, misma regla que ya protege las ediciones pausadas** (FR-008a, SC-011).
