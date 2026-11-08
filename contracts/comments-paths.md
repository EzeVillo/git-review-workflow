# Rutas de edición de la sesión activa

`git review comments paths --porcelain` consulta únicamente la custodia y las
rutas privadas Local y Shared de la sesión activa. No lee prosa, cuenta entradas,
calcula revisiones de documentos, resuelve identidad ni consulta historia.
`status --porcelain` anuncia `capability<TAB>comments-paths` durante una review.
No se infiere soporte del guard ni de la versión. La TUI no tiene buffers de
editor; los tres IDE negocian esta capacidad desde su lectura principal.

## Respuesta

```text
comments-paths<TAB>1<TAB><review-guard><TAB><session>
comments-path<TAB>local<TAB><encoded-path>
comments-path<TAB>shared<TAB><encoded-path>
comments-paths<TAB>complete
```

Son cuatro registros exactos en ese orden. El guard es el de la review mostrada,
no el de captura de Comments; el cliente exige coincidencia antes de guardar
ningún buffer. La sesión es un token hexadecimal de 40 o 64 caracteres. Las
rutas son las de la CLI, incluso si el documento está ausente. Usa el encoder
literal existente: `%25`, `%09`, `%0D`, `%0A`, `%3E` para porcentaje, tab, CR,
LF y `>`. Se decodifica una sola vez, sin tratar `+` como espacio. Un escape
desconocido, sesión inválida, fila ausente/duplicada o final faltante rechaza
la respuesta completa. No se presenta como ausencia de documentos.

Una review antigua sin sesión propietaria emite explícitamente:

```text
comments-paths<TAB>1<TAB><review-guard><TAB>legacy
comments-paths<TAB>complete
```

Sólo esa respuesta válida permite volver al inventario anterior. La pérdida de
claves con una preparación todavía reclamada se rechaza, no se trata como
legacy. Sin capacidad, el cliente usa directamente su consulta anterior.

## Custodia y uso

La consulta comparte `comments_preflight_branch`: valida propietario, tokens,
contexto, sesión y custodio y rechaza enlaces o rutas no regulares. Las cuatro
claves del manifest se leen juntas, sin perder campos vacíos ni interpretar
backslashes o tabs. Los duplicados se rechazan, incluso un contexto duplicado
vacío. Cada preflight de una mutación sigue releyendo config/gitdir al cruzar
sus límites de custodia; no se usa una snapshot anterior a la operación.

Los IDE mantienen el atajo de todos los documentos guardados. Con buffers
modificados o estado desconocido, sólo los cierres de una review activa pueden
usar la consulta acotada. Recuperación posterior a Finish y limpieza de ramas
conservan su inventario completo. Se guardan sólo buffers cuyas rutas coinciden;
no se crean documentos ni se guardan archivos de código u otras sesiones.

Una respuesta fallida, obsoleta o inválida impide continuar y refresca el panel.
La operación posterior conserva su guard y sus comprobaciones de custodia,
índice y recuperación. La consulta no es un lock ni una autorización persistente
para cambiar un documento. Código 0: respuesta completa; 1: uso/custodia/I/O;
2: fuera de una review activa. Sólo se acepta `--porcelain`; no admite --all,
--context ni destinos derivados del cliente. Las consultas no escriben objetos,
config, índice, documentos ni sesiones.
