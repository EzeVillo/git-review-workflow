/** Versión mínima de la CLI que trae el contrato porcelain (research.md Decisión 1). */
export const MIN_CLI_VERSION = "0.8.0";

function parseVersion(version: string): [number, number, number] | undefined {
    const parts = version.trim().split(".");
    if (parts.length !== 3) {
        return undefined;
    }
    const nums = parts.map((p) => Number(p));
    if (nums.some((n) => !Number.isInteger(n) || n < 0)) {
        return undefined;
    }
    return [nums[0], nums[1], nums[2]];
}

/**
 * Compara dos versiones `X.Y.Z`. Devuelve negativo si `a < b`, positivo si
 * `a > b`, cero si son iguales. `undefined` si alguna no tiene formato
 * `X.Y.Z` con enteros — tratado por el llamador como "vieja"/"inválida".
 */
export function compareVersions(a: string, b: string): number | undefined {
    const va = parseVersion(a);
    const vb = parseVersion(b);
    if (!va || !vb) {
        return undefined;
    }
    for (let i = 0; i < 3; i++) {
        if (va[i] !== vb[i]) {
            return va[i] - vb[i];
        }
    }
    return 0;
}

/** `true` si `version` es una CLI vieja (< MIN_CLI_VERSION) o de formato inválido. */
export function isOutdated(version: string, minVersion: string = MIN_CLI_VERSION): boolean {
    const cmp = compareVersions(version, minVersion);
    return cmp === undefined || cmp < 0;
}
