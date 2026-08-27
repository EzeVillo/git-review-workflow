// User-facing copy that is shared with the other clients, byte for byte.
//
// The JetBrains plugin and the Visual Studio extension have carried a UserCopy
// module for a while; this one is the extension's, and it exists for the same
// reason theirs do: scripts/check-client-product-surface.mjs compares the three
// against one canonical, and a string embedded in a command module would force
// that check to match against code rather than against a constant — which is
// fragile precisely when the text changes, the one thing the check exists to
// catch.

/**
 * Lo que se dice cuando el testigo de estado (staleGuard.ts) rechaza una
 * mutación porque el repositorio cambió entre la confirmación y la invocación.
 * **Uno solo para los ocho comandos**, y antes eran catorce literales.
 *
 * Las catorce variantes decían la misma cosa con el verbo cambiado — "nothing
 * was finished", "nothing was saved", "nothing was undone" —, y ese verbo no es
 * información: es el botón que el revisor acaba de apretar, que todavía tiene
 * bajo el cursor. Lo único que no puede deducir es POR QUÉ no pasó nada, y eso
 * es idéntico en los catorce casos.
 *
 * No lleva "try again": el panel ya se refrescó solo, así que el estado que se
 * ve al leer el mensaje es el nuevo. Decir que reintente sería pedirle que
 * repita una decisión que quizá el estado nuevo ya volvió innecesaria.
 *
 * Byte for byte identical to UserCopy.kt and UserCopy.cs.
 */
export const STALE = "The repository changed while you were deciding, so nothing happened.";

/**
 * What "Copy for agent" puts on the clipboard for one draft row.
 *
 * A pointer, not a prompt: the brief lives inside the file, in the instruction
 * block at the top, and repeating it here would give an agent two sources for
 * the same rules. `path` is the absolute path the CLI reported for that row —
 * never one the client built — so the text is enough on its own for an agent to
 * find the file.
 *
 * Byte for byte identical to UserCopy.kt and UserCopy.cs. Nothing here names a
 * model, a service or an assistant: copying is copying.
 */
export function draftAgentPrompt(path: string): string {
	return (
		`Fill in the reading order at ${path}. The instructions are inside the file, ` +
		"in the comment at the top. Do not change the file list or the numbering rules."
	);
}

/**
 * What "Copy for agent" puts on the clipboard for the author's own walkthrough.
 *
 * A pointer, like the draft one, and for the same reason. Two sentences differ,
 * and both are about the situation rather than the format: the file usually
 * already holds finished prose (a walkthrough is written when the PR is done,
 * and then the PR keeps moving), so the one damaging thing an agent can do here
 * is rewrite it whole. Saying "fill in the reading order" over a full file is
 * an instruction to start over, and it would undo exactly what updating in
 * place exists to preserve.
 *
 * Byte for byte identical to UserCopy.kt and UserCopy.cs.
 */
export function walkthroughAgentPrompt(path: string): string {
	return (
		`Update the reading order at ${path}. The instructions are inside the file, ` +
		"in the comment at the top. Entries that already have a number and a why are " +
		"finished: leave them as they are, and fill in only the ones marked \"## ?.\"."
	);
}

/**
 * The choice between reconciling a walkthrough and starting it over, asked
 * BEFORE the verb runs.
 *
 * It used to hang off the CLI FAILING: init ran, and when it died because the
 * file was already there, that is where the three clients offered to overwrite.
 * Since init updates instead of refusing, that path stopped existing — and with
 * it the only way to reach --force from a panel. So the question goes in front.
 *
 * Byte for byte identical to UserCopy.kt and UserCopy.cs.
 */
export const WALKTHROUGH_EXISTS_TITLE = "This branch already has a walkthrough.";
export const WALKTHROUGH_EXISTS_DETAIL =
	"Update keeps everything you already wrote for files that are still in the PR, and adds the ones that are new.\n\n" +
	"Start over replaces it with a blank list. The file is committed to the PR, so git checkout -- .review/walkthrough.md brings the old one back.";
/**
 * Del lado del REVISOR no hay par equivalente, y la asimetría es deliberada.
 *
 * Hubo uno: un modal que, sobre cualquier borrador cuya review ya había
 * cerrado, preguntaba si reconciliar o empezar de cero. Preguntaba porque el
 * asistente no podía saber cuál de las dos cosas hacía falta —el `state` del
 * registro `draft` dice si el orden ya se leyó, no si sigue cubriendo el
 * rango—, así que le pasaba la duda al revisor. Ahora la contesta la CLI, que
 * es la que tiene los dos tips, ofreciendo `draft-update` sólo cuando hay algo
 * que reconciliar; sin pregunta, no hay modal.
 *
 * Y empezar de cero no se repone acá: del lado del autor el archivo está
 * trackeado y `git checkout --` lo devuelve, del lado del revisor vive fuera de
 * git y no hay vuelta atrás. Un botón para eso no va en un paso por el que se
 * pasa de largo; va en Discard, que confirma y cuyo sujeto es el archivo.
 */
/**
 * El ÚLTIMO paso del asistente de inicio, y por eso lleva la rama: elegir una
 * forma de lectura ahí ya arranca la review.
 *
 * La frase es la que decía la pantalla de confirmación que este paso reemplaza
 * ("Start reviewing feature/x, as a walkthrough?"). Esa pantalla repetía las
 * cuatro respuestas que el asistente ya tenía y agregaba el comando, sobre un
 * verbo que no destruye nada — `start` se niega solo con el árbol sucio, y una
 * review empezada se cancela con un botón del panel. Un cartel que aparece
 * siempre deja de leerse, y entonces tampoco se lee el que importa.
 *
 * Byte for byte identical to UserCopy.kt and UserCopy.cs.
 */
export function startLayoutTitle(branch: string): string {
	return `Start reviewing ${branch} — how do you want to read it?`;
}

export const WALKTHROUGH_UPDATE_BUTTON = "Update";
export const WALKTHROUGH_START_OVER_BUTTON = "Start over";
