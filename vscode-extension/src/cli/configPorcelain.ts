/**
 * Tokeniza `git review config --porcelain` (contracts/config-porcelain.md):
 * mismo formato porcelain v1 que `porcelain.ts`, mismo tokenizador línea por
 * línea (split por tab, primer campo = etiqueta), y mismas reglas — etiquetas
 * desconocidas y campos extra al final de un registro conocido se ignoran
 * (FR-003). Existe como módulo aparte porque el registro que reporta (config
 * efectiva + ramas candidatas) no tiene nada que ver con el de una review
 * activa: es la respuesta a "cómo se armaría", no a "cómo está armada"
 * (data-model.md § EffectiveConfig).
 *
 * 008: también parsea `offer` (formas de lectura viables para un tip/rango).
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

/** Eje del marker `--delta`: tip de origin/<rama> vs refs/heads/<rama>. */
export type DeltaOrigin = "remote" | "local";

export interface DeltaRecord {
    name: string;
    tip: string;
    origin: DeltaOrigin;
}

/** Forma de lectura viable reportada por la CLI (008). */
export type OfferId = "walk" | "keys" | "step" | "whole";
export type OfferRank = "recommended" | "available";

export interface ReadingOffer {
    id: OfferId;
    rank: OfferRank;
}

export interface ConfigPorcelainResult {
    config: EffectiveConfig;
    /** En el orden de `git for-each-ref` (lexicográfico); duplicados (misma rama, dos orígenes) esperados, nunca fusionados. */
    candidates: CandidateBranch[];
    /**
     * Sólo cuando la invocación nombró una rama Y hay al menos un tip reviewed
     * previo (FR-015). Cero, una o dos filas — remote y local son ejes disjuntos.
     */
    deltas?: DeltaRecord[];
    /**
     * Formas de lectura viables para el tip/rango del contexto (flags de
     * origen/rango). Ausente cuando la CLI no emitió ninguna (pre-008 o tip
     * no resoluble en soft-skip).
     */
    offers?: ReadingOffer[];
}

function toBool(field: string | undefined): boolean {
    return field === "1";
}

function parseOfferId(raw: string | undefined): OfferId | undefined {
    if (raw === "walk" || raw === "keys" || raw === "step" || raw === "whole") {
        return raw;
    }
    return undefined;
}

function parseOfferRank(raw: string | undefined): OfferRank | undefined {
    if (raw === "recommended" || raw === "available") {
        return raw;
    }
    return undefined;
}

/**
 * Parsea `config`, `candidate`, `delta` y `offer`. `remote` cae a "origin" sólo
 * como último recurso defensivo: el contrato lo emite siempre.
 */
export function parseConfigPorcelain(stdout: string): ConfigPorcelainResult {
    let base: string | undefined;
    let remote: string | undefined;
    const candidates: CandidateBranch[] = [];
    const deltas: DeltaRecord[] = [];
    const offers: ReadingOffer[] = [];

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
                const origin = fields[3];
                if (
                    name !== undefined &&
                    tip !== undefined &&
                    (origin === "remote" || origin === "local")
                ) {
                    deltas.push({name, tip, origin});
                }
                break;
            }
            case "offer": {
                const id = parseOfferId(fields[1]);
                const rank = parseOfferRank(fields[2]);
                if (id !== undefined && rank !== undefined) {
                    offers.push({id, rank});
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
    if (deltas.length > 0) {
        result.deltas = deltas;
    }
    if (offers.length > 0) {
        result.offers = offers;
    }
    return result;
}

/**
 * Marker `--delta` usable para un source de start: remote → fila remote;
 * local y offline → fila local (mismo marker en la CLI).
 */
export function deltaForSource(
    deltas: readonly DeltaRecord[] | undefined,
    source: "remote" | "local" | "offline"
): DeltaRecord | undefined {
    if (deltas === undefined || deltas.length === 0) {
        return undefined;
    }
    const origin: DeltaOrigin = source === "remote" ? "remote" : "local";
    return deltas.find((d) => d.origin === origin);
}
