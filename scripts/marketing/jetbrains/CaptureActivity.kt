package com.ezevillo.gitreview.marketing

import com.ezevillo.gitreview.host.*
import com.ezevillo.gitreview.domain.*
import com.ezevillo.gitreview.settings.GitReviewSettings
import com.ezevillo.gitreview.ui.PanelActionDispatcher
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.editor.colors.EditorColorsManager
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.fileEditor.FileDocumentManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.StartupActivity
import com.intellij.openapi.vfs.LocalFileSystem
import com.intellij.openapi.wm.ToolWindowManager
import com.intellij.openapi.wm.ToolWindowAnchor
import com.intellij.execution.filters.TextConsoleBuilderFactory
import com.intellij.execution.process.OSProcessHandler
import com.intellij.execution.ui.RunContentDescriptor
import com.intellij.execution.ui.RunContentManager
import com.intellij.execution.executors.DefaultRunExecutor
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.openapi.fileTypes.FileTypeManager
import com.intellij.diff.DiffManager
import com.intellij.diff.DiffContentFactory
import com.intellij.diff.requests.SimpleDiffRequest
import java.io.File
import javax.swing.SwingUtilities

// Harness de captura: sólo se agrega a la copia aislada del plugin en el contenedor.
// Acciona el producto real; no suplanta estados, paneles ni resultados de la CLI.
class CaptureActivity : StartupActivity.DumbAware {
  override fun runActivity(project: Project) {
    ApplicationManager.getApplication().executeOnPooledThread {
      try {
        Thread.sleep(12000)
        val app = ApplicationManager.getApplication()
        fun edt(body: () -> Unit) { app.invokeAndWait(body) }
        val settings = GitReviewSettings.getInstance()
        settings.path = "/work/bin/git-review"
        settings.defaultSource = "offline"
        val service = GitReviewService.getInstance(project)
        val dispatcher = PanelActionDispatcher(project, service)
        edt {
          val scheme = EditorColorsManager.getInstance().globalScheme
          scheme.editorFontSize = 22
          scheme.consoleFontSize = 18
          ToolWindowManager.getInstance(project).getToolWindow("Project")?.hide()
          ToolWindowManager.getInstance(project).getToolWindow("gitReview.walkthrough")?.show()
        }
        service.refreshNow()
        File("/tmp/jb-ready").writeText("ready")
        var previous = ""
        while (!project.isDisposed) {
          Thread.sleep(200)
          val commandFile = File("/tmp/jb-command")
          if (!commandFile.exists()) continue
          val line = commandFile.readText().trim()
          if (line == previous || line.isEmpty()) continue
          previous = line
          val command = line.substringAfter(' ')
          val root = project.basePath!!
          fun open(path: String) {
            val file = LocalFileSystem.getInstance().refreshAndFindFileByPath("$root/$path")!!
            edt { FileEditorManager.getInstance(project).openFile(file, true) }
          }
          when(command) {
            "before" -> open("src/rate-limit.js")
            "start" -> edt { MutationActions(project, service).runStart(ReviewIntent(null, ReviewLayout.WALK, ReviewRange.FULL, ReviewSource.OFFLINE), "rate-limit") {} }
            "reading" -> edt { dispatcher.dispatch(ControlId.OPEN_ENTRY, null) }
            "next" -> edt { dispatcher.dispatch(ControlId.NEXT, null) }
            "open" -> edt { dispatcher.dispatch(ControlId.OPEN_ENTRY, null) }
            "select" -> edt {
              val editor = FileEditorManager.getInstance(project).selectedTextEditor!!
              val i = editor.document.text.indexOf("attempts > limit")
              editor.selectionModel.setSelection(i, i + 16)
              editor.caretModel.moveToOffset(i + 16)
            }
            "edit" -> edt {
              val editor = FileEditorManager.getInstance(project).selectedTextEditor!!
              WriteCommandAction.runWriteCommandAction(project) {
                val i = editor.document.text.indexOf("attempts > limit")
                editor.document.replaceString(i, i + 16, "attempts >= limit")
              }
              editor.selectionModel.removeSelection()
              FileDocumentManager.getInstance().saveAllDocuments()
            }
            "tests" -> edt {
              val console = TextConsoleBuilderFactory.getInstance().createBuilder(project).console
              val handler = OSProcessHandler(GeneralCommandLine("node", "--test", "--test-reporter=spec").withWorkDirectory(root))
              console.attachToProcess(handler)
              val descriptor = RunContentDescriptor(console, handler, console.component, "Rate limiter tests")
              RunContentManager.getInstance(project).showRunContent(DefaultRunExecutor.getRunExecutorInstance(), descriptor)
              handler.startNotify()
            }
            "hideTests" -> edt { ToolWindowManager.getInstance(project).getToolWindow("Run")?.hide() }
            "finish" -> edt { MutationActions(project, service).runFinish(false) {} }
            "result" -> {
              fun git(vararg args: String): String = ProcessBuilder(listOf("git") + args).directory(File(root)).start().inputStream.bufferedReader().readText()
              val before = git("show", "HEAD:src/rate-limit.js")
              val after = File("$root/src/rate-limit.js").readText()
              edt {
                val factory = DiffContentFactory.getInstance()
                DiffManager.getInstance().showDiff(project, SimpleDiffRequest("Your extracted fix", factory.create(project, before, FileTypeManager.getInstance().getFileTypeByExtension("js")), factory.create(project, after, FileTypeManager.getInstance().getFileTypeByExtension("js")), "Author's change", "Your fix"))
              }
            }
          }
          File("/tmp/jb-done").writeText(line)
        }
      } catch(e: Throwable) { File("/tmp/jb-error").writeText(e.stackTraceToString()) }
    }
  }
}
