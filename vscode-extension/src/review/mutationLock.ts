/**
 * Cola serializada de profundidad 1 para invocaciones mutantes (`next`/
 * `prev`). Una segunda invocación mientras la primera está en vuelo se
 * descarta, no se encola — encolarla ejecutaría una intención basada en una
 * posición que ya no es la vigente (research.md Decisión 9, FR-020).
 * Publica `busy` a través de `onDidChangeBusy`; `extension.ts` traduce eso a
 * la context key `gitReview.busy`.
 *
 * Sin dependencia de `vscode` a propósito: es lógica pura, testeable sin
 * host (T035).
 */
export class MutationLock {
    private busy = false;
    private readonly listeners = new Set<(busy: boolean) => void>();

    get isBusy(): boolean {
        return this.busy;
    }

    onDidChangeBusy(listener: (busy: boolean) => void): { dispose(): void } {
        this.listeners.add(listener);
        return {dispose: () => this.listeners.delete(listener)};
    }

    /**
     * Corre `fn` si no hay nada en vuelo. Devuelve el resultado, o `undefined`
     * si se descartó porque ya había una mutación corriendo.
     */
    async run<T>(fn: () => Promise<T>): Promise<T | undefined> {
        if (this.busy) {
            return undefined;
        }
        this.setBusy(true);
        try {
            return await fn();
        } finally {
            this.setBusy(false);
        }
    }

    private setBusy(value: boolean): void {
        this.busy = value;
        for (const listener of this.listeners) {
            listener(value);
        }
    }
}
