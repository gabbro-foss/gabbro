package app.gabbro.gabbro

import android.webkit.MimeTypeMap
import java.io.File
import java.io.InputStream
import java.util.concurrent.atomic.AtomicLong

/**
 * The file-dialog side of the `app.gabbro.gabbro/picker` channel: what the
 * picker offers the user, and where their choice ends up.
 *
 * Android hands an app a `content://` reference rather than a path, so a
 * picked file is copied into the app's own cache and that path is what Dart
 * receives — every caller keeps working with plain paths.
 *
 * Replaces the `file_picker` plugin's Android side; the behaviour it must
 * match is pinned in `GabbroPickerTest`.
 */
object GabbroPicker {

    const val CHANNEL = "app.gabbro.gabbro/picker"

    /** Cache subdirectory holding copies of picked files. */
    const val CACHE_SUBDIR = "gabbro_picker"

    private const val CSV_EXTENSION = "csv"
    private const val CSV_MIME_TYPE = "text/csv"
    private const val ALL_FILES = "*/*"

    // Keeps concurrent picks of the same filename apart within a run.
    private val pickCounter = AtomicLong(0)

    /**
     * Types to offer in the open dialog for [extensions]. Android filters by
     * type, not by extension, so an extension it does not know (`.gabbro`)
     * would filter every vault out of view — those fall back to showing all
     * files, exactly as `file_picker` did.
     */
    fun mimeTypes(
        extensions: List<String>?,
        lookup: (String) -> String? = {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(it)
        },
    ): Array<String> {
        if (extensions.isNullOrEmpty()) return arrayOf(ALL_FILES)

        val types = mutableListOf<String>()
        for (extension in extensions) {
            val type = lookup(extension) ?: return arrayOf(ALL_FILES)
            types.add(type)
            // Android reports the older spelling; both are in the wild.
            if (extension == CSV_EXTENSION) types.add(CSV_MIME_TYPE)
        }
        return types.toTypedArray()
    }

    /**
     * A fresh destination for a picked file called [name], inside [cacheDir].
     * Each pick gets its own subdirectory, so picking two files with the same
     * name (both `export.csv`, say) keeps both — an import screen holds
     * several picked paths at once.
     */
    fun cacheTarget(cacheDir: File, name: String?): File {
        val safeName = File(name ?: "picked_file").name.ifEmpty { "picked_file" }
        var dir: File
        do {
            dir = File(File(cacheDir, CACHE_SUBDIR), pickCounter.getAndIncrement().toString())
        } while (!dir.mkdirs())
        return File(dir, safeName)
    }

    /** Copies the picked file's contents to [target]. */
    fun copyTo(input: InputStream, target: File) {
        input.use { source ->
            target.outputStream().use { source.copyTo(it) }
        }
    }

    /**
     * The filesystem path of a picked folder, from the identifier the folder
     * picker returns (`primary:Download/Gabbro`). The JSON export and the file
     * export write there directly, so a wrong path means nothing is saved.
     * Null when the identifier carries no volume.
     */
    fun rawPathFromDocumentId(documentId: String): String? {
        val separator = documentId.indexOf(':')
        if (separator <= 0) return null
        val volume = documentId.substring(0, separator)
        val relative = documentId.substring(separator + 1)
        val root = if (volume == "primary") {
            "/storage/emulated/0"
        } else {
            "/storage/$volume"
        }
        return if (relative.isEmpty()) root else "$root/$relative"
    }
}
