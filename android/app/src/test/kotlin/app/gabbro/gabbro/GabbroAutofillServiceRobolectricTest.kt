package app.gabbro.gabbro

import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.service.autofill.SaveInfo
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Robolectric because android.net.Uri and org.json are stubbed to throw in
 * plain JVM tests. The service instance only serves to load the vendored PSL.
 */
@RunWith(RobolectricTestRunner::class)
class GabbroAutofillServiceRobolectricTest {

    private lateinit var service: GabbroAutofillService
    private lateinit var psl: PublicSuffixList

    @Before
    fun setUp() {
        service = Robolectric.setupService(GabbroAutofillService::class.java)
        psl = PublicSuffixList.fromAsset(service)
    }

    private fun registrable(input: String?): String? = extractRegistrableDomain(input, psl)

    @Test
    fun extractRegistrableDomain_null_blank_return_null() {
        assertNull(registrable(null))
        assertNull(registrable(""))
        assertNull(registrable("   "))
    }

    @Test
    fun extractRegistrableDomain_strips_subdomain_scheme_and_path() {
        assertEquals("example.com", registrable("https://www.example.com/login"))
    }

    @Test
    fun extractRegistrableDomain_adds_scheme_when_missing() {
        assertEquals("example.com", registrable("example.com"))
    }

    @Test
    fun extractRegistrableDomain_collapses_arbitrary_subdomain() {
        assertEquals("example.com", registrable("login.example.com"))
    }

    @Test
    fun extractRegistrableDomain_multipart_tld_keeps_registrable_label() {
        // Audit F-10.
        assertEquals("example.co.uk", registrable("https://login.example.co.uk"))
    }

    @Test
    fun extractRegistrableDomain_unrelated_sites_under_shared_suffix_differ() {
        assertEquals("bbc.co.uk", registrable("https://bbc.co.uk"))
        assertEquals("hsbc.co.uk", registrable("https://hsbc.co.uk"))
    }

    @Test
    fun extractRegistrableDomain_bare_public_suffix_is_null() {
        assertNull(registrable("https://co.uk"))
    }

    @Test
    fun extractRegistrableDomain_rejects_ip_address() {
        assertNull(registrable("https://192.168.1.1"))
    }

    @Test
    fun extractRegistrableDomain_trims_trailing_dot() {
        assertEquals("example.com", registrable("https://example.com."))
    }

    @Test
    fun extractRegistrableDomain_lowercases_host() {
        assertEquals("example.com", registrable("HTTPS://WWW.EXAMPLE.COM"))
    }

    @Test
    fun extractRegistrableDomain_ignores_port() {
        assertEquals("example.com", registrable("https://example.com:8080"))
    }

    @Test
    fun extractRegistrableDomain_ignores_userinfo() {
        assertEquals("example.com", registrable("https://user:pass@example.com"))
    }

    @Test
    fun extractRegistrableDomain_single_label_returned_as_is() {
        assertEquals("localhost", registrable("localhost"))
    }

    @Test
    fun parseSummariesJson_parses_array_with_empty_passwords() {
        val json = """
            [
              {"id":"1","username":"alice","url":"https://a.com"},
              {"id":"2","username":"bob","url":"https://b.com"}
            ]
        """.trimIndent()
        val result = parseSummariesJson(json)
        assertEquals(2, result.size)
        assertEquals(CredentialSummary("1", "alice", "https://a.com", ""), result[0])
        assertEquals(CredentialSummary("2", "bob", "https://b.com", ""), result[1])
        assertTrue(result.all { it.password.isEmpty() })
    }

    @Test
    fun parseSummariesJson_empty_array_returns_empty_list() {
        assertTrue(parseSummariesJson("[]").isEmpty())
    }

    @Test
    fun parseSummariesJson_malformed_json_returns_empty_list() {
        assertTrue(parseSummariesJson("garbage not json").isEmpty())
    }

    @Test
    fun parseSummariesJson_one_missing_field_discards_whole_batch() {
        // Pinned so a move to partial-failure handling is a visible decision.
        val json = """[{"username":"alice","url":"https://a.com"},{"id":"2","username":"bob","url":"https://b.com"}]"""
        assertTrue(parseSummariesJson(json).isEmpty())
    }

    @Test
    fun parseSummariesJson_ignores_unknown_fields() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","extra":"x","favourite":true}]"""
        val result = parseSummariesJson(json)
        assertEquals(1, result.size)
        assertEquals(CredentialSummary("1", "alice", "https://a.com", ""), result[0])
    }

    @Test
    fun parseSummariesJson_reads_app_id_field() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","app_id":"com.company.app"}]"""
        val result = parseSummariesJson(json)
        assertEquals("com.company.app", result[0].appId)
    }

    @Test
    fun parseSummariesJson_missing_app_id_defaults_to_empty() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com"}]"""
        assertEquals("", parseSummariesJson(json)[0].appId)
    }

    @Test
    fun parseSummariesJson_reads_email_field() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","email":"alice@example.com"}]"""
        assertEquals("alice@example.com", parseSummariesJson(json)[0].email)
    }

    @Test
    fun parseSummariesJson_missing_email_defaults_to_empty() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com"}]"""
        assertEquals("", parseSummariesJson(json)[0].email)
    }

    private fun cred(id: String, url: String, appId: String = "") =
        CredentialSummary(id = id, username = "user", url = url, password = "", appId = appId)

    @Test
    fun matchingCredentials_web_exact_etld1_match() {
        val creds = listOf(cred("1", "https://example.com"))
        val matches = matchingCredentials(creds, "https://login.example.com", null, psl)
        assertEquals(1, matches.size)
        assertEquals("1", matches[0].id)
    }

    // Audit F-10.
    @Test
    fun matchingCredentials_web_unrelated_shared_suffix_no_cross_match() {
        val creds = listOf(cred("1", "https://hsbc.co.uk"))
        assertTrue(matchingCredentials(creds, "https://bbc.co.uk", null, psl).isEmpty())
    }

    @Test
    fun matchingCredentials_web_unextractable_request_no_match() {
        val creds = listOf(cred("1", "https://example.com"))
        assertTrue(matchingCredentials(creds, "https://co.uk", null, psl).isEmpty())
        assertTrue(matchingCredentials(creds, "https://192.168.1.1", null, psl).isEmpty())
    }

    @Test
    fun matchingCredentials_native_exact_app_id_match() {
        val creds = listOf(cred("1", "https://example.com", appId = "com.company.app"))
        val matches = matchingCredentials(creds, null, "com.company.app", psl)
        assertEquals(1, matches.size)
        assertEquals("1", matches[0].id)
    }

    // A package token ("paypal") appearing in the entry URL must never count.
    @Test
    fun matchingCredentials_native_no_substring_url_match() {
        val creds = listOf(cred("1", "https://paypal.com", appId = ""))
        assertTrue(
            matchingCredentials(creds, null, "com.paypal.android.p2pmobile", psl).isEmpty(),
        )
    }

    @Test
    fun matchingCredentials_native_blank_app_id_no_match() {
        val creds = listOf(cred("1", "https://example.com", appId = ""))
        assertTrue(matchingCredentials(creds, null, "com.company.app", psl).isEmpty())
    }

    @Test
    fun matchingCredentials_native_app_id_mismatch_no_match() {
        val creds = listOf(cred("1", "https://example.com", appId = "com.company.app"))
        assertTrue(matchingCredentials(creds, null, "com.other.app", psl).isEmpty())
    }

    // Match-before-decrypt: the matching input is secret-free even if the feed leaks one.
    @Test
    fun parseSummariesJson_passwords_always_blank() {
        val json = """[{"id":"1","username":"alice","url":"https://a.com","password":"leak"}]"""
        assertEquals("", parseSummariesJson(json)[0].password)
    }

    @Test
    fun matchingCredentials_returns_password_free_summaries() {
        val creds = listOf(cred("1", "https://example.com", appId = "com.company.app"))
        val matches = matchingCredentials(creds, null, "com.company.app", psl)
        assertTrue(matches.isNotEmpty())
        assertTrue(matches.all { it.password.isEmpty() })
    }

    // FillResponse, SaveInfo and Dataset accessors are @hide, so the assertions
    // below reflect on the framework classes Robolectric supplies.

    // AutofillId has no public constructor.
    private fun newAutofillId(): AutofillId {
        val v = android.widget.EditText(service)
        v.id = android.view.View.generateViewId()
        return v.autofillId!!
    }

    private fun saveInfoOf(response: FillResponse): Any? =
        FillResponse::class.java.getMethod("getSaveInfo").invoke(response)

    private fun saveTypeOf(saveInfo: Any): Int =
        saveInfo.javaClass.getMethod("getType").invoke(saveInfo) as Int

    private fun idsVia(saveInfo: Any, getter: String): List<AutofillId> {
        val arr = saveInfo.javaClass.getMethod(getter).invoke(saveInfo) as Array<*>?
        return arr?.filterIsInstance<AutofillId>() ?: emptyList()
    }

    private fun datasetsOf(response: FillResponse): List<Dataset> {
        @Suppress("UNCHECKED_CAST")
        return (FillResponse::class.java.getMethod("getDatasets").invoke(response)
            as? List<Dataset>) ?: emptyList()
    }

    private fun fieldIdsOf(dataset: Dataset): List<AutofillId> {
        @Suppress("UNCHECKED_CAST")
        return (Dataset::class.java.getMethod("getFieldIds").invoke(dataset)
            as? List<AutofillId>) ?: emptyList()
    }

    private fun fieldValuesOf(dataset: Dataset): List<AutofillValue?> {
        @Suppress("UNCHECKED_CAST")
        return (Dataset::class.java.getMethod("getFieldValues").invoke(dataset)
            as? List<AutofillValue?>) ?: emptyList()
    }

    // Field ids alone do not prove a value was attached.
    private fun valueByIdOf(dataset: Dataset): Map<AutofillId, AutofillValue?> =
        fieldIdsOf(dataset).zip(fieldValuesOf(dataset)).toMap()

    private fun text(s: String): AutofillValue = AutofillValue.forText(s)

    // The unlock IntentSender sits on the Dataset, not the FillResponse.
    private fun datasetAuthOf(dataset: Dataset): Any? =
        Dataset::class.java.getMethod("getAuthentication").invoke(dataset)

    private val usernamePasswordType =
        SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD

    @Test
    fun buildFillResponse_fills_matched_username_and_password_datasets() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret")
        val datasets = datasetsOf(service.buildFillResponse(parsed, listOf(cred)))
        assertEquals(1, datasets.size)
        assertEquals(listOf(uId, pId), fieldIdsOf(datasets[0]))
    }

    @Test
    fun buildAuthResponse_sets_authentication_intent_and_covers_fields() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val response = service.buildAuthResponse(parsed)
        val datasets = datasetsOf(response)
        assertEquals(1, datasets.size)
        assertNotNull(datasetAuthOf(datasets[0]))
        assertEquals(listOf(uId, pId), fieldIdsOf(datasets[0]))
    }

    @Test
    fun buildFillResponse_carries_saveinfo_password_required_user_optional() {
        val uId = newAutofillId()
        val eId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(
            usernameIds = listOf(uId),
            passwordIds = listOf(pId),
            webDomain = "https://example.com",
            packageName = null,
            emailIds = listOf(eId),
        )
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret")
        val saveInfo = saveInfoOf(service.buildFillResponse(parsed, listOf(cred)))
        assertNotNull("FillResponse must carry SaveInfo or the OS never calls onSaveRequest", saveInfo)
        assertEquals(usernamePasswordType, saveTypeOf(saveInfo!!))
        assertEquals(listOf(pId), idsVia(saveInfo, "getRequiredIds"))
        assertEquals(setOf(uId, eId), idsVia(saveInfo, "getOptionalIds").toSet())
    }

    // So a password changed on the locked -> unlock -> fill path still saves.
    @Test
    fun buildAuthResponse_carries_saveinfo() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val saveInfo = saveInfoOf(service.buildAuthResponse(parsed))
        assertNotNull(saveInfo)
        assertEquals(usernamePasswordType, saveTypeOf(saveInfo!!))
        assertEquals(listOf(pId), idsVia(saveInfo, "getRequiredIds"))
    }

    @Test
    fun buildFillResponse_without_password_field_has_no_saveinfo() {
        val uId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), emptyList(), "https://example.com", null)
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret")
        assertNull(saveInfoOf(service.buildFillResponse(parsed, listOf(cred))))
    }

    @Test
    fun buildSaveOnlyResponse_has_saveinfo_and_no_datasets_with_password() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val response = service.buildSaveOnlyResponse(parsed)
        assertNotNull(response)
        assertNotNull(saveInfoOf(response!!))
        assertTrue(datasetsOf(response).isEmpty())
    }

    @Test
    fun buildSaveOnlyResponse_null_without_password_field() {
        val uId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), emptyList(), "https://example.com", null)
        assertNull(service.buildSaveOnlyResponse(parsed))
    }

    @Test
    fun buildFillResponse_fills_correct_value_per_field_kind() {
        val uId = newAutofillId()
        val eId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(
            usernameIds = listOf(uId),
            passwordIds = listOf(pId),
            webDomain = "https://example.com",
            packageName = null,
            emailIds = listOf(eId),
        )
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret", email = "alice@example.com")
        val byId = valueByIdOf(datasetsOf(service.buildFillResponse(parsed, listOf(cred)))[0])
        assertEquals(text("alice"), byId[uId])
        assertEquals(text("alice@example.com"), byId[eId])
        assertEquals(text("secret"), byId[pId])
    }

    @Test
    fun buildAuthResponse_sets_empty_placeholder_value_on_each_field() {
        val uId = newAutofillId()
        val pId = newAutofillId()
        val parsed = ParsedStructure(listOf(uId), listOf(pId), "https://example.com", null)
        val byId = valueByIdOf(datasetsOf(service.buildAuthResponse(parsed))[0])
        assertEquals(text(""), byId[uId])
        assertEquals(text(""), byId[pId])
    }

    private fun presentation() =
        android.widget.RemoteViews(service.packageName, R.layout.autofill_unlock_item)

    private fun assertBuildFillDatasetFillsCorrectly() {
        val uId = newAutofillId()
        val eId = newAutofillId()
        val pId = newAutofillId()
        val cred = CredentialSummary("1", "alice", "https://example.com", "secret", email = "alice@example.com")
        val dataset = buildFillDataset(listOf(uId), listOf(eId), listOf(pId), cred, presentation())
        assertEquals(listOf(uId, eId, pId), fieldIdsOf(dataset))
        val byId = valueByIdOf(dataset)
        assertEquals(text("alice"), byId[uId])
        assertEquals(text("alice@example.com"), byId[eId])
        assertEquals(text("secret"), byId[pId])
    }

    // Robolectric default SDK 34: the setField branch.
    @Test
    fun buildFillDataset_fills_correct_value_per_field_kind() {
        assertBuildFillDatasetFillsCorrectly()
    }

    // The deprecated setValue branch (Android 8 to 13) must fill identically.
    @Test
    @Config(sdk = [33])
    fun buildFillDataset_fills_correct_value_on_legacy_device() {
        assertBuildFillDatasetFillsCorrectly()
    }

    // Both sides of the SDK gate, so an edit to the version check cannot drop
    // the value on one side unnoticed.
    private fun assertFillFieldRoundTrips() {
        val id = newAutofillId()
        val builder = Dataset.Builder()
        builder.fillField(id, text("hunter2"), presentation())
        val dataset = builder.build()
        assertEquals(listOf(id), fieldIdsOf(dataset))
        assertEquals(text("hunter2"), valueByIdOf(dataset)[id])
    }

    @Test
    @Config(sdk = [34])
    fun fillField_sets_value_on_api34_setField_branch() {
        assertFillFieldRoundTrips()
    }

    @Test
    @Config(sdk = [33])
    fun fillField_sets_value_on_legacy_setValue_branch() {
        assertFillFieldRoundTrips()
    }

    private fun loginCred(id: String, url: String, username: String, appId: String = "") =
        CredentialSummary(id = id, username = username, url = url, password = "", appId = appId)

    @Test
    fun matchSaveTarget_web_same_domain_and_identifier_returns_entry() {
        val captured = CapturedLogin("alice", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", "alice"))
        val match = matchSaveTarget(captured, summaries, "https://login.example.com", null, psl)
        assertEquals("1", match?.id)
    }

    @Test
    fun matchSaveTarget_web_identifier_match_is_case_insensitive() {
        val captured = CapturedLogin("Alice", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", "alice"))
        assertEquals("1", matchSaveTarget(captured, summaries, "https://example.com", null, psl)?.id)
    }

    @Test
    fun matchSaveTarget_web_same_site_different_identifier_returns_null() {
        val captured = CapturedLogin("bob", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", "alice"))
        assertNull(matchSaveTarget(captured, summaries, "https://example.com", null, psl))
    }

    @Test
    fun matchSaveTarget_native_app_id_and_identifier_returns_entry() {
        val captured = CapturedLogin("alice", "", "newpw")
        val summaries =
            listOf(loginCred("1", "https://example.com", "alice", appId = "com.company.app"))
        assertEquals("1", matchSaveTarget(captured, summaries, null, "com.company.app", psl)?.id)
    }

    @Test
    fun matchSaveTarget_different_site_returns_null() {
        val captured = CapturedLogin("alice", "", "newpw")
        val summaries = listOf(loginCred("1", "https://other.com", "alice"))
        assertNull(matchSaveTarget(captured, summaries, "https://example.com", null, psl))
    }

    @Test
    fun matchSaveTarget_multiple_same_site_returns_identifier_match() {
        val captured = CapturedLogin("bob", "", "newpw")
        val summaries = listOf(
            loginCred("1", "https://example.com", "alice"),
            loginCred("2", "https://example.com", "bob"),
        )
        assertEquals("2", matchSaveTarget(captured, summaries, "https://example.com", null, psl)?.id)
    }

    @Test
    fun matchSaveTarget_blank_identifier_never_auto_targets() {
        val captured = CapturedLogin("", "", "newpw")
        val summaries = listOf(loginCred("1", "https://example.com", ""))
        assertNull(matchSaveTarget(captured, summaries, "https://example.com", null, psl))
    }

    @Test
    fun saveContextJson_create_serializes_captured_and_candidates() {
        val captured = CapturedLogin("alice", "alice@example.com", "secret")
        val candidates = listOf(loginCred("1", "https://example.com", "alice"))
        val json = org.json.JSONObject(
            saveContextJson(captured, "example.com", "", SaveDecision.Create, candidates),
        )
        val cap = json.getJSONObject("captured")
        assertEquals("alice", cap.getString("username"))
        assertEquals("alice@example.com", cap.getString("email"))
        assertEquals("secret", cap.getString("password"))
        assertEquals("example.com", cap.getString("url"))
        assertEquals("", cap.getString("appId"))
        assertEquals("create", json.getJSONObject("decision").getString("action"))
        val cands = json.getJSONArray("candidates")
        assertEquals(1, cands.length())
        assertEquals("1", cands.getJSONObject(0).getString("id"))
        assertEquals("alice", cands.getJSONObject(0).getString("label"))
    }

    @Test
    fun saveContextJson_update_includes_matched_id() {
        val captured = CapturedLogin("alice", "", "secret")
        val dec = org.json.JSONObject(
            saveContextJson(captured, "example.com", "", SaveDecision.Update("id-9"), emptyList()),
        ).getJSONObject("decision")
        assertEquals("update", dec.getString("action"))
        assertEquals("id-9", dec.getString("matchedId"))
    }

    @Test
    fun saveContextJson_noop_action() {
        val captured = CapturedLogin("alice", "", "secret")
        val json = org.json.JSONObject(
            saveContextJson(captured, "example.com", "", SaveDecision.NoOp, emptyList()),
        )
        assertEquals("noop", json.getJSONObject("decision").getString("action"))
    }
}
