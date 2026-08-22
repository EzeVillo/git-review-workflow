package com.ezevillo.gitreview.domain

/**
 * Qué filas muestra un picker filtrado, y cuál queda elegida — la parte del
 * diálogo que se puede preguntar sin levantar la plataforma.
 *
 * Una fila nunca *es* su posición visible: lo que se devuelve es el índice en el
 * array del llamador, así que filtrar no puede cambiar lo que significa una
 * selección. La fila de texto libre es la única sin índice ahí, y por eso lleva
 * [TYPED].
 */
object PickerRows {
    /** Índice de la fila de texto libre, que no está en ninguna lista. */
    const val TYPED = -2

    /** Ninguna fila elegida. */
    const val NONE = -1

    /**
     * Los índices de [options] que sobreviven a [needle], en orden. Con [freeText]
     * y un needle que no es ya una opción, la fila de texto libre va primera.
     */
    fun rows(options: List<String>, needle: String, freeText: Boolean): List<Int> {
        val trimmed = needle.trim()
        val result = mutableListOf<Int>()
        if (freeText && trimmed.isNotEmpty() && !options.contains(trimmed)) {
            result.add(TYPED)
        }
        options.forEachIndexed { index, label ->
            if (trimmed.isEmpty() || label.contains(trimmed, ignoreCase = true)) {
                result.add(index)
            }
        }
        return result
    }

    /**
     * Qué fila visible queda elegida, dado [keep] (el índice en `options` que
     * estaba elegido antes de filtrar, o null).
     *
     * Con fila de texto libre delante es ella la que gana: preservar la selección
     * anterior dejaba al revisor tipeando un SHA con una rama seleccionada, y
     * aceptar mandaba la rama. Para elegir de la lista se baja una fila, que es
     * visible; que Enter envíe otra cosa, no.
     */
    fun selection(rows: List<Int>, keep: Int?): Int = when {
        rows.isEmpty() -> NONE
        rows.first() == TYPED -> 0
        keep != null && keep != TYPED && rows.contains(keep) -> rows.indexOf(keep)
        else -> 0
    }
}
