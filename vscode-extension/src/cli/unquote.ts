/**
 * Deshace el citado estilo C que git aplica a un path cuando contiene `"` o
 * `\` (con core.quotePath=false). Ver data-model.md § PathRef y research.md
 * Decisión 8. Operación unidireccional: nunca se re-cita el resultado.
 */
export function unquotePath(raw: string): string {
    if (!raw.startsWith('"') || !raw.endsWith('"') || raw.length < 2) {
        return raw;
    }

    const inner = raw.slice(1, -1);
    const chunks: Buffer[] = [];
    let octalRun: number[] = [];

    const flushOctal = () => {
        if (octalRun.length > 0) {
            chunks.push(Buffer.from(octalRun));
            octalRun = [];
        }
    };

    let i = 0;
    while (i < inner.length) {
        const ch = inner[i];
        if (ch === "\\" && i + 1 < inner.length) {
            const next = inner[i + 1];
            if (next >= "0" && next <= "7") {
                const octalDigits = inner.slice(i + 1, i + 4);
                octalRun.push(parseInt(octalDigits, 8) & 0xff);
                i += 4;
                continue;
            }
            flushOctal();
            let decoded: string;
            switch (next) {
                case "\\":
                    decoded = "\\";
                    break;
                case '"':
                    decoded = '"';
                    break;
                case "a":
                    decoded = "\x07";
                    break;
                case "b":
                    decoded = "\b";
                    break;
                case "f":
                    decoded = "\f";
                    break;
                case "n":
                    decoded = "\n";
                    break;
                case "r":
                    decoded = "\r";
                    break;
                case "t":
                    decoded = "\t";
                    break;
                case "v":
                    decoded = "\v";
                    break;
                default:
                    decoded = next;
                    break;
            }
            chunks.push(Buffer.from(decoded, "utf8"));
            i += 2;
            continue;
        }

        flushOctal();
        const codePoint = inner.codePointAt(i);
        const char = codePoint !== undefined ? String.fromCodePoint(codePoint) : ch;
        chunks.push(Buffer.from(char, "utf8"));
        i += char.length;
    }
    flushOctal();

    return Buffer.concat(chunks).toString("utf8");
}

export interface PathRef {
    /** Lo único que vuelve a la CLI (`status --why <raw>`). */
    raw: string;
    /** Lo único que ve el usuario; también base del Uri. */
    display: string;
}

export function toPathRef(raw: string): PathRef {
    return {raw, display: unquotePath(raw)};
}
