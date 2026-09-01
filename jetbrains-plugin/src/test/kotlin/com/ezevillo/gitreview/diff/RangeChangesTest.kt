package com.ezevillo.gitreview.diff

import com.ezevillo.gitreview.domain.CommitChange
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.charset.StandardCharsets

/**
 * El git de apoyo que alimenta los paneles de diff.
 *
 * Contra un repo de verdad y no contra salida de git pegada a mano: lo que
 * rompio esto en su momento fue el ARGV --un `--no-commit-id` que faltaba-- y un
 * argv equivocado produce salida perfectamente parseable. Un fixture de texto
 * habria seguido en verde con los paneles vacios y titulados "M".
 */
class RangeChangesTest {
    @Test
    fun aCommitIsReadWithoutItsShaLeakingInAsAPath(@TempDir dir: File) {
        val repo = Repo(dir)
        repo.init()
        repo.write("a.txt", "one\n")
        repo.write("b.txt", "two\n")
        val first = repo.commitAll("first")

        val changes = RangeChanges.nameStatusCommit(dir.absolutePath, first)

        // Dos archivos y solo dos: sin --no-commit-id el sha entra como una
        // entrada mas y la letra de estado se lee como ruta.
        assertEquals(listOf("a.txt", "b.txt"), changes.map { it.path }.sorted())
        assertTrue(changes.none { it.path.length == 40 }, changes.toString())
        assertTrue(changes.none { it.path in listOf("A", "M", "D") }, changes.toString())
        // Es el commit raiz: todo nace ahi, asi que no hay lado izquierdo.
        assertTrue(changes.all { it.before == null }, changes.toString())
        assertTrue(changes.all { it.after != null }, changes.toString())
    }

    @Test
    fun theThreeKindsOfChangeResolveTheirTwoSides(@TempDir dir: File) {
        val repo = Repo(dir)
        repo.init()
        repo.write("kept.txt", "one\n")
        repo.write("gone.txt", "bye\n")
        repo.commitAll("first")

        repo.write("kept.txt", "two\n")
        repo.write("new.txt", "hello\n")
        File(dir, "gone.txt").delete()
        val second = repo.commitAll("second")

        val byPath = RangeChanges.nameStatusCommit(dir.absolutePath, second).associateBy { it.path }
        assertEquals(setOf("kept.txt", "gone.txt", "new.txt"), byPath.keys)

        assertEquals(CommitChange("kept.txt", "kept.txt", "kept.txt"), byPath["kept.txt"])
        // Un archivo agregado no tiene lado izquierdo, y uno borrado no tiene derecho.
        assertNull(byPath["new.txt"]!!.before)
        assertNotNull(byPath["new.txt"]!!.after)
        assertNotNull(byPath["gone.txt"]!!.before)
        assertNull(byPath["gone.txt"]!!.after)
    }

    /**
     * El diff contra HEAD es lo que ve el modo whole: las ediciones del revisor
     * en el working tree, esten o no en el index.
     */
    @Test
    fun theWholeRangeIsWhatTheWorkingTreeHasOverHead(@TempDir dir: File) {
        val repo = Repo(dir)
        repo.init()
        repo.write("a.txt", "one\n")
        repo.commitAll("first")

        assertEquals(emptyList<CommitChange>(), RangeChanges.nameStatusHead(dir.absolutePath))

        repo.write("a.txt", "edited\n")
        repo.write("añadido.txt", "nuevo\n")
        repo.git("add", "-A")

        val changes = RangeChanges.nameStatusHead(dir.absolutePath)
        // Con -z git no cita las rutas: el acento vuelve entero.
        assertEquals(listOf("a.txt", "añadido.txt"), changes.map { it.path }.sorted())
    }

    /**
     * Un git que falla no es una excepcion ni media lista: es la lista vacia, y
     * el panel de arriba dice "no hay cambios" en vez de romperse.
     */
    @Test
    fun gitFailingComesBackAsNoChanges(@TempDir dir: File) {
        val repo = Repo(dir)
        repo.init()
        repo.write("a.txt", "one\n")
        repo.commitAll("first")

        assertEquals(emptyList<CommitChange>(), RangeChanges.nameStatusCommit(dir.absolutePath, "deadbeef"))
        // Y un ejecutable que no existe tampoco escapa como excepcion.
        assertEquals(
            emptyList<CommitChange>(),
            RangeChanges.nameStatusHead(dir.absolutePath, gitExecutable = "git-not-here"),
        )
    }

    /**
     * `showBytes` devuelve BYTES y no texto: el blob puede no ser UTF-8, y quien
     * lo decodifica es el visor con el charset del archivo.
     */
    @Test
    fun showBytesReturnsTheBlobExactlyAsItWasCommitted(@TempDir dir: File) {
        val repo = Repo(dir)
        repo.init()
        val binary = byteArrayOf(0, 1, 2, 3, 0x7F, -1, -2)
        File(dir, "blob.bin").writeBytes(binary)
        File(dir, "text.txt").writeText("línea\n", StandardCharsets.UTF_8)
        val sha = repo.commitAll("first")

        assertTrue(binary.contentEquals(RangeChanges.showBytes(dir.absolutePath, sha, "blob.bin")))
        assertEquals(
            "línea\n",
            String(RangeChanges.showBytes(dir.absolutePath, sha, "text.txt")!!, StandardCharsets.UTF_8),
        )
    }

    /** Y `null` --no un array vacio-- cuando el archivo no esta en ese ref. */
    @Test
    fun showBytesIsNullWhenThereIsNothingToShow(@TempDir dir: File) {
        val repo = Repo(dir)
        repo.init()
        repo.write("a.txt", "one\n")
        val sha = repo.commitAll("first")

        assertNull(RangeChanges.showBytes(dir.absolutePath, sha, "not-there.txt"))
        assertNull(RangeChanges.showBytes(dir.absolutePath, "deadbeef", "a.txt"))
        assertNull(RangeChanges.showBytes(dir.absolutePath, sha, "a.txt", gitExecutable = "git-not-here"))
    }

    /** Un repo de juguete, con la identidad puesta en cada commit. */
    private class Repo(private val dir: File) {
        fun init() {
            git("init", "-q", "-b", "main")
        }

        fun write(name: String, content: String) {
            File(dir, name).writeText(content, StandardCharsets.UTF_8)
        }

        fun commitAll(message: String): String {
            git("add", "-A")
            git(
                "-c", "user.email=test@example.com",
                "-c", "user.name=Test",
                "commit", "-q", "-m", message,
            )
            return git("rev-parse", "HEAD").trim()
        }

        fun git(vararg args: String): String {
            val process = ProcessBuilder(listOf("git") + args)
                .directory(dir)
                .redirectErrorStream(true)
                .start()
            val out = process.inputStream.readBytes().toString(StandardCharsets.UTF_8)
            val code = process.waitFor()
            check(code == 0) { "git ${args.joinToString(" ")} failed ($code): $out" }
            return out
        }
    }
}
