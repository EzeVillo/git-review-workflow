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

/**
 * Elegir `draft` no es elegir una forma distinta de leer: es escribir el orden
 * que después se lee como walkthrough. Por eso el ítem lleva igual su `layout`
 * —el que quedaría si el borrador se completa— y `draft` marca el desvío por el
 * bucle de armado antes de llegar a start (contracts/client-draft-flow.md).
 */
export type DraftStep = "create" | "resume" | "update";

export interface LayoutPickItem {
    label: string;
    description: string;
    layout: ReviewLayout;
    draft?: DraftStep;
}

const OFFER_META: Record<
    OfferId,
    {label: string; description: string; layout: ReviewLayout; draft?: DraftStep}
> = {
    walk: {
        label: "Walkthrough",
        description: "guided reading order from the PR",
        layout: "walk",
    },
    keys: {
        label: "Walkthrough — keys only",
        description: "only entries marked key",
        layout: "keys",
    },
    // Sin la palabra "walkthrough" como si fuera un término conocido: estas dos
    // son las únicas ofertas que no eligen una forma de leer sino que arman la
    // que el PR no trae, y quien las lee todavía no sabe qué es un walkthrough.
    // Dicen qué se obtiene y cuál es la alternativa. Byte por byte iguales en
    // los tres clientes (contracts/client-draft-panel.md § La copy de la oferta).
    draft: {
        label: "Build a reading order first",
        description: "nobody wrote one for this PR; otherwise you read the whole diff",
        layout: "walk",
        draft: "create",
    },
    "draft-resume": {
        label: "Finish the reading order you started",
        description: "pick up the one you left half-written",
        layout: "walk",
        draft: "resume",
    },
    // La CLI manda ésta en lugar de `draft-resume` cuando el borrador quedó
    // desfasado del rango. Antes las dos situaciones llegaban indistinguibles y
    // el asistente preguntaba con un modal cuál era — o sea le pedía al revisor
    // un dato que sólo la CLI tiene, y cuando la respuesta era "no se movió
    // nada" la reconciliación era un no-op que terminaba en una fila sin
    // Validate and start.
    "draft-update": {
        label: "Update the reading order you wrote",
        description: "the PR moved on; keeps the whys whose files are still in range",
        layout: "walk",
        draft: "update",
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
const OFFER_ORDER: OfferId[] = ["walk", "keys", "draft", "draft-resume", "draft-update", "step", "whole"];

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
/**
 * Cuál de las dos filas del borrador se dibuja ya no se decide acá: la CLI manda
 * `draft-resume` o `draft-update` y cada una trae su copy fija.
 *
 * Antes esto miraba el `state` del registro `draft` para reescribir la copy de
 * `draft-resume` cuando la review ya había cerrado. Ese campo contesta "¿ya se
 * leyó este orden?", no "¿sigue cubriendo el rango?", así que una rama que
 * avanzó después de su review y una que no se movió llegaban con el MISMO
 * `reviewed` — y la fila terminaba ofreciendo reconciliar un orden que no tenía
 * nada que reconciliar.
 */
export function buildLayoutItems(
    offers: readonly ReadingOffer[] | undefined
): LayoutPickItem[] {
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
        const item: LayoutPickItem = {label, description, layout: meta.layout};
        if (meta.draft !== undefined) {
            item.draft = meta.draft;
        }
        return item;
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
