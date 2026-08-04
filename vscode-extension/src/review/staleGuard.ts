import type {ReviewState} from "./state";
import type {Situation} from "./situation";

/**
 * Testigo del estado en el momento en que se arma un diálogo con confirmación
 * (data-model.md § `StateToken`, research.md Decisión 8, FR-038). `branch`/
 * `tip` ausentes cuando no hay review activa al capturar — sigue siendo un
 * testigo válido, sólo que de "no había nada".
 */
export interface StateToken {
    branch?: string;
    tip?: string;
    situation: Situation;
}

export function captureToken(state: ReviewState): StateToken {
    return {
        branch: state.state?.branch,
        tip: state.state?.tip,
        situation: state.situation,
    };
}

/**
 * Revalida el testigo contra el estado leído justo antes de invocar. Una
 * comparación de tres strings sobre datos que el refresco ya trae — no cuesta
 * una invocación extra (data-model.md § `StateToken`).
 */
export function tokenStillValid(token: StateToken, state: ReviewState): boolean {
    return (
        token.situation === state.situation &&
        token.branch === state.state?.branch &&
        token.tip === state.state?.tip
    );
}
