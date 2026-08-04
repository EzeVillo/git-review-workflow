/**
 * Cola serializada de profundidad 1 para invocaciones mutantes (`next`/
 * `prev`). Una segunda invocación mientras la primera está en vuelo se
 * descarta, no se encola — encolarla ejecutaría una intención basada en una
 * posición que ya no es la vigente (research.md Decisión 9, FR-020).
 * Publica `busy` a través de `onDidChangeBusy`; `extension.ts` traduce eso a
 * la context key `gitReview.busy`. El descarte en sí avisa por
 * `onDidDiscard`, para que quien la disparó desde la paleta o un atajo se
 * entere sin silencio (research.md Decisión 7 de `005`, FR-036).
 *
 * Sin dependencia de `vscode` a propósito: es lógica pura, testeable sin
 * host (T035).
 */
// Motivo fijo, no derivado de la operación en vuelo: quien escucha (paleta de
// comandos, atajo) no tiene por qué saber cuál era esa operación, sólo que la
// suya no corrió (research.md Decisión 7, FR-036).
const DISCARD_REASON = "otra operación está en curso";

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
     * Se dispara cuando `run()` descarta una llamada por haber una mutación
     * en vuelo — la señal que le falta al descarte silencioso de `run()`
     * (FR-036): `gitReview.busy` ya apaga los controles del panel, pero no
     * cubre la paleta de comandos ni un atajo de teclado.
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
