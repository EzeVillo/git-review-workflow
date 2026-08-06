/**
 * Ofertas de lectura del asistente de start (008-start-layout-offers).
 * Funciones puras: el wizard las usa para armar el QuickPick y el argv;
 * la CLI es la única fuente de viabilidad (nunca se adivina walk/keys).
 */

import {OfferId, OfferRank, ReadingOffer} from "../cli/configPorcelain";
import {ReviewLayout, ReviewRange, ReviewSource} from "./reviewIntent";

/** Fallback cuando la CLI no emite `offer` (pre-008 o soft-skip sin tip). */
export const FALLBACK_OFFERS: readonly ReadingOffer[] = [
    {id: "step", rank: "available"},
    {id: "whole", rank: "available"},
];

export interface LayoutPickItem {
    label: string;
    description: string;
    layout: ReviewLayout;
}

const OFFER_META: Record<
    OfferId,
    {label: string; description: string; layout: ReviewLayout}
> = {
    walk: {
        label: "Walkthrough",
        description: "curated reading order from the PR",
        layout: "walk",
    },
    keys: {
        label: "Walkthrough — keys only",
        description: "only entries marked key",
        layout: "keys",
    },
    step: {
        label: "Commit by commit",
        description: "one commit at a time (--step)",
        layout: "step",
    },
    whole: {
        label: "Whole diff",
        description: "entire diff at once",
        layout: "whole",
    },
};

/** Orden estable del contrato cuando no hay recommended que reordene. */
const OFFER_ORDER: OfferId[] = ["walk", "keys", "step", "whole"];

/**
 * Ofertas efectivas: las de la CLI, o fallback whole+step sin recommended.
 */
export function effectiveOffers(offers: readonly ReadingOffer[] | undefined): ReadingOffer[] {
    if (offers === undefined || offers.length === 0) {
        return [...FALLBACK_OFFERS];
    }
    return [...offers];
}

/**
 * QuickPick items: recommended primero; resto en orden del contrato.
 * Nunca inventa ids que no vengan en `offers` (salvo vía effectiveOffers).
 */
export function buildLayoutItems(offers: readonly ReadingOffer[] | undefined): LayoutPickItem[] {
    const list = effectiveOffers(offers);
    const byId = new Map<OfferId, OfferRank>();
    for (const o of list) {
        byId.set(o.id, o.rank);
    }

    const ordered: OfferId[] = [];
    for (const id of OFFER_ORDER) {
        if (byId.has(id) && byId.get(id) === "recommended") {
            ordered.push(id);
        }
    }
    for (const id of OFFER_ORDER) {
        if (byId.has(id) && byId.get(id) !== "recommended") {
            ordered.push(id);
        }
    }

    return ordered.map((id) => {
        const meta = OFFER_META[id];
        const rank = byId.get(id) ?? "available";
        const description =
            rank === "recommended" ? `${meta.description} (recommended)` : meta.description;
        const label = rank === "recommended" ? `${meta.label} (recommended)` : meta.label;
        return {label, description, layout: meta.layout};
    });
}

export function layoutSummary(layout: ReviewLayout): string {
    switch (layout) {
        case "walk":
            return "as a walkthrough";
        case "keys":
            return "keys only";
        case "step":
            return "commit by commit";
        case "whole":
            return "as the whole diff";
        default: {
            const _exhaustive: never = layout;
            return _exhaustive;
        }
    }
}

/**
 * Flags de `config --porcelain` para el contexto de ofertas (sin la rama ni
 * `--porcelain` ni `--`). network: false en el invocador.
 */
export function offerConfigFlags(source: ReviewSource, range: ReviewRange): string[] {
    const flags: string[] = [];
    if (source === "local") {
        flags.push("--local");
    } else if (source === "offline") {
        flags.push("--offline");
    }
    if (range === "delta") {
        flags.push("--delta");
    }
    return flags;
}
