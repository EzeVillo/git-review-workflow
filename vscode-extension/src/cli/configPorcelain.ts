/**
 * Tokeniza `git review config --porcelain` (contracts/config-porcelain.md):
 * mismo formato porcelain v1 que `porcelain.ts`, mismo tokenizador línea por
 * línea (split por tab, primer campo = etiqueta), y mismas reglas — etiquetas
 * desconocidas y campos extra al final de un registro conocido se ignoran
 * (FR-003). Existe como módulo aparte porque el registro que reporta (config
 * efectiva + ramas candidatas) no tiene nada que ver con el de una review
 * activa: es la respuesta a "cómo se armaría", no a "cómo está armada"
 * (data-model.md § EffectiveConfig).
 */

export interface EffectiveConfig {
    /** Ausente = sin configurar, un estado normal (un review completo fallaría pidiéndola). */
    base?: string;
    /** Siempre presente: `origin` cuando no hay nada configurado, ya resuelto por la CLI. */
    remote: string;
}

export interface CandidateBranch {
    /** Sin el prefijo de namespace: el valor que vuelve a la CLI como argumento. */
    name: string;
    origin: "remote" | "local";
    current: boolean;
}

export interface ConfigPorcelainResult {
    config: EffectiveConfig;
    /** En el orden de `git for-each-ref` (lexicográfico); duplicados (misma rama, dos orígenes) esperados, nunca fusionados. */
    candidates: CandidateBranch[];
    /** Sólo cuando la invocación nombró una rama Y esa rama tiene un tip reviewed previo (FR-015). */
    delta?: { name: string; tip: string };
}

function toBool(field: string | undefined): boolean {
    return field === "1";
}

/**
 * Parsea `config<TAB>clave<TAB>valor`, `candidate<TAB>name<TAB>origin<TAB>current`
 * y `delta<TAB>name<TAB>tip`. `remote` cae a "origin" sólo como último recurso
 * defensivo: el contrato lo emite siempre, así que su ausencia implica una CLI
 * rota, no un estado válido a distinguir (a diferencia de `base`, que sí puede
 * estar legítimamente ausente).
 */
export function parseConfigPorcelain(stdout: string): ConfigPorcelainResult {
    let base: string | undefined;
    let remote: string | undefined;
    const candidates: CandidateBranch[] = [];
    let delta: { name: string; tip: string } | undefined;

    for (const line of stdout.split("\n")) {
        if (line.length === 0) {
            continue;
        }
        const fields = line.split("\t");
        switch (fields[0]) {
            case "config": {
                const key = fields[1];
                const value = fields[2];
                if (value === undefined) {
                    break;
                }
                if (key === "base") {
                    base = value;
                } else if (key === "remote") {
                    remote = value;
                }
                break;
            }
            case "candidate": {
                const name = fields[1];
                const origin = fields[2];
                if (name === undefined || (origin !== "remote" && origin !== "local")) {
                    break;
                }
                candidates.push({name, origin, current: toBool(fields[3])});
                break;
            }
            case "delta": {
                const name = fields[1];
                const tip = fields[2];
                if (name !== undefined && tip !== undefined) {
                    delta = {name, tip};
                }
                break;
            }
            default:
                // Etiqueta desconocida: se ignora (FR-003).
                break;
        }
    }

    const config: EffectiveConfig = {remote: remote ?? "origin"};
    if (base !== undefined) {
        config.base = base;
    }
    const result: ConfigPorcelainResult = {config, candidates};
    if (delta) {
        result.delta = delta;
    }
    return result;
}
