# Walkthrough authoring guide (opcional, por repo)

**Fecha:** 2026-08-11  
**Estado:** aprobado en diseño; pendiente de plan e implementación  
**Concepto en producto:** *guide* (no “template”)

## Problema

`git review walkthrough init` (y `draft`) ya generan un esqueleto con **formato fijo** e instrucciones genéricas de contenido (qué es `> key`, tono del why, Heads-up). Esas reglas genéricas no capturan el criterio de un equipo: qué archivos suelen ser esenciales en *este* monorepo, cómo explicar casos de borde, qué no merece Heads-up, etc.

Un “template” del walkthrough **no** es la solución: el molde del formato *ya es* el skeleton. Lo que falta es un lugar opcional de **criterios de autoría**, que un agente (o un humano) lea al llenar el esqueleto, sin poder alterar el contrato de `build`.

## Objetivos

1. Señalar un archivo de repo **opcional** con reglas de *contenido* al escribir walkthroughs.
2. Que `init` y `draft` lo descubran de la misma forma (mismo generador de skeleton).
3. Que el guide **no** cambie formato, lista de archivos, numeración ni validación de `build`.
4. Cambio chico: texto + una comprobación de presencia + docs; sin motor de templates ni subcomando nuevo.

## No objetivos (v1)

- Subcomando que genere o valide el guide.
- Parsear, inyectar o aplicar el guide en shell.
- Path configurable / `git config` / guide global del usuario.
- Leer el guide desde el tip del PR en `draft` (eso sería “guide del autor del PR”).
- Superficie en la extensión VS Code o el plugin de IntelliJ.
- Tocar la landing (`docs/index.html`).

## Diseño

### Qué es el guide

Archivo Markdown **opcional, commiteado en el repo**, con convenciones de contenido para quien llena el esqueleto:

- qué entradas marcar `> key` (y qué no);
- cómo redactar los whys y el Heads-up;
- convenciones del equipo (tono, nivel de detalle, anti-patrones locales).

La CLI **no interpreta** el guide. Solo lo **señala**. Quien anota (persona o agente) es quien lo lee y aplica.

### Path canónico

```text
.review/walkthrough-guide.md
```

- Fijo; sin config en v1.
- Vive junto al sidecar del walkthrough (`.review/walkthrough.md`).
- Lo crea el equipo a mano cuando quiera.
- `clean` / `forget` **no** lo tocan: es prosa de equipo versionada, no estado de una sesión de review.

### Alcance: repo del work tree, no el tip del PR

La presencia del guide se resuelve en el **working tree del repositorio donde se corre el comando** (ruta de archivo `.review/walkthrough-guide.md` relativa al top-level del repo).

En `draft`, eso significa las convenciones del **equipo que draftea / revisa**, no un guide embebido en la rama remota del autor. Buscar `git show <tip>:.review/walkthrough-guide.md` queda fuera de v1.

### Cambios en `init` y `draft`

El skeleton se genera en un único bloque compartido en `bin/git-review-verbs/walkthrough`. Ahí van dos superficies:

#### A) Comentario HTML del skeleton

Un bullet nuevo (inglés, como el resto del comentario), en la lista de instrucciones de autoría, del estilo:

- Optional authoring guide: if `.review/walkthrough-guide.md` exists in this repository, follow it for **content choices only** (which entries are key, how to write whys / Heads-up, team conventions). It cannot change this format, the file list, or the numbering rules above.

#### B) Note en stderr al terminar de escribir

Siempre una de estas dos líneas (mismo estilo que otras `note:` del verbo):

| Condición | Mensaje (orientativo; la implementación puede ajustar redacción manteniendo el sentido) |
|-----------|----------------------------------------------------------------------------------------|
| El path **existe** como archivo en el work tree | `note: authoring guide found at .review/walkthrough-guide.md; use it for keys/whys (it cannot change the format)` |
| **No** existe | `note: optional authoring guide: create .review/walkthrough-guide.md for team rules on keys/whys (it cannot change the format)` |

Así el guide es descubrible sin abrir el `.md`, y si está, el flujo confirma que hay que usarlo.

`build` / `draft --build`: **sin cambios de reglas**.

### Documentación

Actualizar **ambos** README (`README.md` y `README.es.md`) en la sección de `git review walkthrough`:

1. path `.review/walkthrough-guide.md`;
2. opcional;
3. solo criterios de contenido;
4. no cambia el formato; `build` no lo valida;
5. `init` y `draft` lo señalan (encontrado vs invitación a crearlo).

La landing no se toca (no es flag, tabla de verbos, instalación ni demo del formato del walkthrough).

### Tests

En la suite de walkthrough (bats, preferible en contenedor en Windows):

1. Sin guide: `init` (y un caso `draft`) emite la note “optional… create…”.
2. Con `.review/walkthrough-guide.md` presente: note “found at…”.
3. El skeleton generado contiene el path del guide en el comentario de instrucciones.
4. Nombres de `@test` en ASCII puro.

No se requieren tests nuevos de reglas de `build` salvo regresión accidental si se toca código adyacente.

## Decisiones cerradas

| Tema | Decisión |
|------|----------|
| Nombre | *guide* (no template) |
| Ubicación | por repo, path fijo `.review/walkthrough-guide.md` |
| Superficie | solo texto en skeleton + note de presencia; sin subcomando |
| init vs draft | mismo comportamiento (generador compartido) |
| Enfoque de producto | C: skeleton + stderr + README EN/ES |
| Interpretación por la CLI | ninguna |

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| El guide intenta “cambiar el formato” y el agente obedece | Texto del skeleton y de la note reiteran que no puede; `build` sigue siendo el gate de formato |
| Note ruidosa cuando nadie usa guides | Una sola línea; el costo es aceptable por descubribilidad |
| Confundir guide del repo con walkthrough del PR en draft | Documentar: se lee el work tree local, no el tip remoto |
| Tres superficies de docs | Solo dos README; landing fuera de alcance |

## Criterios de éxito

- Un equipo puede commitear `.review/walkthrough-guide.md` y un agente que siga el skeleton/notes lo usará para keys/whys sin romper `build`.
- Sin guide, `init`/`draft` siguen funcionando y avisan que el archivo es opcional.
- Diff de implementación acotado al verbo walkthrough, tests y dos README.

## Siguiente paso

Plan de implementación (`writing-plans`) e implementación del cambio mínimo descrito arriba.
