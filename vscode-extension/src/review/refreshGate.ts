/** Coalesces observations around mutations without caching CLI state. */
export class RefreshGate {
    private busy = false;
    private pending = false;
    private reading = false;

    request(): void { this.pending = true; }
    mutationChanged(busy: boolean): void { this.busy = busy; }
    primaryStarting(): void { this.pending = false; }
    tryStart(): boolean {
        if (this.busy || this.reading || !this.pending) return false;
        this.pending = false;
        this.reading = true;
        return true;
    }
    finished(): void { this.reading = false; }
}
