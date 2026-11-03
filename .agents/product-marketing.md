# Contexto de producto y comunicación

Actualizado: 3 de noviembre de 2026.

## Público y problema

El público principal son desarrolladores y equipos que revisan cambios de agentes de IA.
Recibir muchos archivos cambiados obliga a reconstruir por dónde empezar, el motivo de
cada cambio y las partes que necesitan atención. El mismo recorrido sirve para PRs escritos
por personas; usar IA no es un requisito del producto.

## Propuesta principal

Revisar un PR con un recorrido guiado que aporte orden de lectura y contexto.

Mensaje de portada:

> La IA escribió el código. Revisalo con un recorrido guiado.

El walkthrough puede venir del autor o de un agente, committeado junto al cambio. El revisor
también puede preparar su propio orden local cuando el PR no trae uno. El panel sigue las
entradas y muestra su motivo, las marcadas como importantes y el contexto general del cambio.

## Jerarquía del mensaje

1. Orientarse y entender: orden de lectura, motivo por archivo y puntos importantes.
2. Revisar y dejar observaciones, aunque no se modifique el código.
3. Ejecutar pruebas y corregir cuando haga falta; extraer esas correcciones a otra rama.

La revisión local sostiene el flujo completo. No presentarla como el único motivo para usar
la herramienta, ni decir que quien solo lee o comenta ya tiene suficiente con otro panel.
Una revisión útil puede terminar sin ninguna corrección de código.

## Capacidades y límites

- La CLI crea la estructura, valida el formato y expone el estado. No escribe ni comprueba
  por sí sola los motivos del walkthrough y no llama a un modelo de IA para generarlos.
- El recorrido es una propuesta del autor, agente o revisor. Las explicaciones se contrastan
  con el código y sus pruebas; no son evidencia automática de que el cambio esté bien.
- El PR completo sigue disponible durante el recorrido. El orden no sustituye inspeccionar
  archivos fuera de él ni obliga a corregirlos.
- Las correcciones se extraen solo si se hicieron. Los comentarios Local y Shared tienen
  su propio flujo; Shared se prepara como Markdown para el PR, sin publicarlo automáticamente
  en GitHub o GitLab.
- Describir los clientes por lo que ofrecen al usuario, sin compararlos entre sí. La copy
  compartida de las tiendas se mantiene en `contracts/client-product-surface.yaml`.

## Evidencia y validación

Esta jerarquía es el criterio de comunicación elegido para probar. Todavía no hay una
comparación que demuestre que consigue más adopción que liderar con la edición local.
Las demos muestran capacidades en ejemplos; no son casos de clientes ni mediciones de ahorro.

En pilotos, observar si las personas se orientan con el recorrido, entienden el motivo de
los cambios y quieren usarlo en otro PR. Una visita, descarga, reproducción o like no
demuestra uso recurrente. No prometer porcentajes de ahorro o de detección de errores.

## Descubrimiento y contenidos

La portada presenta el recorrido con contexto. Las guías pueden responder búsquedas más
específicas, como revisar un PR localmente, sin convertir ese tema en la definición de todo
el producto. Los volúmenes de búsqueda y la conversión son hipótesis por medir.

Los documentos de trabajo se escriben en español. El producto y las tiendas usan inglés;
README y referencia CLI conservan sus pares bilingües. Los cambios de presentación no
requieren reescribir la referencia técnica, la historia de decisiones o los changelogs.

En esta etapa LinkedIn queda fuera por decisión de Ezequiel. El asistente busca posibles
participantes en conversaciones públicas afines y prepara invitaciones concretas; no delega
la búsqueda en los contactos personales del autor. Todo contacto sigue requiriendo aprobación
previa del destinatario, canal y texto.

## Publicación

La landing se publica en Cloudflare, en `https://git-review.ezevillo.com/`, con
tags `landing-vX.Y.Z`. Sus releases son independientes de la CLI y los clientes.
Publicar en redes, actualizar fichas, pushear o desplegar requiere la autorización
correspondiente de Ezequiel; preparar textos o commits locales no la concede.

## Referencias

- `AGENTS.md`: arquitectura y reglas del repositorio.
- `README.md` y `README.es.md`: presentación del producto.
- `contracts/client-product-surface.yaml`: copy compartida de los clientes.
- `specs/marketing/2026-10-25-descubrimiento-organico.md`: alcance y verificación de la web.
