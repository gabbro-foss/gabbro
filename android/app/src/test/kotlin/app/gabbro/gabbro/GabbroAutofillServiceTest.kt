package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// extractAppToken, extractRegistrableDomain, and parseSummariesJson are private
// instance methods on GabbroAutofillService (an Android Service) — they cannot
// be called from JVM unit tests without Robolectric or production-code refactoring.
// The pure-Kotlin helpers below cover the data-model layer only.

class GabbroAutofillServiceTest {

    // ── CredentialSummary ─────────────────────────────────────────────────────

    @Test
    fun credentialSummary_copy_updates_password() {
        val base = CredentialSummary(id = "x", username = "user", url = "https://a.com", password = "")
        val withPw = base.copy(password = "s3cr3t")
        assertEquals("s3cr3t", withPw.password)
        assertEquals("x", withPw.id)
        assertEquals("user", withPw.username)
    }

    @Test
    fun credentialSummary_equality_based_on_all_fields() {
        val a = CredentialSummary("1", "alice", "https://example.com", "pw")
        val b = CredentialSummary("1", "alice", "https://example.com", "pw")
        assertEquals(a, b)
    }

    // ── ParsedStructure.isEmpty ───────────────────────────────────────────────

    @Test
    fun parsedStructure_isEmpty_true_when_both_id_lists_empty() {
        val ps = ParsedStructure(
            usernameIds = emptyList(),
            passwordIds = emptyList(),
            webDomain = null,
            packageName = null,
        )
        assertTrue(ps.isEmpty())
    }

    @Test
    fun parsedStructure_isEmpty_true_even_when_webDomain_set() {
        // isEmpty only checks id lists — webDomain alone does not make it non-empty
        val ps = ParsedStructure(
            usernameIds = emptyList(),
            passwordIds = emptyList(),
            webDomain = "example.com",
            packageName = "com.example",
        )
        assertTrue(ps.isEmpty())
    }

    // ── classifyField ─────────────────────────────────────────────────────────
    // Pure per-field decision lifted out of the AssistStructure walk. android.*
    // constants used below are compile-time-inlined, so this runs in the fast
    // JVM lane with no Robolectric. The ViewNode glue that feeds these signals
    // is device-verified.

    // password-class inputType (TYPE_CLASS_TEXT | TYPE_TEXT_VARIATION_PASSWORD)
    private val passwordInputType =
        android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD

    // email-class inputType (TYPE_CLASS_TEXT | TYPE_TEXT_VARIATION_EMAIL_ADDRESS)
    private val emailInputType =
        android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS

    private fun classify(
        hints: List<String>? = null,
        inputType: Int = 0,
        htmlType: String? = null,
        htmlAutocomplete: String? = null,
        hint: String? = null,
        idEntry: String? = null,
        htmlName: String? = null,
        htmlId: String? = null,
    ): FieldKind = classifyField(
        autofillHints = hints,
        inputType = inputType,
        htmlType = htmlType,
        htmlAutocomplete = htmlAutocomplete,
        hint = hint,
        idEntry = idEntry,
        htmlName = htmlName,
        htmlId = htmlId,
    )

    // (1) autofill hint username — preserved
    @Test
    fun classifyField_autofill_hint_username_is_username() {
        assertEquals(FieldKind.USERNAME, classify(hints = listOf("username")))
    }

    // (2) autofill hint password — preserved
    @Test
    fun classifyField_autofill_hint_password_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(hints = listOf("password")))
    }

    // (3) the web miss: HTML type=password, no hints, inputType 0 -> Password
    @Test
    fun classifyField_html_type_password_with_no_other_signal_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(htmlType = "password", inputType = 0))
    }

    // (4) HTML type=email -> Username
    @Test
    fun classifyField_html_type_email_is_username() {
        assertEquals(FieldKind.USERNAME, classify(htmlType = "email"))
    }

    // (5) autocomplete current-/new-password -> Password
    @Test
    fun classifyField_autocomplete_current_and_new_password_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(htmlAutocomplete = "current-password"))
        assertEquals(FieldKind.PASSWORD, classify(htmlAutocomplete = "new-password"))
    }

    // (6) autocomplete username -> Username
    @Test
    fun classifyField_autocomplete_username_is_username() {
        assertEquals(FieldKind.USERNAME, classify(htmlAutocomplete = "username"))
    }

    // (7) inputType password variation — preserved
    @Test
    fun classifyField_inputtype_password_variation_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(inputType = passwordInputType))
    }

    // (8) inputType email variation — preserved
    @Test
    fun classifyField_inputtype_email_variation_is_username() {
        assertEquals(FieldKind.USERNAME, classify(inputType = emailInputType))
    }

    // (9) keyword password in name/id -> Password. html name/id are only trusted
    // on a real form control (htmlType present); type=text marks an input without
    // tripping the earlier Tier-2 html-type rule.
    @Test
    fun classifyField_keyword_password_in_name_or_id_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(idEntry = "loginPassword"))
        assertEquals(FieldKind.PASSWORD, classify(htmlName = "user_password", htmlType = "text"))
    }

    // (10) keyword email/username/login/phone in hint/idEntry/name/id -> Username
    @Test
    fun classifyField_keyword_user_signals_are_username() {
        assertEquals(FieldKind.USERNAME, classify(hint = "Email or phone"))
        assertEquals(FieldKind.USERNAME, classify(idEntry = "user_login"))
        assertEquals(FieldKind.USERNAME, classify(htmlName = "username_field", htmlType = "text"))
        assertEquals(FieldKind.USERNAME, classify(hint = "Phone number"))
    }

    // (13) html id carries the username truth where name is too short to match
    // (aur.archlinux.org: name="user", id="id_username", type="text").
    @Test
    fun classifyField_html_id_username_on_input_is_username() {
        assertEquals(
            FieldKind.USERNAME,
            classify(htmlType = "text", htmlName = "user", htmlId = "id_username"),
        )
    }

    // (14) container guard: a <form name="login"> carries an html name but no
    // html type. It must not be classified as a username field (bbs/wiki false
    // positive that produced an extra username target).
    @Test
    fun classifyField_html_name_without_type_is_none() {
        assertEquals(FieldKind.NONE, classify(htmlName = "login"))
        assertEquals(FieldKind.NONE, classify(htmlName = "userlogin"))
    }

    // (11) no signal at all -> None
    @Test
    fun classifyField_no_signal_is_none() {
        assertEquals(FieldKind.NONE, classify())
    }

    // (12) precedence: HTML type=password beats a stray "username" keyword
    @Test
    fun classifyField_html_password_beats_stray_username_keyword() {
        assertEquals(
            FieldKind.PASSWORD,
            classify(htmlType = "password", idEntry = "username_field"),
        )
    }

    // ── formatNodeDiagnostic ──────────────────────────────────────────────────
    // Pure formatter for the debug-only structure dump. Turns one node's signals
    // into a single stable log line so a logcat capture on a failing SPA page
    // shows exactly what (if anything) the browser exposed. Metadata only — never
    // an AutofillValue / typed text. Side-effecting emission (Log.d) and the walk
    // are device-verified, not unit-tested.

    private fun diag(
        className: String? = null,
        hasAutofillId: Boolean = false,
        hints: List<String>? = null,
        inputType: Int = 0,
        htmlType: String? = null,
        htmlName: String? = null,
        htmlAutocomplete: String? = null,
        htmlId: String? = null,
        webDomain: String? = null,
        idEntry: String? = null,
        hint: String? = null,
        childCount: Int = 0,
    ): String = formatNodeDiagnostic(
        className = className,
        hasAutofillId = hasAutofillId,
        autofillHints = hints,
        inputType = inputType,
        htmlType = htmlType,
        htmlName = htmlName,
        htmlAutocomplete = htmlAutocomplete,
        htmlId = htmlId,
        webDomain = webDomain,
        idEntry = idEntry,
        hint = hint,
        childCount = childCount,
    )

    // (1) html attributes are rendered into the line
    @Test
    fun formatNodeDiagnostic_includes_html_attributes() {
        val line = diag(
            htmlType = "password",
            htmlName = "pw",
            htmlAutocomplete = "current-password",
            htmlId = "pwField",
        )
        assertTrue(line, line.contains("type=password"))
        assertTrue(line, line.contains("name=pw"))
        assertTrue(line, line.contains("autocomplete=current-password"))
        assertTrue(line, line.contains("id=pwField"))
    }

    // (2) autofill hints are rendered into the line
    @Test
    fun formatNodeDiagnostic_includes_autofill_hints() {
        val line = diag(hints = listOf("username", "emailAddress"))
        assertTrue(line, line.contains("username"))
        assertTrue(line, line.contains("emailAddress"))
    }

    // (3) inputType is rendered as hex
    @Test
    fun formatNodeDiagnostic_renders_inputtype_as_hex() {
        val line = diag(inputType = passwordInputType)
        assertTrue(line, line.contains(Integer.toHexString(passwordInputType)))
    }

    // (4) autofillId presence is marked yes/no
    @Test
    fun formatNodeDiagnostic_marks_autofill_id_presence() {
        assertTrue(diag(hasAutofillId = true).contains("afId=yes"))
        assertTrue(diag(hasAutofillId = false).contains("afId=no"))
    }

    // (5) the SPA-miss case: a node with no signals still yields a stable,
    // non-crashing line that shows the emptiness
    @Test
    fun formatNodeDiagnostic_no_signal_node_is_stable() {
        val line = diag(className = "android.view.View")
        assertTrue(line, line.contains("android.view.View"))
        assertTrue(line, line.contains("afId=no"))
        assertTrue(line, line.contains("html[]"))
        assertTrue(line, line.contains("hints[]"))
    }

    // (6) null/blank fields do not throw and are shown empty
    @Test
    fun formatNodeDiagnostic_null_fields_do_not_throw() {
        val line = diag() // everything default/null
        assertTrue(line.isNotBlank())
        assertTrue(line, line.contains("html[]"))
        assertTrue(line, line.contains("hints[]"))
    }

    // ── nativeAppIdMatches ────────────────────────────────────────────────────
    // Native-app match is EXACT package-name equality. The cardinal rule: an
    // unset (blank) app id matches nothing — no loose/substring matching.

    @Test
    fun nativeAppIdMatches_exact_package_matches() {
        assertTrue(nativeAppIdMatches("com.company.app", "com.company.app"))
    }

    @Test
    fun nativeAppIdMatches_blank_app_id_matches_nothing() {
        assertFalse(nativeAppIdMatches("", "com.company.app"))
        assertFalse(nativeAppIdMatches(null, "com.company.app"))
        assertFalse(nativeAppIdMatches("   ", "com.company.app"))
    }

    @Test
    fun nativeAppIdMatches_blank_or_different_package_does_not_match() {
        assertFalse(nativeAppIdMatches("com.company.app", null))
        assertFalse(nativeAppIdMatches("com.company.app", ""))
        assertFalse(nativeAppIdMatches("com.company.app", "com.other.app"))
    }

    @Test
    fun nativeAppIdMatches_trims_surrounding_whitespace() {
        assertTrue(nativeAppIdMatches("  com.company.app  ", "com.company.app"))
    }

    // ── shouldRecordPackage ───────────────────────────────────────────────────

    @Test
    fun shouldRecordPackage_third_party_app_is_recorded() {
        assertTrue(shouldRecordPackage("com.company.app", "app.gabbro.gabbro"))
    }

    @Test
    fun shouldRecordPackage_own_package_is_not_recorded() {
        assertFalse(shouldRecordPackage("app.gabbro.gabbro", "app.gabbro.gabbro"))
    }

    @Test
    fun shouldRecordPackage_blank_is_not_recorded() {
        assertFalse(shouldRecordPackage(null, "app.gabbro.gabbro"))
        assertFalse(shouldRecordPackage("", "app.gabbro.gabbro"))
        assertFalse(shouldRecordPackage("  ", "app.gabbro.gabbro"))
    }

    // ── recentAppsUpdated ─────────────────────────────────────────────────────

    @Test
    fun recentAppsUpdated_prepends_new_package() {
        assertEquals(
            listOf("new.app", "old.app"),
            recentAppsUpdated(listOf("old.app"), "new.app", 10),
        )
    }

    @Test
    fun recentAppsUpdated_moves_duplicate_to_front_without_duplicating() {
        assertEquals(
            listOf("b.app", "a.app", "c.app"),
            recentAppsUpdated(listOf("a.app", "b.app", "c.app"), "b.app", 10),
        )
    }

    @Test
    fun recentAppsUpdated_enforces_cap_dropping_oldest() {
        assertEquals(
            listOf("d.app", "c.app", "b.app"),
            recentAppsUpdated(listOf("c.app", "b.app", "a.app"), "d.app", 3),
        )
    }
}
