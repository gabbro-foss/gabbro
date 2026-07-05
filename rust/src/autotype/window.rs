//! Active-window inspection for auto-type (ADR-017), Linux-only.
//!
//! At trigger time Gabbro captures the focused window so a later phase can
//! refocus it after the picker steals focus and abort if focus moved (the
//! wrong-window safeguard). The window id comes from the EWMH
//! `_NET_ACTIVE_WINDOW` property the window manager publishes on the root; the
//! app's identity (for diagnostics) comes from `WM_CLASS` and its title from
//! `_NET_WM_NAME`. The decode helpers here are pure and host-testable; the
//! X server round-trips are hardware-only.

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{AtomEnum, ConnectionExt as _, Window};

/// Errors from an active-window query.
#[derive(Debug, thiserror::Error)]
pub enum WindowError {
    #[error("X11 request failed: {0}")]
    Connection(#[from] x11rb::errors::ConnectionError),
    #[error("X11 reply error: {0}")]
    Reply(#[from] x11rb::errors::ReplyError),
}

/// The active window id from `_NET_ACTIVE_WINDOW`'s decoded values. EWMH uses
/// `0` -- or an absent property, i.e. an empty slice -- to mean "no window is
/// active".
pub fn first_active_window(values: &[u32]) -> Option<u32> {
    values.first().copied().filter(|&w| w != 0)
}

/// Parse a `WM_CLASS` property (`instance\0class\0`) into `(instance, class)`.
/// Empty input yields `None`; a missing class segment yields an empty class.
pub fn parse_wm_class(value: &[u8]) -> Option<(String, String)> {
    if value.is_empty() {
        return None;
    }
    let mut parts = value.split(|&b| b == 0);
    let instance = parts.next().unwrap_or_default();
    let class = parts.next().unwrap_or_default();
    Some((
        String::from_utf8_lossy(instance).into_owned(),
        String::from_utf8_lossy(class).into_owned(),
    ))
}

/// Read the currently active top-level window from the WM's `_NET_ACTIVE_WINDOW`
/// property on `root`. `Ok(None)` means the property is absent or reports no
/// active window (hardware; needs an X server).
pub fn active_window(conn: &impl Connection, root: Window) -> Result<Option<Window>, WindowError> {
    let atom = conn.intern_atom(true, b"_NET_ACTIVE_WINDOW")?.reply()?.atom;
    if atom == x11rb::NONE {
        return Ok(None);
    }
    let reply = conn
        .get_property(false, root, atom, AtomEnum::WINDOW, 0, 1)?
        .reply()?;
    let values: Vec<u32> = reply.value32().map(|it| it.collect()).unwrap_or_default();
    Ok(first_active_window(&values))
}

/// Read a window's `WM_CLASS` as `(instance, class)` (hardware).
pub fn wm_class(
    conn: &impl Connection,
    win: Window,
) -> Result<Option<(String, String)>, WindowError> {
    let reply = conn
        .get_property(false, win, AtomEnum::WM_CLASS, AtomEnum::STRING, 0, 1024)?
        .reply()?;
    Ok(parse_wm_class(&reply.value))
}

/// Read a window's title, preferring the EWMH UTF-8 `_NET_WM_NAME` and falling
/// back to the legacy `WM_NAME` (hardware).
pub fn window_title(conn: &impl Connection, win: Window) -> Result<Option<String>, WindowError> {
    let net_name = conn.intern_atom(true, b"_NET_WM_NAME")?.reply()?.atom;
    let utf8 = conn.intern_atom(true, b"UTF8_STRING")?.reply()?.atom;
    if net_name != x11rb::NONE && utf8 != x11rb::NONE {
        let reply = conn
            .get_property(false, win, net_name, utf8, 0, 1024)?
            .reply()?;
        if !reply.value.is_empty() {
            return Ok(Some(String::from_utf8_lossy(&reply.value).into_owned()));
        }
    }
    let reply = conn
        .get_property(false, win, AtomEnum::WM_NAME, AtomEnum::STRING, 0, 1024)?
        .reply()?;
    if reply.value.is_empty() {
        Ok(None)
    } else {
        Ok(Some(String::from_utf8_lossy(&reply.value).into_owned()))
    }
}

/// A snapshot of the focused window taken at trigger time -- enough to refocus
/// it and verify focus hasn't moved before typing (ADR-017).
#[derive(Debug, Clone)]
pub struct CapturedWindow {
    pub id: Window,
    pub class: Option<(String, String)>,
    pub title: Option<String>,
}

/// Capture the active window plus its class and title in one call (hardware).
/// `Ok(None)` means no window is active. Class/title are best-effort: a read
/// that fails (e.g. the window vanished mid-capture) yields `None` for that
/// field rather than failing the whole capture.
pub fn capture_active(
    conn: &impl Connection,
    root: Window,
) -> Result<Option<CapturedWindow>, WindowError> {
    let Some(id) = active_window(conn, root)? else {
        return Ok(None);
    };
    Ok(Some(CapturedWindow {
        id,
        class: wm_class(conn, id).ok().flatten(),
        title: window_title(conn, id).ok().flatten(),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_values_means_none() {
        assert_eq!(first_active_window(&[]), None);
    }

    #[test]
    fn zero_means_none() {
        assert_eq!(first_active_window(&[0]), None);
    }

    #[test]
    fn nonzero_id_is_returned() {
        assert_eq!(first_active_window(&[0x01a0_000f]), Some(0x01a0_000f));
    }

    #[test]
    fn first_value_wins() {
        assert_eq!(first_active_window(&[0xabc, 0xdef]), Some(0xabc));
    }

    #[test]
    fn wm_class_splits_instance_and_class() {
        assert_eq!(
            parse_wm_class(b"appinstance\0AppClass\0"),
            Some(("appinstance".to_string(), "AppClass".to_string())),
        );
    }

    #[test]
    fn wm_class_second_example() {
        assert_eq!(
            parse_wm_class(b"editor\0Editor\0"),
            Some(("editor".to_string(), "Editor".to_string())),
        );
    }

    #[test]
    fn wm_class_empty_is_none() {
        assert_eq!(parse_wm_class(b""), None);
    }

    #[test]
    fn wm_class_missing_class_segment_is_graceful() {
        assert_eq!(
            parse_wm_class(b"onlyinstance\0"),
            Some(("onlyinstance".to_string(), String::new())),
        );
    }
}
