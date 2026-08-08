package com.ezevillo.gitreview.domain

/**
 * Depth-1 lock for mutations: a second call while busy is discarded, not queued.
 */
class MutationLock {
    companion object {
        const val DISCARD_REASON: String = "Another operation is already in progress"
    }

    @Volatile
    private var busy: Boolean = false
    private val busyListeners = mutableSetOf<(Boolean) -> Unit>()
    private val discardListeners = mutableSetOf<(String) -> Unit>()

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
     */
    fun <T> run(fn: () -> T): T? {
        if (busy) {
            discardListeners.forEach { it(DISCARD_REASON) }
            return null
        }
        setBusy(true)
        return try {
            fn()
        } finally {
            setBusy(false)
        }
    }

    private fun setBusy(value: Boolean) {
        busy = value
        busyListeners.forEach { it(value) }
    }
}
