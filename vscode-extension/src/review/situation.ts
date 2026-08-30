/**
 * `Situation`: el resultado de una invocación. Módulo sin dependencia de
 * `vscode`: es lógica pura, testeable sin host.
 */
export type Situation =
    "review"
    | "no-review"
    | "out-of-range"
    | "error"
    | "cli-missing"
    | "cli-outdated"
    | "finish-conflict"
    | "finish-pending";

/**
 * Mapea el exit code de `status --porcelain` a `Situation`. Un exit code
 * desconocido (`>3`, o cualquier otro valor incluido `1`) se trata siempre
 * como `error`, nunca como `review`.
 */
export function situationForExitCode(exitCode: number | null): Situation {
    switch (exitCode) {
        case 0:
            return "review";
        case 2:
            return "no-review";
        case 3:
            return "out-of-range";
        default:
            return "error";
    }
}

/**
 * `situationForExitCode` ampliado con el registro `finish`
 * (contracts/finish-state.md): `finish-conflict` gana siempre sobre `review`,
 * y `finish-pending` sobre `no-review` — nunca al revés, y nunca sobre
 * ninguna otra situación (`out-of-range`/`error`/`cli-*` no cambian, aunque el
 * inventario trajera un cierre pendiente de OTRA review). `hasFinishConflict`
 * viene de parsear el registro `finish` de `status --porcelain` (sólo posible
 * con exit `0`); `hasFinishPending` viene de si el inventario de
 * `list --porcelain` trae al menos una fila `finish … pending` (sólo
 * relevante con exit `2`, donde el panel ya invoca `list` para el estado vacío).
 */
export function situationFor(
    exitCode: number | null,
    hasFinishConflict: boolean,
    hasFinishPending: boolean
): Situation {
    const base = situationForExitCode(exitCode);
    if (base === "review" && hasFinishConflict) {
        return "finish-conflict";
    }
    if (base === "no-review" && hasFinishPending) {
        return "finish-pending";
    }
    return base;
}

/**
 * `true` para las dos situaciones donde `ReviewState.state` queda poblado y es
 * seguro leer la review en curso o salir de ella del todo: `review` y
 * `finish-conflict` — un cierre trabado sigue dejando la review legible; lo
 * único que no corresponde es *navegarla*.
 * Usada por los comandos de sólo lectura (`openEntry`/`openChange`/
 * `openAllChanges`/`showWhy`/`goToEntry`) y por `abortReview` — tirar la
 * review entera es uno de los tres caminos que contracts/finish-state.md
 * documenta para resolver un cierre trabado, y `bin/git-review-verbs/abort`
 * no tiene ningún guard sobre `reviewundohead` que lo bloquee.
 *
 * La navegación (`next`/`prev`) NO pasa por acá: sigue bloqueada en sus tres
 * capas propias (el panel retira `renderNavRow`, `navigate.ts` exige
 * `situation === "review"`, y la paleta filtra por lo mismo) — ninguna de
 * las tres cambia con este helper.
 */
export function isReviewReadable(situation: Situation): boolean {
    return situation === "review" || situation === "finish-conflict";
}
