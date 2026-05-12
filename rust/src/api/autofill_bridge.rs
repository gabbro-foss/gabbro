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
}