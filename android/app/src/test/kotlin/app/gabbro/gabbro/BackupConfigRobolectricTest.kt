package app.gabbro.gabbro

import android.content.pm.ApplicationInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.xmlpull.v1.XmlPullParser

/**
 * R-02: allowBackup defaults to true, and Auto Backup would copy the vault to
 * Google Drive. The OS reads "no backup" from three places (allowBackup,
 * dataExtractionRules, fullBackupContent on API <= 30) and OEM transfer tools
 * do not all honour the flag, so every layer is asserted. Robolectric reads
 * the merged manifest, so a plugin re-enabling backup fails here too. The
 * manifest-to-rules linkage is @hide; the hardware step `aapt dump xmltree`
 * covers it.
 */
@RunWith(RobolectricTestRunner::class)
class BackupConfigRobolectricTest {

    private val allDomains = setOf("root", "file", "database", "sharedpref", "external")

    @Test
    fun merged_manifest_disables_backup() {
        val appInfo = RuntimeEnvironment.getApplication().applicationInfo
        assertEquals(
            "android:allowBackup must be false: the vault must never leave " +
                "the device via Auto Backup or device-to-device transfer (R-02)",
            0,
            appInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP,
        )
    }

    @Test
    fun data_extraction_rules_exclude_everything() {
        val rules = parseRulesXml("data_extraction_rules")
        assertEquals("no <include> rule may ever appear", emptyList<BackupRule>(),
            rules.filter { it.action == "include" })
        for (section in listOf("cloud-backup", "device-transfer")) {
            val excluded = rules.filter { it.section == section && it.action == "exclude" }
                .map { it.domain }.toSet()
            assertTrue(
                "<$section> must exclude all domains; missing: ${allDomains - excluded}",
                excluded.containsAll(allDomains),
            )
        }
    }

    @Test
    fun legacy_backup_rules_exclude_everything() {
        val rules = parseRulesXml("backup_rules")
        assertEquals("no <include> rule may ever appear", emptyList<BackupRule>(),
            rules.filter { it.action == "include" })
        val excluded = rules.filter { it.action == "exclude" }.map { it.domain }.toSet()
        assertTrue(
            "full-backup-content must exclude all domains; missing: ${allDomains - excluded}",
            excluded.containsAll(allDomains),
        )
    }

    private data class BackupRule(val section: String, val action: String, val domain: String)

    private fun parseRulesXml(resName: String): List<BackupRule> {
        val app = RuntimeEnvironment.getApplication()
        val resId = app.resources.getIdentifier(resName, "xml", app.packageName)
        assertTrue("res/xml/$resName.xml must exist", resId != 0)
        val parser = app.resources.getXml(resId)
        val rules = mutableListOf<BackupRule>()
        var section = ""
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            if (event == XmlPullParser.START_TAG) {
                when (parser.name) {
                    "cloud-backup", "device-transfer" -> section = parser.name
                    "include", "exclude" -> rules.add(
                        BackupRule(section, parser.name,
                            parser.getAttributeValue(null, "domain") ?: ""),
                    )
                }
            }
            event = parser.next()
        }
        return rules
    }
}
