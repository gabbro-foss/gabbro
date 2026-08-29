/// JNI, not flutter_rust_bridge: the autofill service runs outside Flutter in
/// the same process, sharing VAULT_SESSION. Symbol names follow
/// Java_<package_with_underscores>_<Class>_<method>.
#[cfg(target_os = "android")]
pub mod jni {
    use crate::vault::session::is_vault_unlocked;
    use jni::objects::JClass;
    use jni::sys::jboolean;
    use jni::JNIEnv;

    /// Returns JNI_TRUE if the vault session is currently unlocked.
    /// Delegates to is_vault_unlocked() - a public function that encapsulates
    /// the VAULT_SESSION mutex access.
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_isVaultUnlocked(
        _env: JNIEnv,
        _class: JClass,
    ) -> jboolean {
        u8::from(is_vault_unlocked())
    }

    /// `{"id","username","password"}`; `"{}"` when locked, unknown, or not a Login.
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

        // Zeroizing<String>: the plaintext password is scrubbed from the Rust
        // heap once the JNI copy below completes (S-06).
        let json = match get_entry_for_autofill(&id_str) {
            Ok(j) => j,
            Err(_) => zeroize::Zeroizing::new(String::from("{}")),
        };

        env.new_string(&*json).unwrap_or_else(|_| {
            env.new_string("{}")
                .expect("failed to allocate fallback JString")
        })
    }

    /// See `login_summaries_json`; `[]` when locked.
    #[no_mangle]
    pub extern "system" fn Java_app_gabbro_gabbro_RustBridge_listLoginSummaries<'local>(
        env: JNIEnv<'local>,
        _class: JClass<'local>,
    ) -> jni::objects::JString<'local> {
        use crate::vault::session::{login_summaries_for_autofill, login_summaries_json};

        let json = match login_summaries_for_autofill() {
            Ok(summaries) => login_summaries_json(&summaries),
            Err(_) => String::from("[]"),
        };

        env.new_string(json).unwrap_or_else(|_| {
            env.new_string("[]")
                .expect("failed to allocate empty JString")
        })
    }
}
