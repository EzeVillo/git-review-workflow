package com.ezevillo.gitreview.domain

/**
 * Undoes git C-style quoting applied when a path contains `"` or `\`
 * (`core.quotePath=false`). One-way: never re-quote the result.
 */
fun unquotePath(raw: String): String {
    if (!raw.startsWith('"') || !raw.endsWith('"') || raw.length < 2) {
        return raw
    }

    val inner = raw.substring(1, raw.length - 1)
    val chunks = ArrayList<ByteArray>()
    val octalRun = ArrayList<Int>()

    fun flushOctal() {
        if (octalRun.isNotEmpty()) {
            chunks.add(octalRun.map { it.toByte() }.toByteArray())
            octalRun.clear()
        }
    }

    var i = 0
    while (i < inner.length) {
        val ch = inner[i]
        if (ch == '\\' && i + 1 < inner.length) {
            val next = inner[i + 1]
            if (next in '0'..'7') {
                val end = minOf(i + 4, inner.length)
                val octalDigits = inner.substring(i + 1, end)
                // Match TS: take up to 3 octal digits after backslash
                val digits = buildString {
                    for (c in octalDigits) {
                        if (c in '0'..'7' && length < 3) append(c) else break
                    }
                }
                if (digits.isNotEmpty()) {
                    octalRun.add(digits.toInt(8) and 0xff)
                    i += 1 + digits.length
                    continue
                }
            }
            flushOctal()
            val decoded: String = when (next) {
                '\\' -> "\\"
                '"' -> "\""
                'a' -> "\u0007"
                'b' -> "\b"
                'f' -> "\u000c"
                'n' -> "\n"
                'r' -> "\r"
                't' -> "\t"
                'v' -> "\u000b"
                else -> next.toString()
            }
            chunks.add(decoded.toByteArray(Charsets.UTF_8))
            i += 2
            continue
        }

        flushOctal()
        val cp = inner.codePointAt(i)
        val char = String(Character.toChars(cp))
        chunks.add(char.toByteArray(Charsets.UTF_8))
        i += char.length
    }
    flushOctal()

    val total = chunks.sumOf { it.size }
    val out = ByteArray(total)
    var offset = 0
    for (c in chunks) {
        System.arraycopy(c, 0, out, offset, c.size)
        offset += c.size
    }
    return String(out, Charsets.UTF_8)
}

/** Path as emitted by porcelain (`raw`) vs UI/filesystem (`display`). */
data class PathRef(
    /** What goes back to the CLI (`status --why <raw>`). */
    val raw: String,
    /** What the user sees; also filesystem path base. */
    val display: String,
)

fun toPathRef(raw: String): PathRef = PathRef(raw = raw, display = unquotePath(raw))
