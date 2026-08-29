package app.gabbro.gabbro

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.annotation.RequiresApi
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The Rust seam is a lambda, so nothing here loads the native library. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class GabbroPasskeyProviderRobolectricTest {

    private val context: android.content.Context = org.robolectric.RuntimeEnvironment.getApplication()

    @Test
    fun `service is declared with the system-only binding permission`() {
        val info = context.packageManager.getServiceInfo(
            ComponentName(context, GabbroCredentialProviderService::class.java),
            PackageManager.GET_META_DATA,
        )
        assertEquals("android.permission.BIND_CREDENTIAL_PROVIDER_SERVICE", info.permission)
        assertTrue(info.exported)
        assertNotNull(
            "capabilities XML must be linked",
            info.metaData?.get("android.credentials.provider"),
        )
    }

    private fun option(requestJson: String) =
        BeginGetPublicKeyCredentialOption(Bundle(), "test-id", requestJson)

    private val requestJson =
        """{"challenge": "YWJj", "rpId": "example.com", "allowCredentials": []}"""

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    @Test
    fun `locked vault yields an unlock action, never an empty list`() {
        val response = buildBeginGetResponse(context, listOf(option(requestJson))) {
            """{"error": "Vault is locked"}"""
        }
        assertEquals(0, response.credentialEntries.size)
        assertEquals(1, response.authenticationActions.size)
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    @Test
    fun `unlocked vault yields one picker row per match`() {
        val matches = """{"matches": [
            {"entryId": "e1", "rpId": "example.com", "userName": "a@example.com",
             "userDisplayName": "A", "credentialIdB64": "YQ"},
            {"entryId": "e2", "rpId": "example.com", "userName": "b@example.com",
             "userDisplayName": "B", "credentialIdB64": "Yg"}
        ]}"""
        val response = buildBeginGetResponse(context, listOf(option(requestJson))) { matches }
        assertEquals(2, response.credentialEntries.size)
        assertEquals(0, response.authenticationActions.size)
    }

    private val oneMatch = """{"matches": [
        {"entryId": "e1", "rpId": "example.com", "userName": "a@example.com",
         "userDisplayName": "A", "credentialIdB64": "YQ"}
    ]}"""

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    @Test
    fun `relockAfter stamps row intents and the service path stays unstamped`() {
        val stamped = buildBeginGetResponse(
            context, listOf(option(requestJson)), relockAfter = true
        ) { oneMatch }
        val stampedIntent = org.robolectric.Shadows.shadowOf(
            (stamped.credentialEntries.single()
                as androidx.credentials.provider.PublicKeyCredentialEntry).pendingIntent
        ).savedIntent
        assertTrue(
            stampedIntent.getBooleanExtra(GabbroPasskeyActivity.EXTRA_RELOCK_AFTER, false)
        )

        val service = buildBeginGetResponse(context, listOf(option(requestJson))) { oneMatch }
        val serviceIntent = org.robolectric.Shadows.shadowOf(
            (service.credentialEntries.single()
                as androidx.credentials.provider.PublicKeyCredentialEntry).pendingIntent
        ).savedIntent
        assertFalse(serviceIntent.hasExtra(GabbroPasskeyActivity.EXTRA_RELOCK_AFTER))
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    @Test
    fun `creation request yields the save-in-Gabbro entry`() {
        val response = buildBeginCreateResponse(context)
        assertEquals(1, response.createEntries.size)
    }

    private val braveRelease =
        "9C:2D:B7:05:13:51:5F:DB:FB:BC:58:5B:3E:DF:3D:71:23:D4:DC:67:C9:4F:FD:30:63:61:C1:D7:9B:BF:18:AC"

    private fun vendoredAllowlist(): PrivilegedBrowserAllowlist =
        PrivilegedBrowserAllowlist(
            context.assets.open("passkey_privileged_browsers.json")
                .bufferedReader().use { it.readText() }
        )

    @Test
    fun `vendored allowlist accepts Brave and refuses a forged fingerprint`() {
        val allowlist = vendoredAllowlist()
        assertTrue(allowlist.isPrivileged("com.brave.browser", braveRelease))
        assertTrue(allowlist.isPrivileged("app.vanadium.browser",
            "C6:AD:B8:B8:3C:6D:4C:17:D2:92:AF:DE:56:FD:48:8A:51:D3:16:FF:8F:2C:11:C5:41:02:23:BF:F8:A7:DB:B3"))
        assertFalse(
            "same package, wrong signer: a repackaged fake must be refused",
            allowlist.isPrivileged("com.brave.browser", braveRelease.replace("9C", "00")),
        )
        assertFalse(allowlist.isPrivileged("com.evil.browser", braveRelease))
    }

    private val appCert =
        "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"

    private fun assetLinks(pkg: String, cert: String) = """[
        {"relation": ["delegate_permission/common.handle_all_urls"],
         "target": {"namespace": "android_app", "package_name": "$pkg",
                    "sha256_cert_fingerprints": ["$cert"]}}
    ]"""

    @Test
    fun `asset links accept only the vouched package and signer`() {
        val body = assetLinks("com.company.app", appCert)
        assertTrue(assetLinksPermitsApp(body, "com.company.app", appCert))
        assertFalse(assetLinksPermitsApp(body, "com.other.app", appCert))
        assertFalse(assetLinksPermitsApp(body, "com.company.app", appCert.replace("AA", "00")))
        assertFalse(assetLinksPermitsApp("not json", "com.company.app", appCert))
        assertFalse(assetLinksPermitsApp("[]", "com.company.app", appCert))
    }

    @Test
    fun `caller decision refuses when the site cannot be reached`() {
        val decision = decideCaller(
            "example.com", "com.company.app", appCert, vendoredAllowlist(), "hash",
            appPasskeysEnabled = true,
        ) { null }
        assertTrue(decision is CallerDecision.Refused)
    }

    @Test
    fun `caller decision verifies an app the site vouches for`() {
        var fetched: String? = null
        val decision = decideCaller(
            "example.com", "com.company.app", appCert, vendoredAllowlist(), "keyhash",
            appPasskeysEnabled = true,
        ) { url ->
            fetched = url
            assetLinks("com.company.app", appCert)
        }
        assertEquals("https://example.com/.well-known/assetlinks.json", fetched)
        assertTrue(decision is CallerDecision.VerifiedApp)
        assertEquals(
            "android:apk-key-hash:keyhash",
            (decision as CallerDecision.VerifiedApp).origin,
        )
    }

    // F1: Android grants INTERNET silently, so the toggle is the only consent
    // gate before a fetch.

    @Test
    fun `toggle off refuses an app before any fetch`() {
        var fetchCalled = false
        val decision = decideCaller(
            "example.com", "com.company.app", appCert, vendoredAllowlist(), "hash",
            appPasskeysEnabled = false,
        ) {
            fetchCalled = true
            assetLinks("com.company.app", appCert)
        }
        assertTrue(decision is CallerDecision.Refused)
        assertFalse("no network before the opt-in", fetchCalled)
    }

    @Test
    fun `toggle off leaves privileged browsers untouched`() {
        val decision = decideCaller(
            "example.com", "com.brave.browser", braveRelease, vendoredAllowlist(), "hash",
            appPasskeysEnabled = false,
        ) { null }
        assertTrue(decision is CallerDecision.PrivilegedBrowser)
    }

    @Test
    fun `runOffMain executes the block on another thread and returns its value`() {
        val caller = Thread.currentThread().name
        val ranOn = runOffMain { Thread.currentThread().name }
        assertNotNull(ranOn)
        assertFalse("block must not run on the calling thread", ranOn == caller)
    }

    @Test
    fun `runOffMain returns null when the block throws`() {
        assertEquals(null, runOffMain<String> { throw RuntimeException("boom") })
    }

    @Test
    fun `bridge envelope distinguishes locked from error from matches`() {
        assertTrue(parsePasskeyMatches("""{"error": "Vault is locked"}""") is PasskeyRustResult.Locked)
        assertTrue(parsePasskeyMatches("""{"error": "boom"}""") is PasskeyRustResult.Error)
        assertTrue(parsePasskeyMatches("garbage") is PasskeyRustResult.Error)
        val ok = parsePasskeyMatches("""{"matches": []}""")
        assertTrue(ok is PasskeyRustResult.Matches && ok.matches.isEmpty())
    }

    @Test
    fun `client data json carries type challenge and origin`() {
        val cdj = org.json.JSONObject(
            buildClientDataJson("webauthn.get", "Y2hhbGxlbmdl", "android:apk-key-hash:xyz")
        )
        assertEquals("webauthn.get", cdj.getString("type"))
        assertEquals("Y2hhbGxlbmdl", cdj.getString("challenge"))
        assertEquals("android:apk-key-hash:xyz", cdj.getString("origin"))
    }
}
