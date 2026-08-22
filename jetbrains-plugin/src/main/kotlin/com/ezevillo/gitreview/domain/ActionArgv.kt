package com.ezevillo.gitreview.domain

/**
 * Table-driven (action, params) → argv for the 27 contributes.commands.
 * SC-003 / FR-008 automated parity (T016d).
 */
data class ActionArgv(
    val verb: String,
    val args: List<String>,
    val network: Boolean = false,
)

sealed class ActionParams {
    data class Start(val intent: ReviewIntent, val currentBranch: String) : ActionParams()
    data class Continue(val source: String) : ActionParams()
    data object Empty : ActionParams()
    data class FinishOnto(val ontoSource: Boolean) : ActionParams()
    data class UndoFinish(val force: Boolean) : ActionParams()
    data class ResumeFinish(val ontoSource: Boolean) : ActionParams()
    data class Preview(val stat: Boolean) : ActionParams()
    data class Compare(val layoutFlags: List<String>, val lower: String, val upper: String) : ActionParams()
    data class Housekeeping(val action: HousekeepingAction) : ActionParams()
    data class SetConfig(val key: String, val name: String) : ActionParams()
    data class WalkthroughInit(val force: Boolean) : ActionParams()
    /** 012: descartar el borrador de UNA rama desde el bloque del panel. */
    data class ForgetDraft(val source: String) : ActionParams()
    /** Crear una guia de autoria, vacia: la compartida del repo o la propia. */
    data class CreateGuide(val team: Boolean) : ActionParams()
    /** Borrar la propia. La compartida no se borra por aca: es git rm mas un commit. */
    data object DeleteGuide : ActionParams()
    data object WalkthroughBuild : ActionParams()
    data object Version : ActionParams()
    data object StatusPorcelain : ActionParams()
    data class StatusWhy(val rawPath: String) : ActionParams()
    data object ListPorcelain : ActionParams()
    data object ConfigPorcelain : ActionParams()
}

/**
 * Maps a product action id (without `gitReview.` prefix, camelCase as in package.json)
 * plus params to verb+args.
 */
fun actionToArgv(action: String, params: ActionParams = ActionParams.Empty): ActionArgv {
    return when (action) {
        "startReview" -> {
            val p = params as ActionParams.Start
            ActionArgv("start", intentToArgs(p.intent, p.currentBranch), network = true)
        }
        "continueReview" -> {
            val p = params as ActionParams.Continue
            ActionArgv("continue", listOf(p.source))
        }
        // Nunca --all ni --saved: una acción sobre una fila no toca las demás.
        "forgetDraft" -> {
            val p = params as ActionParams.ForgetDraft
            ActionArgv("forget", forgetDraftArgs(p.source))
        }
        // El verbo es walkthrough; guide es el primer argumento, como draft.
        "createGuide" -> {
            val p = params as ActionParams.CreateGuide
            ActionArgv("walkthrough", createGuideArgs(p.team))
        }
        "deleteGuide" -> ActionArgv("walkthrough", deleteGuideArgs())
        "saveReview" -> ActionArgv("save", emptyList())
        "abortReview" -> ActionArgv("abort", emptyList())
        "finishReview" -> {
            val onto = (params as? ActionParams.FinishOnto)?.ontoSource == true
            ActionArgv("finish", if (onto) listOf("--onto-source") else emptyList())
        }
        "undoFinish" -> {
            val force = (params as? ActionParams.UndoFinish)?.force == true
            ActionArgv(
                "finish",
                if (force) listOf("--abort", "--force") else listOf("--abort"),
            )
        }
        "resumeFinish" -> {
            val onto = (params as? ActionParams.ResumeFinish)?.ontoSource == true
            ActionArgv(
                "finish",
                if (onto) listOf("--resume", "--onto-source") else listOf("--resume"),
            )
        }
        "next" -> ActionArgv("next", emptyList())
        "prev" -> ActionArgv("prev", emptyList())
        "previewEdits" -> ActionArgv("preview", emptyList())
        "previewEditsStat" -> ActionArgv("preview", listOf("--stat"))
        "compareReview" -> {
            val p = params as ActionParams.Compare
            ActionArgv("compare", p.layoutFlags + listOf("--", p.lower, p.upper))
        }
        "cleanReview", "discardInventory", "forgetReview" -> {
            // Housekeeping kinds share this entry for exact argv tests.
            val p = params as ActionParams.Housekeeping
            ActionArgv(
                verbForHousekeeping(p.action),
                argsForHousekeeping(p.action),
                network = housekeepingNeedsNetwork(p.action),
            )
        }
        "setBase" -> {
            val p = params as ActionParams.SetConfig
            ActionArgv("config", listOf("base", "--", p.name))
        }
        "setRemote" -> {
            val p = params as ActionParams.SetConfig
            ActionArgv("config", listOf("remote", "--", p.name))
        }
        "walkthroughInit" -> {
            val force = (params as? ActionParams.WalkthroughInit)?.force == true
            ActionArgv("walkthrough", if (force) listOf("init", "--force") else listOf("init"))
        }
        "walkthroughBuild" -> ActionArgv("walkthrough", listOf("build"))
        // Read / UI-only (no CLI mutation argv for open*/show*/refresh/install/log)
        "openEntry", "openChange", "openAllChanges", "showWhy",
        "goToEntry", "refresh", "installCli", "showCliLog",
        -> ActionArgv("", emptyList())
        else -> throw IllegalArgumentException("unknown action: $action")
    }
}

/** The 27 command ids from contributes.commands (without gitReview. prefix). */
val PRODUCT_ACTIONS: List<String> = listOf(
    "openEntry",
    "openChange",
    "openAllChanges",
    "showWhy",
    "next",
    "prev",
    "goToEntry",
    "refresh",
    "installCli",
    "continueReview",
    "startReview",
    "setBase",
    "setRemote",
    "abortReview",
    "saveReview",
    "finishReview",
    "undoFinish",
    "resumeFinish",
    "discardInventory",
    "cleanReview",
    "forgetReview",
    "previewEdits",
    "previewEditsStat",
    "compareReview",
    "walkthroughInit",
    "walkthroughBuild",
    "showCliLog",
)
