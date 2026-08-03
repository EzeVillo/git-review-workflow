# Contrato: registros `subject`, `author` y `base` de `git review status --porcelain`

**Delta sobre** [`001-contrato-porcelain/contracts/status-porcelain.md`](../../001-contrato-porcelain/contracts/status-porcelain.md),
que sigue vigente sin cambios. Este documento sólo agrega registros; **no
modifica ninguno existente, ningún exit code y ninguna invocación**.

Sigue siendo formato porcelain v1: texto plano, una línea por registro, campos
separados por tab, primer campo = etiqueta. La aditividad es la de siempre — un
consumidor ignora las etiquetas que no reconoce, así que uno construido contra
el contrato anterior no se entera de que estos registros existen.

## Regla que gobierna estos tres registros

Los campos de estos registros son **texto escrito por una persona**, no por git.
A diferencia de un path, **pueden contener el separador de campos**:

| Byte    | ¿Puede aparecer en el asunto? | ¿En el nombre del autor? |
|---------|-------------------------------|---------------------------|
| tab     | **sí**                        | **sí**                    |
| newline | no (`%s` es la primera línea) | no (git lo elimina del ident al commitear) |

De ahí la regla, que aplica a los tres y a cualquier registro futuro con texto
libre:

> **El texto libre es siempre el último campo de su registro, y hay a lo sumo
> uno por registro.** Se emite byte a byte, sin escapar, sin citar y sin
> sustituir nada.

Un consumidor lee ese campo como *"todo lo que sigue al N-ésimo tab, hasta el
fin de línea"* — no como *"el campo N-ésimo"*. Es la misma disciplina que el
contrato ya aplica a los paths, por el motivo opuesto: allá el separador no
puede aparecer en el dato, acá sí, y por eso el dato va donde no hay nada que
desplazar.

Corolario de diseño: estos registros **no admiten campos nuevos al final**. Lo
que haya que agregar en el futuro va en un registro propio.

## Registro `subject`

```
subject<TAB>position<TAB>asunto
```

Emitido **sólo en modo `step`**, una vez por posición de la secuencia, en el
mismo orden que los registros `entry`.

- `position`: 1-based, el mismo que el del registro `entry` correspondiente.
- `asunto`: la primera línea del mensaje del commit, tal cual. Puede contener
  tabs; puede estar vacío (un commit cuyo mensaje no tiene primera línea). Nunca
  contiene un newline.

## Registro `author`

```
author<TAB>position<TAB>autor
```

Emitido **sólo en modo `step`**, una vez por posición, en el mismo orden.

- `position`: como arriba.
- `autor`: nombre y correo en la forma `Nombre <correo>`, tal como los muestra
  la salida humana. Puede contener tabs. Nunca contiene un newline.

Es el autor, no quien commiteó: es el dato que la salida humana ya imprime.

## Registro `base`

```
base<TAB>base
```

Emitido **sólo en modo `whole`**, y **sólo si hay una base registrada**
(`branch.<rama>.reviewbase`). Sin base, el registro se omite entero — omitir,
nunca en blanco, la misma regla que el resto del contrato.

Registro único, sin posición: la base es de la review, no de una entrada.

## Ejemplo completo (modo step, 2 commits, el primero con ediciones)

```
state	review/feat-x	feat-x	a1b2c3d4e5f6…	step	none	1	2	2	6bce6d1
entry	1	6bce6d1	1
entry	2	f307e69	0
subject	1	feat: exponer el asunto en porcelain
subject	2	test: cubrir los bytes hostiles
author	1	Eze Villo <ezevillodev@gmail.com>
author	2	Eze Villo <ezevillodev@gmail.com>
```

El orden entre grupos de registros no es significativo; el orden **dentro** de
un grupo sí lo es, y coincide con el de `entry`. Un consumidor debe emparejar
por `position`, nunca por orden de aparición.

## Ejemplo (modo whole, con base)

```
state	review/fix-quoting	fix-quoting	1a2b3c4d5e6f…	whole	none
base	main
```

## Lo que este delta NO hace

- **No agrega ningún campo** a `state` ni a `entry`. La aridad de los registros
  existentes es exactamente la de `001`, incluida su variación por modo.
- **No cambia `--why`**, que sigue siendo válido sólo en modo walk y sigue
  fallando con exit `1` fuera de él.
- **No agrega invocaciones.** Los tres registros salen de la misma
  `git review status --porcelain` que el consumidor ya hace.
- **No cambia la salida humana**, que ya mostraba estos tres datos y los sigue
  mostrando igual.

## Exclusiones registradas

Datos que la salida humana muestra y que este contrato **deliberadamente** no
expone, con su motivo (FR-015):

| Dato                                  | Motivo                                                                                                                       |
|---------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Cuerpo del mensaje de un commit       | Prosa multi-línea: no puede viajar en un registro de una línea, y exponerla requeriría una superficie de stream propia. Q3 la dejó fuera del alcance. |
| Diffstat de un commit                 | El consumidor ya alcanza esos mismos archivos por la superficie de diff de su host; duplicarlo chocaría con la exclusión de interfaz de diff propia de `002`. Q2. |
| Textos de ayuda (`next`, `banked …`)  | Son la guía al usuario humano sobre qué comando correr, no estado de la review. Ya excluidos por `001`.                       |
