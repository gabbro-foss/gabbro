package app.gabbro.gabbro

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

/**
 * Without the extra the dialog opens wherever the system chooses; without the
 * reply nothing can be remembered.
 */
@RunWith(RobolectricTestRunner::class)
class GabbroPickerLocationTest {

    private val context get() = RuntimeEnvironment.getApplication()

    @Test
    fun `the open intent carries the types and the initial location`() {
        val intent = GabbroPicker.OpenDocumentAt().createIntent(
            context,
            GabbroPicker.PickRequest(
                mimeTypes = arrayOf("application/json"),
                initialUri = "content://docs/document/primary%3ADownload%2Fx.json",
            ),
        )
        assertEquals(Intent.ACTION_OPEN_DOCUMENT, intent.action)
        assertTrue(intent.hasCategory(Intent.CATEGORY_OPENABLE))
        assertEquals("*/*", intent.type)
        assertEquals(listOf("application/json"), intent.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.toList())
        assertEquals(
            Uri.parse("content://docs/document/primary%3ADownload%2Fx.json"),
            intent.getParcelableExtra(DocumentsContract.EXTRA_INITIAL_URI) as Uri?,
        )
    }

    @Test
    fun `no remembered location means no initial-uri extra`() {
        val intent = GabbroPicker.OpenDocumentAt().createIntent(
            context,
            GabbroPicker.PickRequest(mimeTypes = arrayOf("*/*"), initialUri = null),
        )
        assertFalse(intent.hasExtra(DocumentsContract.EXTRA_INITIAL_URI))
        val blank = GabbroPicker.OpenDocumentAt().createIntent(
            context,
            GabbroPicker.PickRequest(mimeTypes = arrayOf("*/*"), initialUri = ""),
        )
        assertFalse(blank.hasExtra(DocumentsContract.EXTRA_INITIAL_URI))
    }

    @Test
    fun `the picked reply carries the cache path and the location`() {
        val reply = GabbroPicker.pickedFileReply(
            "/cache/gabbro_picker/3/x.json",
            Uri.parse("content://docs/document/primary%3ADownload%2Fx.json"),
        )
        assertEquals("/cache/gabbro_picker/3/x.json", reply["path"])
        assertEquals("content://docs/document/primary%3ADownload%2Fx.json", reply["uri"])
    }

    @Test
    fun `a cancelled dialog parses to null`() {
        assertNull(GabbroPicker.OpenDocumentAt().parseResult(0, null))
    }
}
