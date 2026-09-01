package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.MIN_CLI_VERSION

/**
 * Una CLI con libreto: contesta por verbo y anota lo que le preguntaron.
 *
 * Todo lo que el pipeline de refresh decide sale de estas cuatro o cinco
 * respuestas, asi que es aca donde sus ramas se pueden ejercitar de verdad. Un
 * proceso real por caso seria lento y, para un timeout o una CLI ausente,
 * estaria probando la maquina.
 */
class FakeCliRunner : CliRunner {
    data class Call(
        val verb: String,
        val args: List<String>,
        val cwd: String,
        val network: Boolean,
    )

    private val answers = LinkedHashMap<String, (List<String>) -> InvokeResult>()

    val calls = ArrayList<Call>()

    val verbs: List<String> get() = calls.map { it.verb }

    /** Lo que contesta un verbo del que nadie dijo nada. */
    var fallback: InvokeResult = InvokeResult("", "", 0)

    init {
        // Una CLI presente y al dia, salvo que un test diga otra cosa. El minimo
        // mismo y no un literal: subir MIN_CLI_VERSION convertiria si no cada
        // test de estado en un panel cli-outdated.
        answer("--version", "$MIN_CLI_VERSION\n")
    }

    fun answer(verb: String, result: InvokeResult): FakeCliRunner {
        answers[verb] = { result }
        return this
    }

    fun answer(verb: String, stdout: String, exitCode: Int = 0): FakeCliRunner =
        answer(verb, InvokeResult(stdout, "", exitCode))

    fun fails(verb: String, stderr: String, exitCode: Int = 1): FakeCliRunner =
        answer(verb, InvokeResult("", stderr, exitCode))

    override fun invoke(
        verb: String,
        args: List<String>,
        cwd: String,
        network: Boolean,
        timeoutMs: Long,
    ): InvokeResult {
        calls.add(Call(verb, args, cwd, network))
        return answers[verb]?.invoke(args) ?: fallback
    }
}
