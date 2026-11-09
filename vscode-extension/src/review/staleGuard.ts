import type {ReviewState} from "./state";
import type {Situation} from "./situation";

/**
 * Testigo del estado en el momento en que se arma un diálogo con confirmación.
 * `branch`/`tip` ausentes cuando no hay review activa al capturar — sigue
 * siendo un testigo válido, sólo que de "no había nada".
 */
export interface StateToken {
    continueGuard?: string;
    guard?: string;
    branch?: string;
    tip?: string;
    situation: Situation;
}

export function captureToken(state: ReviewState): StateToken {
    return {
        continueGuard: state.continueGuard,
        guard: state.guard,
        branch: state.state?.branch,
        tip: state.state?.tip,
        situation: state.situation,
    };
}

/**
 * Revalida el testigo contra el estado leído justo antes de invocar. Una
 * comparación de tres strings sobre datos que el refresco ya trae — no cuesta
 * una invocación extra.
 */
export function tokenStillValid(token: StateToken, state: ReviewState): boolean {
    return (
        token.continueGuard === state.continueGuard && token.situation === state.situation &&
        token.branch === state.state?.branch &&
        token.tip === state.state?.tip && token.guard === state.guard
    );
}

export function parseStateGuard(output: string): string | undefined {
    const guards = output.split("\n").map(line => line.replace(/\r$/, ""))
        .filter(line => line.startsWith("guard\t")).map(line => line.slice(6));
    return guards.length === 1 && /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(guards[0]) ? guards[0] : undefined;
}
