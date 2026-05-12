/// JNI bridge functions for GabbroAutofillService.
///
/// These are called directly from Kotlin (not via flutter_rust_bridge) because
/// the autofill service runs outside Flutter but inside the same process.
/// The VAULT_SESSION global is shared — no new session state needed.
///
/// Naming rule: Java_<package_dots_as_underscores>_<Class>_<method>
/// Package: app.gabbro.gabbro  →  app_gabbro_gabbro
#[cfg(target_os = "android")]
pub mod jni {
    use jni::JNIEnv;
    use jni::objects::JClass;
    use jni::sys::jboolean;
    use crate::vault::session::is_vault_unlocked;

    /// Returns JNI_TRUE if the vault session is currently unlocked.
    /// Delegates to is_vault_unlocked() — a public function that encapsulates
    /// the VAULT_SESSION mutex access.
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_isVaultUnlocked(
        _env: JNIEnv,
        _class: JClass,
    ) -> jboolean {
        u8::from(is_vault_unlocked())
    }

    /// Returns a JSON string encoding id, username, and password for a single
    /// Login entry looked up by UUID.
    ///
    /// Shape: `{"id":"...","username":"...","password":"..."}`
    /// Returns `"{}"` if the vault is locked, the id is not found, or the
    /// entry is not a Login entry.
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_getEntry<'local>(
        mut env: JNIEnv<'local>,
        _class: JClass<'local>,
        id: jni::objects::JString<'local>,
    ) -> jni::objects::JString<'local> {
        use crate::vault::session::get_entry_for_autofill;

        let id_str: String = match env.get_string(&id) {
            Ok(s) => s.into(),
            Err(_) => return env.new_string("{}").expect("failed to allocate JString"),
        };

        let json = match get_entry_for_autofill(&id_str) {
            Ok(j) => j,
            Err(_) => String::from("{}"),
        };

        env.new_string(json).unwrap_or_else(|_| {
            env.new_string("{}").expect("failed to allocate fallback JString")
        })
    }

    /// Returns a JSON string encoding all Login entry summaries in the session.
    ///
    /// Shape: `[{"id":"...","username":"...","url":"..."}]`
    /// Returns an empty array `[]` if the vault is locked or the session is empty.
    /// Kotlin parses this with org.json.JSONArray — no new Android dependency needed.
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_listLoginSummaries<'local>(
        mut env: JNIEnv<'local>,
        _class: JClass<'local>,
    ) -> jni::objects::JString<'local> {
        use crate::vault::session::login_summaries_for_autofill;

        let json = match login_summaries_for_autofill() {
            Ok(summaries) => {
                let entries: Vec<String> = summaries.iter().map(|s| {
                    format!(
                        "{{\"id\":\"{}\",\"username\":\"{}\",\"url\":\"{}\"}}",
                        s.id.replace('"', "\\\""),
                        s.username.replace('"', "\\\""),
                        s.url.replace('"', "\\\""),
                    )
                }).collect();
                format!("[{}]", entries.join(","))
            }
            Err(_) => String::from("[]"),
        };

        env.new_string(json).unwrap_or_else(|_| {
            env.new_string("[]").expect("failed to allocate empty JString")
        })
    }
}