package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import javax.swing.SwingUtilities

class CommentFormTest {
    private val capture = CommentCapture("src/old.kt", "base", 12, 15, false, "baseOid", "headOid", "src/old.kt", "src/new.kt", true, "selected code")
    private fun edt(test: () -> Unit) = SwingUtilities.invokeAndWait(test)
    @Test fun selectionIsDefaultAndScopeSwitchesPreserveTextAndOriginalSelection() = edt {
        val form = CommentForm(capture, listOf("local", "shared")) {}
        assertEquals(listOf(CommentScope.SELECTION, CommentScope.FILE, CommentScope.GENERAL), form.scopes)
        assertEquals(CommentScope.SELECTION, form.selectedScope)
        assertEquals("selected code", form.preview.text)
        form.text.text = "Question"
        form.scope.selectedIndex = 2
        assertEquals(CommentScope.GENERAL, form.selectedScope)
        assertFalse(form.previewPane.isVisible); assertEquals("", form.preview.text)
        assertEquals("Question", form.text.text)
        form.scope.selectedIndex = 0
        assertEquals("selected code", form.preview.text)
        assertTrue(form.scope.selectedItem.toString().contains("12–15"))
        assertTrue(form.scope.selectedItem.toString().contains(CommentsCopy.baseSide))
    }
    @Test fun caretWithoutSelectionDefaultsToFileAndOffersGeneral() = edt {
        val form = CommentForm(capture.copy(hasSelection = false, snippet = ""), listOf("local", "shared")) {}
        assertEquals(listOf(CommentScope.FILE, CommentScope.GENERAL), form.scopes)
        assertEquals(CommentScope.FILE, form.selectedScope)
        assertFalse(form.previewPane.isVisible); assertEquals("", form.preview.text)
        assertFalse(form.canSave)
    }
    @Test fun missingEditorOffersOnlyGeneral() = edt {
        val form = CommentForm(null, listOf("local", "shared")) {}
        assertEquals(listOf(CommentScope.GENERAL), form.scopes)
        assertEquals(CommentsCopy.general, form.scope.selectedItem)
    }
    @Test fun savingDisablesCancelInputsAndDuplicateSubmitsThenClosesOnSuccess() = edt {
        val form = CommentForm(capture, listOf("local", "shared")) {}
        form.text.text = "Question"; form.destination.selectedIndex = 1
        var callback: ((String?) -> Unit)? = null
        var saves = 0; var closes = 0
        val submit: (String, String, CommentScope, (String?) -> Unit) -> Unit = { kind, body, scope, done ->
            saves++; assertEquals("shared", kind); assertEquals("Question", body)
            assertEquals(CommentScope.SELECTION, scope); callback = done
        }
        val complete: (String?) -> Unit = { if (it == null) closes++ }
        form.save(submit, complete)
        assertTrue(form.busy); assertFalse(form.canCancel); assertFalse(form.canSave)
        assertFalse(form.destination.isEnabled); assertFalse(form.scope.isEnabled); assertFalse(form.text.isEditable)
        form.save(submit, complete)
        assertEquals(1, saves); assertEquals(0, closes)
        callback!!(null); callback!!(null)
        assertEquals(1, closes)
    }
    @Test fun failureRestoresControlsAndRetainsBodyDestinationAndScopeForRetry() = edt {
        val form = CommentForm(capture, listOf("local", "shared")) {}
        form.text.text = "Question"; form.destination.selectedIndex = 0; form.scope.selectedIndex = 1
        var error: String? = null
        form.save({ _, _, _, done -> done("stale") }) { error = it }
        assertEquals("stale", error); assertFalse(form.busy); assertTrue(form.canCancel); assertTrue(form.canSave)
        assertEquals("Question", form.text.text); assertEquals(0, form.destination.selectedIndex)
        assertEquals(CommentScope.FILE, form.selectedScope)
        assertTrue(form.text.isEditable); assertTrue(form.destination.isEnabled); assertTrue(form.scope.isEnabled)
    }
    @Test fun synchronousFailureRetainsUnsavedInput() = edt {
        val form = CommentForm(capture, listOf("local", "shared")) {}
        form.text.text = "Question"; form.destination.selectedIndex = 0
        var error: String? = null
        form.save({ _, _, _, _ -> throw IllegalStateException("offline") }) { error = it }
        assertEquals("offline", error); assertTrue(form.canSave); assertEquals("Question", form.text.text)
    }
    @Test fun fileScopeOmitsLineCoordinatesAndGeneralOmitsAllLocationArguments() {
        val selected = capture.locationArgs(CommentScope.SELECTION)
        assertEquals("12", selected[selected.indexOf("--start-line") + 1])
        assertEquals("15", selected[selected.indexOf("--end-line") + 1])
        val file = capture.locationArgs(CommentScope.FILE)
        assertFalse("--start-line" in file); assertFalse("--end-line" in file)
        for (args in listOf(file, selected)) {
            assertEquals("base", args[args.indexOf("--side") + 1])
            assertEquals("src/old.kt", args[args.indexOf("--base-path") + 1])
            assertEquals("src/new.kt", args[args.indexOf("--head-path") + 1])
            assertEquals("baseOid", args[args.indexOf("--base") + 1])
        }
        assertTrue(capture.locationArgs(CommentScope.GENERAL).isEmpty())
    }
    @Test fun unselectedCaretCannotBeSubmittedAsSelectedLines() {
        assertThrows(IllegalArgumentException::class.java) { capture.copy(hasSelection = false).locationArgs(CommentScope.SELECTION) }
    }
    @Test fun formRendersAllThreeScopesAndPreview() = edt {
        val form = CommentForm(capture, listOf("local", "shared")) {}
        form.text.text = "Why does this return before checking permissions?"
        form.destination.selectedIndex = 1
        form.setSize(640, 430); layoutTree(form)
        val image = java.awt.image.BufferedImage(640, 430, java.awt.image.BufferedImage.TYPE_INT_RGB)
        val g = image.createGraphics(); form.paint(g); g.dispose()
        val output = java.io.File("build/shots/comment-form.png"); output.parentFile.mkdirs()
        javax.imageio.ImageIO.write(image, "png", output)
        assertTrue(output.length() > 1000)
    }
    @Test fun unifiedSelectionUsesOriginalCoordinatesAndRejectsMixedSides() {
        assertEquals(12 to 14, commentOriginalLines(20, 22) { it - 8 })
        assertEquals(12 to 12, commentOriginalLines(20, 20) { it - 8 })
        assertNull(commentOriginalLines(20, 22) { if (it == 20) -1 else it - 8 })
        assertNull(commentOriginalLines(20, 22) { if (it == 20) 42 else it - 8 })
        assertNull(commentOriginalLines(0, 1) { it })
    }
    @Test fun destinationPlaceholderIsNotASelectableItem() = edt {
        val form = CommentForm(capture, listOf("local", "shared")) {}
        assertEquals(-1, form.destination.selectedIndex)
        assertEquals(listOf(CommentsCopy.localDestination, CommentsCopy.sharedDestination), (0 until form.destination.itemCount).map { form.destination.getItemAt(it) })
        val display = form.destination.renderer.getListCellRendererComponent(javax.swing.JList(), null, -1, false, false) as javax.swing.JLabel
        assertEquals(CommentsCopy.destination, display.text)
        form.text.text = "Question"; assertFalse(form.canSave)
        form.destination.selectedIndex = 0; assertTrue(form.canSave)
    }
    @Test fun textFieldsAndSelectorsShareBothEdgesAtDifferentWidths() = edt {
        val form = CommentForm(capture, listOf("local", "shared")) {}
        for (width in listOf(430, 640)) {
            for (scope in form.scopes.indices) {
                form.scope.selectedIndex = scope
                form.setSize(width, 430); layoutTree(form)
                val origin = javax.swing.SwingUtilities.convertPoint(form.scope.parent, form.scope.location, form)
                for (field in listOf(form.destination, form.textPane) + if (form.previewPane.isVisible) listOf(form.previewPane) else emptyList()) {
                    val point = javax.swing.SwingUtilities.convertPoint(field.parent, field.location, form)
                    assertEquals(origin.x, point.x)
                    assertEquals(form.scope.width, field.width)
                }
            }
        }
    }
    @Test fun soleCliDestinationIsHiddenAndSubmittedWithoutChoosing() = edt {
        for (kind in listOf("local", "shared")) {
            val report = parseComments("comments-capability\tadd\t$kind\ncomments-capability\tadd\t$kind\ncomments-capability\tadd\tunknown\ncomments-capability\tadd")
            val form = CommentForm(capture, report.destinations()) {}
            assertFalse(form.destination.isVisible)
            form.text.text = "Keep this note"
            assertTrue(form.canSave)
            var submitted: String? = null
            form.save({ destination, _, _, done -> submitted = destination; done(null) }) {}
            assertEquals(kind, submitted)
        }
        assertTrue(parseComments("comments-guard\tg").destinations().isEmpty())
    }
    private fun layoutTree(c: java.awt.Container) { c.doLayout(); c.components.filterIsInstance<java.awt.Container>().forEach { layoutTree(it) } }
}
