/**
 * Un solo root usable, como el cwd de la CLI: 0 → nada; 1 → ese; 2+ → nada
 * (no adivinar el primero). Multi-root ambiguo no es un picker: es "no hay
 * un cwd único en el que correr `git review`".
 *
 * Genérico y sin dependencia de `vscode` para poder unit-testearlo sin host.
 */
export function pickSoleTarget<T>(targets: readonly T[]): T | undefined {
    return targets.length === 1 ? targets[0] : undefined;
}
