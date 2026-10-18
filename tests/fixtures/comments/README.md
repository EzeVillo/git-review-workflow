# Fixtures de comentarios

Los `.md` de este directorio son datos, no documentación a normalizar. La regla
`-text` de `.gitattributes` conserva sus bytes también en Windows. No regenerar
los esperados con el parser o renumerador del producto.

| Fuente | Esperado | Propósito |
|--------|----------|-----------|
| `freeform.md` | `freeform.expected.md` | Preámbulo, listas, citas, encabezados internos, ordinales repetidos y etiqueta vacía |
| `hundred.md` | `hundred.expected.md` | Cien cuerpos distintos, orden físico, huecos y números repetidos |
| `bom-crlf.md` | `bom-crlf.expected.md` | BOM UTF-8 y CRLF en todas las líneas |
| `mixed-eol.md` | `mixed-eol.expected.md` | LF/CRLF intercalados, CR literal y EOF sin LF |
| `no-final-lf.md` | `no-final-lf.expected.md` | Último cuerpo sin LF final |
| `fences-html.md` | `fences-html.expected.md` | Backticks, tildes, citas, indentación y comentarios HTML |
| `paths-references.md` | `paths-references.expected.md` | OID SHA-1/SHA-256, claves futuras y paths codificados |
| `empty.md` | `empty.expected.md` | Archivo existente de cero bytes |
| `open-fence.md` | `open-fence.expected.md` | Fence sin cierre; el resto sigue siendo código |
| `open-html.md` | — | HTML sin cierre: rechazo de reescritura |

Los números de fuente no definen el orden esperado. Las parejas se escribieron
como datos independientes con los cuerpos literales compartidos; ninguna usa
funciones del producto. Los OID ilustrativos no prometen objetos disponibles.
Los tests históricos construyen OID reales en sus repositorios temporales.
