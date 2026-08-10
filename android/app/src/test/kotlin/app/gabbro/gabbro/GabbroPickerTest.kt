package app.gabbro.gabbro

import java.io.ByteArrayInputStream
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the pieces of the `app.gabbro.gabbro/picker` channel that decide what
 * the user sees and where their file lands.
 *
 * The `.gabbro` case is the one that matters most: Android has no registered
 * type for it, so filtering by type would show the user an empty picker with
 * none of their vaults in it.
 */
class GabbroPickerTest {

    // A stand-in for Android's own extension -> type table.
    private val androidTypes = mapOf(
        "csv" to "text/comma-separated-values",
        "json" to "application/json",
        "pdf" to "application/pdf",
    )

    private fun types(extensions: List<String>?) =
        GabbroPicker.mimeTypes(extensions) { androidTypes[it] }

    @Test
    fun `no extensions shows every file`() {
        assertArrayEquals(arrayOf("*/*"), types(null))
        assertArrayEquals(arrayOf("*/*"), types(emptyList()))
    }

    @Test
    fun `json maps to its type`() {
        assertArrayEquals(arrayOf("application/json"), types(listOf("json")))
    }

    @Test
    fun `csv maps to both spellings of the csv type`() {
        assertArrayEquals(
            arrayOf("text/comma-separated-values", "text/csv"),
            types(listOf("csv")),
        )
    }

    @Test
    fun `gabbro is unknown to Android so every file is shown`() {
        assertArrayEquals(arrayOf("*/*"), types(listOf("gabbro")))
    }

    @Test
    fun `one unknown extension widens the whole filter`() {
        assertArrayEquals(arrayOf("*/*"), types(listOf("json", "gabbro")))
    }

    @Test
    fun `a picked file is copied into the cache with its own name`() {
        val cacheDir = Files.createTempDirectory("gabbro_cache").toFile()
        val bytes = byteArrayOf(1, 2, 3, 4)

        val target = GabbroPicker.cacheTarget(cacheDir, "vault.gabbro")
        GabbroPicker.copyTo(ByteArrayInputStream(bytes), target)

        assertEquals("vault.gabbro", target.name)
        assertTrue(target.absolutePath.startsWith(cacheDir.absolutePath))
        assertArrayEquals(bytes, target.readBytes())
    }

    @Test
    fun `two picks of the same filename do not overwrite each other`() {
        val cacheDir = Files.createTempDirectory("gabbro_cache").toFile()

        val first = GabbroPicker.cacheTarget(cacheDir, "vault.gabbro")
        GabbroPicker.copyTo(ByteArrayInputStream(byteArrayOf(1)), first)
        val second = GabbroPicker.cacheTarget(cacheDir, "vault.gabbro")
        GabbroPicker.copyTo(ByteArrayInputStream(byteArrayOf(2)), second)

        assertNotEquals(first.absolutePath, second.absolutePath)
        assertArrayEquals(byteArrayOf(1), first.readBytes())
        assertArrayEquals(byteArrayOf(2), second.readBytes())
    }

    @Test
    fun `a nameless pick still lands somewhere readable`() {
        val cacheDir = Files.createTempDirectory("gabbro_cache").toFile()

        val target = GabbroPicker.cacheTarget(cacheDir, null)
        GabbroPicker.copyTo(ByteArrayInputStream(byteArrayOf(9)), target)

        assertTrue(target.name.isNotEmpty())
        assertArrayEquals(byteArrayOf(9), target.readBytes())
    }

    @Test
    fun `a path traversal in the name cannot escape the cache`() {
        val cacheDir = Files.createTempDirectory("gabbro_cache").toFile()

        val target = GabbroPicker.cacheTarget(cacheDir, "../../evil.gabbro")

        assertTrue(target.canonicalPath.startsWith(cacheDir.canonicalPath))
    }

    @Test
    fun `a folder on internal storage becomes a writable path`() {
        assertEquals(
            "/storage/emulated/0/Download/Gabbro",
            GabbroPicker.rawPathFromDocumentId("primary:Download/Gabbro"),
        )
    }

    @Test
    fun `the root of internal storage has no trailing separator`() {
        assertEquals(
            "/storage/emulated/0",
            GabbroPicker.rawPathFromDocumentId("primary:"),
        )
    }

    @Test
    fun `an sd card folder resolves under its volume`() {
        assertEquals(
            "/storage/1B0A-3F2C/Backups",
            GabbroPicker.rawPathFromDocumentId("1B0A-3F2C:Backups"),
        )
    }

    @Test
    fun `a document id with no volume yields no path`() {
        assertNull(GabbroPicker.rawPathFromDocumentId("Download/Gabbro"))
        assertNull(GabbroPicker.rawPathFromDocumentId(""))
    }
}
