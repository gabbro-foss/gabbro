//! Hardware diagnostic for ADR-017 Phase 2a: report the active window.
//!
//! Usage:
//!   cargo run --bin autotype_window
//!
//! Prints the focused window's id, WM_CLASS and title once a second for ten
//! seconds. Run it, then click around (browser, editor, terminal) and confirm
//! it tracks focus and reads each app correctly on your X11/qtile session.

#[cfg(target_os = "linux")]
fn main() {
    use std::{thread, time::Duration};
    use x11rb::connection::Connection;

    use rust_lib_gabbro::autotype::window;

    let (conn, screen_num) = match x11rb::connect(None) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("could not connect to the X server: {e}");
            std::process::exit(1);
        }
    };
    let root = conn.setup().roots[screen_num].root;

    eprintln!("autotype_window: reporting the active window once a second for 10s.");
    eprintln!("click around (browser, editor, terminal) and watch it track focus.\n");

    for _ in 0..10 {
        match window::active_window(&conn, root) {
            Ok(Some(win)) => {
                let class = window::wm_class(&conn, win).ok().flatten();
                let title = window::window_title(&conn, win).ok().flatten();
                println!("active=0x{win:08x} class={class:?} title={title:?}");
            }
            Ok(None) => println!("active=<none>"),
            Err(e) => println!("error: {e}"),
        }
        thread::sleep(Duration::from_secs(1));
    }
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("autotype_window is Linux-only (ADR-017).");
    std::process::exit(1);
}
