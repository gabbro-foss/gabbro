//! Linux desktop auto-type (ADR-017): X11-only, opt-in.
//!
//! Gabbro does not grab a global key; a user-bound `gabbro --autotype` trigger
//! (later phase) drives the fill. This module holds the pieces: `keysym` maps a
//! secret's characters to X11 keysyms (pure, host-testable), and the injection
//! layer (later) binds them to a scratch keycode and synthesises key events via
//! `XTEST`. Gated behind `cfg(target_os = "linux")` at the crate root.

pub mod fill;
pub mod inject;
pub mod keysym;
pub mod sequence;
pub mod trigger;
pub mod window;

/// Render a [`ReplyError`] without the value the server objected to.
///
/// x11rb's own `Display` Debug-prints the whole `X11Error`, `bad_value`
/// included. The one checked request carrying secret-derived data is
/// `ChangeKeyboardMapping` (`inject.rs`), whose payload is the password's
/// keysyms -- so a server that echoed one back would put a password character
/// on a terminal, since `lib/main.dart` prints fill errors in release builds.
/// Keep what a tester needs (the kind and the request) and drop the value.
pub(crate) fn redact_reply(e: &x11rb::errors::ReplyError) -> String {
    match e {
        x11rb::errors::ReplyError::ConnectionError(e) => format!("X11 connection error: {e}"),
        x11rb::errors::ReplyError::X11Error(e) => match e.request_name {
            Some(name) => format!("X11 request rejected: {:?} ({name})", e.error_kind),
            None => format!("X11 request rejected: {:?}", e.error_kind),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::redact_reply;
    use x11rb::errors::{ConnectionError, ReplyError};
    use x11rb::protocol::ErrorKind;
    use x11rb::x11_utils::X11Error;

    fn x11_error(request_name: Option<&'static str>) -> X11Error {
        X11Error {
            error_kind: ErrorKind::Value,
            error_code: 2,
            sequence: 42,
            bad_value: 0x79,
            minor_opcode: 0,
            major_opcode: 100,
            extension_name: None,
            request_name,
        }
    }

    #[test]
    fn a_rejection_keeps_the_kind_and_request_but_not_the_value() {
        assert_eq!(
            redact_reply(&ReplyError::X11Error(x11_error(Some(
                "ChangeKeyboardMapping"
            )))),
            "X11 request rejected: Value (ChangeKeyboardMapping)",
        );
    }

    #[test]
    fn an_unnamed_request_still_drops_the_value() {
        assert_eq!(
            redact_reply(&ReplyError::X11Error(x11_error(None))),
            "X11 request rejected: Value",
        );
    }

    #[test]
    fn a_connection_error_passes_through_with_context() {
        assert_eq!(
            redact_reply(&ReplyError::ConnectionError(
                ConnectionError::InsufficientMemory
            )),
            "X11 connection error: Insufficient memory",
        );
    }
}
