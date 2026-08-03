# Specification Quality Checklist: Paridad de información entre la CLI y el panel del editor

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-03
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

## Notas de validación

**Iteración 1** — tres `[NEEDS CLARIFICATION]` en los requisitos de custodia de
la paridad, alcance del diffstat y superficie del mensaje del commit. Los tres
eran de alcance, no detalles técnicos, así que se presentaron como preguntas en
vez de resolverse con un default.

**Iteración 2** — respondidas y registradas en la sección *Preguntas resueltas*
del spec:

- **Q1 → Custom**: sin custodia. La paridad es un estado que esta feature
  alcanza, no una invariante del proyecto; por ahora se puede romper. Se cayeron
  la historia que la custodiaba y su requisito.
- **Q2 → A**: la lista de archivos del commit queda como exclusión deliberada
  con su motivo (el panel ya la ofrece al abrir los cambios, y duplicarla
  chocaría con la exclusión de interfaz de diff propia heredada de `002`).
- **Q3 → A**: sólo el asunto. El cuerpo del mensaje queda como exclusión
  registrada.

Sin ítems pendientes. Listo para `/speckit-plan`.

## Efecto de las respuestas sobre el alcance

Q3 → A es la que más recorta, y para bien: sin cuerpo del mensaje **no hace falta
ninguna invocación nueva de la CLI**. Todo lo que la feature agrega entra como
campos aditivos en la consulta de estado que la extensión ya hace. Eso elimina
de raíz dos riesgos que estaban anotados para el plan:

- ya no hay que decidir qué hacer con la superficie de explicaciones, hoy
  cerrada por contrato al modo con walkthrough;
- el presupuesto de invocaciones deja de ser una restricción a administrar y
  pasa a ser un requisito duro y trivial de cumplir (FR-013, SC-005).

## Riesgos anotados para la fase de plan

No bloquean el spec, pero conviene que el plan los resuelva explícitamente:

1. **Nombres de autor y bytes de control.** FR-011 existe porque la garantía que
   el proyecto tiene para paths (git cita cualquier byte de control) **no**
   aplica a un nombre de autor: lo elige quien commitea, no git. Es la
   superficie de riesgo nueva de esta feature.
2. **Aridad posicional del registro de estado.** FR-012 apunta a que el registro
   común ya varía su cantidad de campos según el modo; agregar datos "al final"
   los deja en posiciones distintas por modo.
3. **Costo de producir los asuntos.** FR-014 y SC-008: una review de decenas de
   commits necesita el asunto de todos ellos. El plan debe evitar que eso se
   traduzca en un proceso por commit.
4. **Precedente sin cobertura**: la extensión ya invoca una consulta directa al
   repositorio para armar la lista de archivos de un commit, y eso no está
   justificado en ninguna spec. FR-001 lo vuelve inconsistente. Queda
   explícitamente **fuera de esta feature** por decisión del usuario ("después
   vemos qué hacemos"); el principio general sí se documenta en el README de la
   extensión.
