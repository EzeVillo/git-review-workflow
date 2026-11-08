package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.PanelWhy
import com.ezevillo.gitreview.domain.StateRecord
import java.util.concurrent.atomic.AtomicReference

/** Couples completion and supersession atomically across pooled threads. */
internal class WhyReadState {
    data class Ticket(val owner: StateRecord?, val value: PanelWhy?)
    private val current = AtomicReference(Ticket(null, null))

    fun begin(owner: StateRecord?, value: PanelWhy?): Ticket = Ticket(owner, value).also { current.set(it) }
    fun complete(ticket: Ticket, value: PanelWhy): Boolean = current.compareAndSet(ticket, ticket.copy(value = value))
    fun valueFor(owner: StateRecord?): PanelWhy? = current.get().takeIf { it.owner === owner }?.value
}
