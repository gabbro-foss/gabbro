//! Linux desktop auto-type (ADR-017): X11-only, opt-in.
//!
//! Gabbro does not grab a global key; a user-bound `gabbro --autotype` trigger
//! (later phase) drives the fill. This module holds the pieces: `keysym` maps a
//! secret's characters to X11 keysyms (pure, host-testable), and the injection
//! layer (later) binds them to a scratch keycode and synthesises key events via
//! `XTEST`. Gated behind `cfg(target_os = "linux")` at the crate root.

pub mod inject;
pub mod keysym;
