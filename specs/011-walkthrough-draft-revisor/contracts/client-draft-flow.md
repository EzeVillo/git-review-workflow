# Contrato: flujo del borrador en el asistente de inicio

**Feature**: `011-walkthrough-draft-revisor`

Normativo para los dos clientes. Paridad de **producto**: mismo flujo, mismos
textos, mismas decisiones. El vehículo de interfaz es propio de cada plataforma.

## Dónde entra

En el paso **forma de lectura** del asistente, que ya existe y ya se arma con
los registros `offer` ([layoutOffers.ts](../../../vscode-extension/src/review/layoutOffers.ts),
[LayoutOffers.kt](../../../jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/LayoutOffers.kt)).
No se agrega un paso nuevo ni se reordena el asistente.

### Metadatos de los ids nuevos

| id             | label                          | description                            |
|----------------|--------------------------------|----------------------------------------|
| `draft`        | `Walkthrough — draft one`      | `no reading order yet; write one`      |
| `draft-resume` | `Walkthrough — continue draft` | `finish the reading order you started` |

Orden en el selector: el de `OFFER_ORDER`, extendido a
`walk, keys, draft, draft-resume, step, whole`. La regla de `recommended`
primero no cambia.

## Máquina del flujo

Al elegir `draft` o `draft-resume`:

```text
1. crear (sólo si el id es `draft`) ────► walkthrough draft <branch> [flags]
2. abrir el borrador en el editor
3. ESPERAR  ──────────────────────────► aviso no bloqueante [Continue] [Cancel]
      │
      ├─ Continue ──► walkthrough draft --build <branch> [flags]
      │                   ├─ falla ──► mostrar stderr ──► volver a 3
      │                   └─ ok    ──► 4
      │
      └─ Cancel ────► volver al paso de forma de lectura (paso 4 del asistente),
                      conservando el borrador
4. recargar ofertas ──► config --porcelain [flags] -- <branch>
      ├─ hay `keys` ──► preguntar recorrido completo vs sólo esenciales
      └─ no hay      ──► continuar sin preguntar
5. confirmación y start, como cualquier otra forma de lectura
```

### Requisitos del aviso de espera

1. **No bloqueante**: el revisor tiene que poder editar el borrador mientras
   está visible. Un diálogo modal incumple el contrato.
2. **Persistente**: no puede desaparecer solo. El revisor puede tardar minutos.
3. **Reintentable**: tras un rechazo de validación muestra el motivo y vuelve a
   quedar disponible, sin límite de intentos.
4. **Recuperable**: si el revisor lo descarta o cierra el editor, el borrador
   sobrevive y se retoma reabriendo el asistente, donde la oferta pasa a ser
   `draft-resume`.
5. **Con la ruta a mano cuando el archivo no se pudo mostrar**: si el cliente no
   logró abrir el borrador —el caso real es un proyecto abierto en una subcarpeta
   del repo, donde `<cwd>/.git` no existe—, el aviso dice dónde quedó. La CLI
   imprime la ruta por **stdout** y los dos clientes muestran únicamente stderr,
   así que el aviso es el único lugar donde el revisor puede enterarse. Se sigue
   diciendo en cada reintento, no sólo la primera vez.
6. **Guardado antes de validar**: en *Continue*, el cliente guarda el borrador
   —y únicamente ése, nunca todo lo abierto— antes de invocar `--build`, que lee
   del disco. VS Code no autoguarda por defecto y IntelliJ guarda al perder el
   foco, que es justo lo que no ocurre mientras el asistente conduce: sin esto
   el camino normal —escribir el orden en el editor y apretar Continue— valida
   el esqueleto vacío que quedó en disco y responde con el error de entradas sin
   llenar mientras el texto está a la vista, sin nombrar la causa.

**Cerrar el aviso no significa lo mismo en los dos clientes, y es deliberado.**
En VS Code, descartar la notificación (la cruz, o un *Clear All Notifications*)
**no** es Cancel: es lo más fácil de hacer sin querer mientras se edita el archivo
que el aviso pide editar, así que el aviso se vuelve a mostrar y sólo *Cancel*
abandona el bucle. En IntelliJ la cruz del `DialogWrapper` **sí** equivale a
Cancel, y por eso `DraftFlowEvent` no tiene el caso `Dismiss`: no existe ahí el
accidente que lo motiva —no hay nada que cierre ese diálogo en masa, y cerrarlo es
un acto sobre ese diálogo y no sobre una bandeja de avisos—, y Swing entrega la
cruz y el botón por el mismo `doCancelAction`. En ninguno de los dos se pierde
trabajo: el borrador sobrevive y la vuelta siguiente lo ofrece como
`draft-resume` (requisito 4).

### Vehículo por plataforma

| Cliente  | Vehículo                              | Por qué                                                                                                                |
|----------|---------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| VS Code  | Notificación con acciones             | No bloquea, y al tener botones no se auto-oculta. `{modal: true}` bloquea el editor y queda descartado.                |
| IntelliJ | `DialogWrapper` con `isModal = false` | Mismo efecto; toda la familia `Messages.*` bloquea el IDE. Menos infraestructura que registrar un `NotificationGroup`. |

Diferencia estructural admitida: el asistente de VS Code es asíncrono y espera
el aviso dentro del propio flujo; el de IntelliJ es síncrono, así que corta y se
reanuda desde el callback del diálogo, con el contexto (rama, origen, rango)
capturado en la closure. **Invisible para el revisor**: en ninguno de los dos
tiene que reabrir el asistente en el camino normal.

## Invocaciones permitidas

Ampliación de la lista cerrada de
[
`002-extension-vscode/contracts/cli-invocation.md`](../../002-extension-vscode/contracts/cli-invocation.md):

```sh
git review walkthrough draft [--local|--offline] [--delta] -- <branch>
git review walkthrough draft --build [--local|--offline] [--delta] -- <branch>
```

Ambas con `network: false`. Los flags de origen y rango son **los mismos** que
el asistente ya resolvió en sus pasos previos: el borrador tiene que listar los
archivos de la review que se va a iniciar, no otros.

## Prohibiciones

- Ningún cliente lee, parsea, valida ni escribe el borrador. Sólo invoca la CLI
  y muestra lo que reporta.
- Ningún cliente deriva por su cuenta si se puede armar un borrador o si ya
  existe: eso llega por `offer`.
- Ninguna acción, control o bloque nuevo en el panel. `panel_layout` no cambia.
- Ninguna llamada a un servicio de IA, ni sugerencia de una. Quién completa el
  borrador está fuera del producto.
