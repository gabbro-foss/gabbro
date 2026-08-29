//! Auto-type bridge (ADR-017). Compiles on every platform because the generated
//! frb glue references these fns unconditionally; off Linux each `impl_*` is
//! a "Linux-only" stub.

/// The window captured at trigger time, flattened for the bridge.
pub struct CapturedWindowData {
    pub id: u32,
    pub app_class: String,
    pub title: String,
}

/// Capture the currently focused window (Linux only).
pub fn autotype_capture_active_window() -> Result<Option<CapturedWindowData>, String> {
    impl_capture()
}

/// Fill `entry_id` into `window_id` (Linux only). The secret is read from the
/// Rust session and injected without crossing the bridge.
pub fn autotype_fill(window_id: u32, entry_id: String) -> Result<(), String> {
    impl_fill(window_id, entry_id)
}

/// The unix-socket path the Dart listener should bind and the client uses.
pub fn autotype_socket_path() -> String {
    impl_socket_path()
}

/// The trigger token the Dart listener must match (avoids duplicating it).
pub fn autotype_trigger_token() -> String {
    impl_token()
}

#[cfg(target_os = "linux")]
pub(crate) fn impl_capture() -> Result<Option<CapturedWindowData>, String> {
    use x11rb::connection::Connection;
    let (conn, screen) = x11rb::connect(None).map_err(|e| e.to_string())?;
    let root = conn.setup().roots[screen].root;
    let captured =
        crate::autotype::window::capture_active(&conn, root).map_err(|e| e.to_string())?;
    Ok(captured.map(captured_to_data))
}

#[cfg(target_os = "linux")]
pub(crate) fn impl_fill(window_id: u32, entry_id: String) -> Result<(), String> {
    crate::autotype::fill::fill(window_id, &entry_id).map_err(|e| e.to_string())
}

#[cfg(target_os = "linux")]
pub(crate) fn impl_socket_path() -> String {
    crate::autotype::trigger::default_socket_path()
        .to_string_lossy()
        .into_owned()
}

#[cfg(target_os = "linux")]
pub(crate) fn impl_token() -> String {
    crate::autotype::trigger::trigger_token().to_string()
}

#[cfg(target_os = "linux")]
fn captured_to_data(w: crate::autotype::window::CapturedWindow) -> CapturedWindowData {
    CapturedWindowData {
        id: w.id,
        // WM_CLASS is (instance, class); the class element is the app-facing
        // name (e.g. "Brave-browser").
        app_class: w.class.map(|(_instance, class)| class).unwrap_or_default(),
        title: w.title.unwrap_or_default(),
    }
}

#[cfg(not(target_os = "linux"))]
pub(crate) fn impl_capture() -> Result<Option<CapturedWindowData>, String> {
    Err("auto-type is Linux-only".to_string())
}

#[cfg(not(target_os = "linux"))]
pub(crate) fn impl_fill(window_id: u32, entry_id: String) -> Result<(), String> {
    let _ = (window_id, entry_id);
    Err("auto-type is Linux-only".to_string())
}

#[cfg(not(target_os = "linux"))]
pub(crate) fn impl_socket_path() -> String {
    String::new()
}

#[cfg(not(target_os = "linux"))]
pub(crate) fn impl_token() -> String {
    String::new()
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::captured_to_data;
    use crate::autotype::window::CapturedWindow;

    #[test]
    fn captured_window_full_flatten() {
        let d = captured_to_data(CapturedWindow {
            id: 0x1a0_000f,
            class: Some(("brave-browser".into(), "Brave-browser".into())),
            title: Some("Login - Brave".into()),
        });
        assert_eq!(d.id, 0x1a0_000f);
        assert_eq!(d.app_class, "Brave-browser"); // the class element, not instance
        assert_eq!(d.title, "Login - Brave");
    }

    #[test]
    fn captured_window_no_class() {
        let d = captured_to_data(CapturedWindow {
            id: 7,
            class: None,
            title: Some("t".into()),
        });
        assert_eq!(d.id, 7);
        assert_eq!(d.app_class, "");
        assert_eq!(d.title, "t");
    }

    #[test]
    fn captured_window_no_title() {
        let d = captured_to_data(CapturedWindow {
            id: 7,
            class: Some(("i".into(), "C".into())),
            title: None,
        });
        assert_eq!(d.app_class, "C");
        assert_eq!(d.title, "");
    }
}
