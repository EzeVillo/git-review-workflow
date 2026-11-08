package com.ezevillo.gitreview.host

/** Coalesces observations around mutations; it never caches product state. */
class RefreshGate {
    private var busy = false
    private var pending = false
    private var reading = false

    @Synchronized fun request() { pending = true }
    @Synchronized fun mutationChanged(value: Boolean) { busy = value }
    /** Only signals received before this authoritative read are covered by it. */
    @Synchronized fun primaryStarting() { pending = false }
    @Synchronized fun tryStart(): Boolean {
        if (busy || reading || !pending) return false
        pending = false
        reading = true
        return true
    }
    @Synchronized fun finished() { reading = false }
}
