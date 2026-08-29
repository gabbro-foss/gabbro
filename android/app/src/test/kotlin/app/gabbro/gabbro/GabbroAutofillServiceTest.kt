package app.gabbro.gabbro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Helpers touching android.net.Uri or org.json are tested under Robolectric in
// GabbroAutofillServiceRobolectricTest; those classes throw in plain JVM tests.

class GabbroAutofillServiceTest {

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
        val ps = ParsedStructure(
            usernameIds = emptyList(),
            passwordIds = emptyList(),
            webDomain = "example.com",
            packageName = "com.example",
        )
        assertTrue(ps.isEmpty())
    }

    // The android.* constants are compile-time inlined, so no Robolectric needed.
    private val passwordInputType =
        android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD

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

    @Test
    fun classifyField_autofill_hint_username_is_username() {
        assertEquals(FieldKind.USERNAME, classify(hints = listOf("username")))
    }

    @Test
    fun classifyField_autofill_hint_password_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(hints = listOf("password")))
    }

    @Test
    fun classifyField_html_type_password_with_no_other_signal_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(htmlType = "password", inputType = 0))
    }

    @Test
    fun classifyField_html_type_email_is_email() {
        assertEquals(FieldKind.EMAIL, classify(htmlType = "email"))
    }

    @Test
    fun classifyField_autocomplete_current_and_new_password_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(htmlAutocomplete = "current-password"))
        assertEquals(FieldKind.PASSWORD, classify(htmlAutocomplete = "new-password"))
    }

    @Test
    fun classifyField_autocomplete_username_is_username() {
        assertEquals(FieldKind.USERNAME, classify(htmlAutocomplete = "username"))
    }

    @Test
    fun classifyField_inputtype_password_variation_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(inputType = passwordInputType))
    }

    @Test
    fun classifyField_inputtype_email_variation_is_email() {
        assertEquals(FieldKind.EMAIL, classify(inputType = emailInputType))
    }

    // htmlType = "text" marks a real control without tripping the html-type tier.
    @Test
    fun classifyField_keyword_password_in_name_or_id_is_password() {
        assertEquals(FieldKind.PASSWORD, classify(idEntry = "loginPassword"))
        assertEquals(FieldKind.PASSWORD, classify(htmlName = "user_password", htmlType = "text"))
    }

    @Test
    fun classifyField_keyword_user_signals_are_username() {
        assertEquals(FieldKind.USERNAME, classify(idEntry = "user_login"))
        assertEquals(FieldKind.USERNAME, classify(htmlName = "username_field", htmlType = "text"))
        assertEquals(FieldKind.USERNAME, classify(hint = "Phone number"))
    }

    @Test
    fun classifyField_email_signals_are_email() {
        assertEquals(FieldKind.EMAIL, classify(hints = listOf("emailAddress")))
        assertEquals(FieldKind.EMAIL, classify(htmlAutocomplete = "email"))
        assertEquals(FieldKind.EMAIL, classify(hint = "Email or phone"))
        assertEquals(FieldKind.EMAIL, classify(idEntry = "user_email"))
        assertEquals(FieldKind.EMAIL, classify(htmlName = "email_field", htmlType = "text"))
    }

    @Test
    fun classifyField_email_keyword_outranks_username_keyword() {
        assertEquals(FieldKind.EMAIL, classify(idEntry = "login_email"))
    }

    // aur.archlinux.org: name="user" is too short, id="id_username" carries it.
    @Test
    fun classifyField_html_id_username_on_input_is_username() {
        assertEquals(
            FieldKind.USERNAME,
            classify(htmlType = "text", htmlName = "user", htmlId = "id_username"),
        )
    }

    // A <form name="login"> container has a name but no type and must not
    // become a username target.
    @Test
    fun classifyField_html_name_without_type_is_none() {
        assertEquals(FieldKind.NONE, classify(htmlName = "login"))
        assertEquals(FieldKind.NONE, classify(htmlName = "userlogin"))
    }

    @Test
    fun classifyField_no_signal_is_none() {
        assertEquals(FieldKind.NONE, classify())
    }

    @Test
    fun classifyField_html_password_beats_stray_username_keyword() {
        assertEquals(
            FieldKind.PASSWORD,
            classify(htmlType = "password", idEntry = "username_field"),
        )
    }

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

    @Test
    fun formatNodeDiagnostic_includes_autofill_hints() {
        val line = diag(hints = listOf("username", "emailAddress"))
        assertTrue(line, line.contains("username"))
        assertTrue(line, line.contains("emailAddress"))
    }

    @Test
    fun formatNodeDiagnostic_renders_inputtype_as_hex() {
        val line = diag(inputType = passwordInputType)
        assertTrue(line, line.contains(Integer.toHexString(passwordInputType)))
    }

    @Test
    fun formatNodeDiagnostic_marks_autofill_id_presence() {
        assertTrue(diag(hasAutofillId = true).contains("afId=yes"))
        assertTrue(diag(hasAutofillId = false).contains("afId=no"))
    }

    @Test
    fun formatNodeDiagnostic_no_signal_node_is_stable() {
        val line = diag(className = "android.view.View")
        assertTrue(line, line.contains("android.view.View"))
        assertTrue(line, line.contains("afId=no"))
        assertTrue(line, line.contains("html[]"))
        assertTrue(line, line.contains("hints[]"))
    }

    @Test
    fun formatNodeDiagnostic_null_fields_do_not_throw() {
        val line = diag()
        assertTrue(line.isNotBlank())
        assertTrue(line, line.contains("html[]"))
        assertTrue(line, line.contains("hints[]"))
    }

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

    @Test
    fun fillValueFor_email_field_uses_email() {
        assertEquals("user@example.com",
            fillValueFor(FieldKind.EMAIL, "user", "user@example.com"))
    }

    @Test
    fun fillValueFor_email_field_falls_back_to_username_when_no_email() {
        assertEquals("user", fillValueFor(FieldKind.EMAIL, "user", ""))
    }

    @Test
    fun fillValueFor_username_field_uses_username() {
        assertEquals("user",
            fillValueFor(FieldKind.USERNAME, "user", "user@example.com"))
    }

    @Test
    fun fillValueFor_username_field_falls_back_to_email_when_no_username() {
        assertEquals("user@example.com", fillValueFor(FieldKind.USERNAME, "", "user@example.com"))
    }

    @Test
    fun fillValueFor_both_blank_is_empty() {
        assertEquals("", fillValueFor(FieldKind.EMAIL, "", ""))
        assertEquals("", fillValueFor(FieldKind.USERNAME, "", ""))
    }

    @Test
    fun capturedLogin_maps_username_email_password_fields() {
        val captured = capturedLoginFrom(
            listOf(
                FieldKind.USERNAME to "alice",
                FieldKind.EMAIL to "alice@example.com",
                FieldKind.PASSWORD to "secret",
            ),
        )
        assertEquals(CapturedLogin("alice", "alice@example.com", "secret"), captured)
    }

    @Test
    fun capturedLogin_email_only_leaves_username_blank() {
        val captured = capturedLoginFrom(
            listOf(
                FieldKind.EMAIL to "alice@example.com",
                FieldKind.PASSWORD to "secret",
            ),
        )
        assertEquals(CapturedLogin("", "alice@example.com", "secret"), captured)
    }

    @Test
    fun capturedLogin_without_password_is_null() {
        assertNull(capturedLoginFrom(listOf(FieldKind.USERNAME to "alice")))
    }

    @Test
    fun capturedLogin_blank_password_is_null() {
        assertNull(
            capturedLoginFrom(
                listOf(FieldKind.USERNAME to "alice", FieldKind.PASSWORD to "   "),
            ),
        )
    }

    @Test
    fun capturedLogin_ignores_none_and_takes_first_nonblank_of_each_kind() {
        val captured = capturedLoginFrom(
            listOf(
                FieldKind.NONE to "junk",
                FieldKind.PASSWORD to "",
                FieldKind.PASSWORD to "secret",
                FieldKind.USERNAME to "",
                FieldKind.USERNAME to "alice",
            ),
        )
        assertEquals(CapturedLogin("alice", "", "secret"), captured)
    }

    @Test
    fun effectiveIdentifier_uses_username_when_present() {
        assertEquals("alice", effectiveIdentifier("  Alice ", "a@b.com"))
    }

    @Test
    fun effectiveIdentifier_falls_back_to_email_when_username_blank() {
        assertEquals("a@b.com", effectiveIdentifier("", "A@B.com"))
    }

    @Test
    fun effectiveIdentifier_both_blank_is_empty() {
        assertEquals("", effectiveIdentifier("", "  "))
    }

    @Test
    fun decideSave_creates_when_no_match() {
        assertEquals(SaveDecision.Create, decideSave(null, null, "secret"))
    }

    @Test
    fun decideSave_updates_when_password_differs() {
        assertEquals(SaveDecision.Update("id-1"), decideSave("id-1", "old", "new"))
    }

    @Test
    fun decideSave_noop_when_password_identical() {
        assertEquals(SaveDecision.NoOp, decideSave("id-1", "same", "same"))
    }

    @Test
    fun shouldOfferSave_false_when_no_password() {
        assertFalse(shouldOfferSave(null, "example.com", "com.company.app"))
    }

    @Test
    fun shouldOfferSave_false_when_no_context() {
        val captured = CapturedLogin("alice", "", "secret")
        assertFalse(shouldOfferSave(captured, "", ""))
    }

    @Test
    fun shouldOfferSave_true_with_web_context() {
        val captured = CapturedLogin("alice", "", "secret")
        assertTrue(shouldOfferSave(captured, "example.com", ""))
    }

    @Test
    fun shouldOfferSave_true_with_app_context() {
        val captured = CapturedLogin("alice", "", "secret")
        assertTrue(shouldOfferSave(captured, "", "com.company.app"))
    }

    @Test
    fun candidateLabel_prefers_username_then_email_then_url() {
        assertEquals(
            "alice",
            candidateLabel(
                CredentialSummary("1", "alice", "https://example.com", "", email = "alice@example.com"),
            ),
        )
        assertEquals(
            "bob@example.com",
            candidateLabel(
                CredentialSummary("2", "", "https://example.com", "", email = "bob@example.com"),
            ),
        )
        assertEquals(
            "https://example.com",
            candidateLabel(CredentialSummary("3", "", "https://example.com", "")),
        )
    }
}
