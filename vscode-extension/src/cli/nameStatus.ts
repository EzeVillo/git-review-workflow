/**
 * Un archivo tocado por un commit, con sus dos lados del diff resueltos.
 *
 * Los lados son `undefined` cuando el archivo *no existe* de ese lado: no hay
 * blob que pedirle a git, y pedirlo igual es un error (ver `parseNameStatus`).
 */
export interface CommitChange {
    /** Path que identifica al archivo; el que tenía antes, si el commit lo elimina. */
    path: string;
    /** Path en el árbol anterior — `undefined` cuando el commit lo agrega. */
    before: string | undefined;
    /** Path en el árbol posterior — `undefined` cuando el commit lo elimina. */
    after: string | undefined;
}

/**
 * Parsea la salida de `git diff-tree -z --name-status`: campos separados por
 * NUL, cada registro un código de status seguido de un path (dos en renames y
 * copias). Con `-z` git nunca cita los paths, así que salen literales y no
 * pasan por `unquotePath`.
 *
 * Lo que importa del status es de qué lado existe el archivo. Un commit que
 * agrega un archivo no tiene lado izquierdo, y uno que lo elimina no tiene
 * derecho: pedirle a la extensión de git el blob del lado que falta no es
 * inofensivo — falla con `FileNotFound` y el host lo escupe como `Unable to
 * read file 'git:...'`.
 *
 * Los renames y las copias (`R`/`C`) sólo aparecen si alguien pasa `-M`/`-C`
 * —`diff-tree` es plumbing y no mira `diff.renames`—, pero se parsean igual:
 * traen dos paths, y tratarlos como uno solo desincronizaría el resto de la
 * lista, no sólo ese registro.
 */
export function parseNameStatus(output: string): CommitChange[] {
    // El único campo vacío es el que deja el NUL final; ni los status ni los
    // paths pueden serlo.
    const fields = output.split("\0").filter((field) => field.length > 0);
    const changes: CommitChange[] = [];

    let i = 0;
    while (i < fields.length) {
        const code = fields[i][0];
        if (code === "R" || code === "C") {
            const from = fields[i + 1];
            const to = fields[i + 2];
            if (from === undefined || to === undefined) {
                break;
            }
            changes.push({path: to, before: from, after: to});
            i += 3;
            continue;
        }

        const path = fields[i + 1];
        if (path === undefined) {
            break;
        }
        changes.push({
            path,
            before: code === "A" ? undefined : path,
            after: code === "D" ? undefined : path,
        });
        i += 2;
    }

    return changes;
}
