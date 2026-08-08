package com.ezevillo.gitreview.domain

import java.util.concurrent.CopyOnWriteArraySet

/**
 * Depth-1 lock for mutations: a second call while busy is discarded, not queued.
 */
class MutationLock {
    companion object {
        const val DISCARD_REASON: String = "Another operation is already in progress"
    }

    @Volatile
    private var busy: Boolean = false
    // Mutations run on a pooled thread while the panel reads busy from the EDT.
    private val busyListeners = CopyOnWriteArraySet<(Boolean) -> Unit>()
    private val discardListeners = CopyOnWriteArraySet<(String) -> Unit>()

    val isBusy: Boolean get() = busy

    fun onDidChangeBusy(listener: (Boolean) -> Unit): () -> Unit {
        busyListeners.add(listener)
        return { busyListeners.remove(listener) }
    }

    fun onDidDiscard(listener: (String) -> Unit): () -> Unit {
        discardListeners.add(listener)
        return { discardListeners.remove(listener) }
    }

    /**
     * Runs [fn] if not busy. Returns the result, or `null` if discarded.
     * Synchronous API: callers wrap async work inside [fn].
     *
     * Claiming the lock is atomic — callers arrive from pooled threads, so the
     * check and the claim cannot be two steps. The monitor is reentrant, so a
     * nested call on the same thread still sees `busy` and is discarded.
     */
    fun <T> run(fn: () -> T): T? {
        synchronized(this) {
            if (busy) {
                discardListeners.forEach { it(DISCARD_REASON) }
                return null
            }
            setBusy(true)
        }
        return try {
            fn()
        } finally {
            synchronized(this) { setBusy(false) }
        }
    }

    private fun setBusy(value: Boolean) {
        busy = value
        busyListeners.forEach { it(value) }
    }
}
