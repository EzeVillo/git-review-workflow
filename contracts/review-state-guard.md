# Validación del contexto de una review

`status --porcelain` agrega, durante una review activa, un registro:

```text
guard<TAB><token>
```

El token es opaco, hexadecimal minúsculo de 40 o 64 caracteres. No es una
credencial ni se calcula en los clientes. Está ligado al gitdir, rama, HEAD y
metadata de la review activa, incluidos cursor y estado de cierre. No incluye
el índice, working tree, texto de comentarios ni buffers del editor. Los cambios
de una review diferente no lo invalidan. No se persiste como autorización de
una sesión posterior.

El resto del reporte y sus códigos de salida permanecen iguales. El registro
es aditivo, no ensancha `state`, y no aparece en salida humana ni en `--why`.
Fuera de una review el reporte mantiene su comportamiento anterior, incluido el
código 2 y stdout vacío: allí los clientes siguen consultando inventario y config.

Una acción que se refiere a ese contexto se invoca así:

```sh
guard=$(git review status --porcelain | awk -F '\t' '$1 == "guard" {print $2}')
git review --expect-state "$guard" next
```

El prefijo funciona tanto a través de `git review` como invocando el dispatcher
directamente. Se envía como argumentos separados; no es una cadena de shell.
La CLI comprueba el contexto antes de entregar control al verbo:

- Coincidencia: se ejecuta normalmente y conserva stdout, stderr, stdin y código
  de salida de la operación. Su timeout y política de red dependen del verbo real.
- Diferencia: código 4, stdout vacío y `error: review state changed` en stderr.
  El verbo no se ejecuta. El cliente refresca el estado completo, muestra su
  mensaje `STALE` habitual y no reintenta la acción.
- Token inválido o argumentos incompletos: código 1, sin ejecutar el verbo.
- Error de lectura del contexto: error de la CLI, sin ejecutar el verbo.

El cliente conserva el token del modelo que originó el gesto, incluso mientras
espera una confirmación. No sustituye ese valor por el de otro modelo posterior.
Un registro ausente, inválido o duplicado no habilita la ruta rápida: se conserva
la validación anterior, incluida la prelectura donde ya existía. La presencia de
un `guard` válido permite utilizar el prefijo sin exigirlo a las CLI anteriores.

El control se usa para mutaciones de la review, no para `status`, `list`, config
de lectura, `--why`, Preview o validaciones `--check`. Comments conserva sus
guards específicos de contexto y revisión del documento; el guard general no
los sustituye ni agrega una comprobación redundante a esos comandos.

Esta comprobación es una precondición optimista en la invocación. No es un lock
global ni una transacción frente a un checkout externo concurrente. Los locks,
guards del índice, metadata, documentos y recuperación propios de cada verbo
siguen siendo obligatorios. No se elimina una guarda del verbo por haber enviado
un token coincidente.
