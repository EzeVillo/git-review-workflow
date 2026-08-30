/**
 * Cola serializada de profundidad 1 para invocaciones mutantes (`next`/`prev`):
 * una segunda invocación mientras la primera está en vuelo se descarta, no se
 * encola — encolarla ejecutaría una intención basada en una posición que ya no
 * es la vigente. Publica `busy` por `onDidChangeBusy` (`extension.ts` lo
 * traduce a la context key `gitReview.busy`) y el descarte por `onDidDiscard`,
 * para que la paleta de comandos o un atajo se enteren sin silencio.
 *
 * Sin dependencia de `vscode`: es lógica pura, testeable sin host.
 */
// Fijo, no derivado de la operación en vuelo: quien escucha no necesita saber
// cuál era, sólo que la suya no corrió.
const DISCARD_REASON = "Another operation is already in progress";

export class MutationLock {
    private busy = false;
    private readonly busyListeners = new Set<(busy: boolean) => void>();
    private readonly discardListeners = new Set<(reason: string) => void>();

    get isBusy(): boolean {
        return this.busy;
    }

    onDidChangeBusy(listener: (busy: boolean) => void): { dispose(): void } {
        this.busyListeners.add(listener);
        return {dispose: () => this.busyListeners.delete(listener)};
    }

    /**
     * Se dispara cuando `run()` descarta una llamada por haber otra en vuelo:
     * la señal que falta porque `gitReview.busy` apaga los controles del
     * panel pero no cubre la paleta de comandos ni un atajo de teclado.
     */
    onDidDiscard(listener: (reason: string) => void): { dispose(): void } {
        this.discardListeners.add(listener);
        return {dispose: () => this.discardListeners.delete(listener)};
    }

    /**
     * Corre `fn` si no hay nada en vuelo. Devuelve el resultado, o `undefined`
     * si se descartó porque ya había una mutación corriendo.
     */
    async run<T>(fn: () => Promise<T>): Promise<T | undefined> {
        if (this.busy) {
            for (const listener of this.discardListeners) {
                listener(DISCARD_REASON);
            }
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
        for (const listener of this.busyListeners) {
            listener(value);
        }
    }
}
