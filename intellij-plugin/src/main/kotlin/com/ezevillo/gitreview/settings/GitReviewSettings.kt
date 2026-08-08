package com.ezevillo.gitreview.settings

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.PersistentStateComponent
import com.intellij.openapi.components.State
import com.intellij.openapi.components.Storage
import com.intellij.openapi.options.Configurable
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBTextField
import com.intellij.util.ui.FormBuilder
import javax.swing.JComboBox
import javax.swing.JComponent
import javax.swing.JPanel

@State(name = "GitReviewSettings", storages = [Storage("gitReview.xml")])
class GitReviewSettings : PersistentStateComponent<GitReviewSettings.State> {
    data class State(
        var path: String = "",
        var defaultSource: String = "remote",
    )

    private var myState = State()

    override fun getState(): State = myState

    override fun loadState(state: State) {
        myState = state
    }

    var path: String
        get() = myState.path
        set(value) {
            myState.path = value
        }

    var defaultSource: String
        get() = myState.defaultSource
        set(value) {
            myState.defaultSource = value
        }

    companion object {
        fun getInstance(): GitReviewSettings =
            ApplicationManager.getApplication().getService(GitReviewSettings::class.java)
    }
}

/** Per-project last-opened whole entry display path. */
@State(name = "GitReviewLastOpened", storages = [Storage("gitReviewLastOpened.xml")])
class LastOpenedStore : PersistentStateComponent<LastOpenedStore.State> {
    data class State(
        var byBranch: MutableMap<String, String> = mutableMapOf(),
    )

    private var myState = State()

    override fun getState(): State = myState
    override fun loadState(state: State) {
        myState = state
    }

    fun get(branch: String): String? = myState.byBranch[branch]

    fun set(branch: String, display: String) {
        myState.byBranch[branch] = display
    }
}

class GitReviewConfigurable : Configurable {
    private var pathField: JBTextField? = null
    private var sourceCombo: JComboBox<String>? = null

    override fun getDisplayName(): String = "git review"

    override fun createComponent(): JComponent {
        pathField = JBTextField()
        sourceCombo = JComboBox(arrayOf("remote", "local", "offline"))
        return FormBuilder.createFormBuilder()
            .addLabeledComponent(JBLabel("Path to git-review:"), pathField!!, 1, false)
            .addLabeledComponent(JBLabel("Default source:"), sourceCombo!!, 1, false)
            .addComponentFillVertically(JPanel(), 0)
            .panel
    }

    override fun isModified(): Boolean {
        val s = GitReviewSettings.getInstance()
        return pathField?.text != s.path || sourceCombo?.selectedItem != s.defaultSource
    }

    override fun apply() {
        val s = GitReviewSettings.getInstance()
        s.path = pathField?.text.orEmpty()
        s.defaultSource = sourceCombo?.selectedItem as? String ?: "remote"
    }

    override fun reset() {
        val s = GitReviewSettings.getInstance()
        pathField?.text = s.path
        sourceCombo?.selectedItem = s.defaultSource
    }
}
