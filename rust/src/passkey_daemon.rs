//! Rust owns the uhid device, CTAPHID reassembly and the KEEPALIVE timer so
//! none of it sits on the Dart event loop; KEEPALIVE keeps the browser from
//! timing out while the user decides. This thread and fd glue has no headless
//! path to a real browser and is proven in the hardware matrix.

use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::ctaphid::{self, Ctaphid};
use crate::uhid;

/// How often to send KEEPALIVE while a request waits on the user.
const KEEPALIVE_EVERY: Duration = Duration::from_millis(100);
/// Idle sleep between fd polls, so the pump does not busy-spin.
const POLL_IDLE: Duration = Duration::from_millis(5);

/// Shared between the pump thread and the bridge calls.
struct Shared {
    /// The uhid device, opened non-blocking. Writes (responses, keepalive)
    /// and reads (host reports) both go through it under this mutex.
    dev: std::fs::File,
    hid: Ctaphid,
    /// Channel id of the request currently awaiting a Dart response, if any.
    inflight_cid: Option<u32>,
    /// The response Dart handed back, waiting to be framed and written.
    pending_response: Option<Vec<u8>>,
}

struct Daemon {
    shared: Arc<Mutex<Shared>>,
    running: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
    /// Held for the daemon's life (F4); dropping it releases the flock.
    _lock: std::fs::File,
}

/// Between `open()` and `start()`: the device exists but nothing pumps it
/// yet. Dropping it (via `stop()` or a re-open) closes the fd and the kernel
/// unplugs the virtual key.
struct Opened {
    dev: std::fs::File,
    /// Held from `open()` on (F4); dropping it releases the flock.
    lock: std::fs::File,
}

static DAEMON: Mutex<Option<Daemon>> = Mutex::new(None);
static OPENED: Mutex<Option<Opened>> = Mutex::new(None);

/// The fallible half of startup (F2): take the instance lock, open
/// `/dev/uhid`, create the virtual device. Split from `start()` so the Err
/// reaches Dart through an awaitable bridge fn - a stream fn's Err lands on
/// an unawaited FRB future and is lost, leaving the provider silently dead.
/// Idempotent-safe: an already-running daemon is stopped first.
pub fn open() -> Result<(), String> {
    stop();

    let lock = take_instance_lock()?;

    let mut dev = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_NONBLOCK)
        .open("/dev/uhid")
        .map_err(|e| format!("open /dev/uhid: {e} (is the udev rule installed?)"))?;
    dev.write_all(&uhid::create2_event())
        .map_err(|e| format!("create uhid device: {e}"))?;

    *OPENED.lock().map_err(|e| e.to_string())? = Some(Opened { dev, lock });
    Ok(())
}

/// Attach the pump thread to the device `open()` created. Each complete
/// CTAP2 request is streamed to `on_request`. Err only when `open()` did not
/// run first (a wiring bug, not a runtime condition).
pub fn start(on_request: impl Fn(Vec<u8>) + Send + 'static) -> Result<(), String> {
    let opened = OPENED
        .lock()
        .map_err(|e| e.to_string())?
        .take()
        .ok_or("passkey daemon: open() must succeed before start()")?;

    let shared = Arc::new(Mutex::new(Shared {
        dev: opened.dev,
        hid: Ctaphid::new(),
        inflight_cid: None,
        pending_response: None,
    }));
    let running = Arc::new(AtomicBool::new(true));

    let thread = {
        let shared = Arc::clone(&shared);
        let running = Arc::clone(&running);
        std::thread::spawn(move || pump(shared, running, on_request))
    };

    *DAEMON.lock().map_err(|e| e.to_string())? = Some(Daemon {
        shared,
        running,
        thread: Some(thread),
        _lock: opened.lock,
    });
    Ok(())
}

/// Exclusive single-instance lock (F4), taken BEFORE `/dev/uhid` is opened:
/// a second Gabbro instance gets a clean Err instead of creating a duplicate
/// virtual key (the browser would see two identical authenticators).
fn take_instance_lock() -> Result<std::fs::File, String> {
    use std::os::fd::AsRawFd;

    let dir = std::env::var("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let path = dir.join("gabbro-passkey.lock");
    let file = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&path)
        .map_err(|e| format!("open {}: {e}", path.display()))?;
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err(
            "another Gabbro instance already owns the passkey device (instance lock held)".into(),
        );
    }
    Ok(file)
}

/// Hand a finished CTAP2 response back to the daemon; the pump thread frames
/// and writes it, ending the KEEPALIVE for that request.
pub fn respond(response: Vec<u8>) -> Result<(), String> {
    let guard = DAEMON.lock().map_err(|e| e.to_string())?;
    let daemon = guard.as_ref().ok_or("passkey daemon is not running")?;
    let mut shared = daemon.shared.lock().map_err(|e| e.to_string())?;
    shared.pending_response = Some(response);
    Ok(())
}

/// Stop the pump thread and drop the uhid device (the kernel unplugs it).
/// Also drops an opened-but-never-pumped device from a lone `open()`.
pub fn stop() {
    if let Ok(mut g) = OPENED.lock() {
        *g = None;
    }
    let taken = DAEMON.lock().ok().and_then(|mut g| g.take());
    if let Some(mut daemon) = taken {
        daemon.running.store(false, Ordering::SeqCst);
        if let Some(t) = daemon.thread.take() {
            let _ = t.join();
        }
        // Dropping `shared` (last Arc) closes the fd; the kernel removes the
        // virtual device so the browser sees a clean unplug.
    }
}

/// The pump loop: read host reports, answer framing/PING itself, surface CTAP2
/// requests, write pending responses, and keep alive the in-flight request.
fn pump(shared: Arc<Mutex<Shared>>, running: Arc<AtomicBool>, on_request: impl Fn(Vec<u8>)) {
    let mut buf = [0u8; 4 + 128 + 64 + 64 + 2 + 2 + 16 + 4096];
    let mut last_keepalive = Instant::now();

    while running.load(Ordering::SeqCst) {
        let mut did_work = false;
        let mut surfaced: Option<Vec<u8>> = None;
        {
            let mut s = match shared.lock() {
                Ok(s) => s,
                Err(_) => return,
            };

            // 1. Write a response Dart handed back, framed on its channel.
            //    /dev/uhid accepts only uhid_event structs: every report must
            //    go through input2_event, a raw packet write is EINVAL.
            if let (Some(resp), Some(cid)) = (s.pending_response.take(), s.inflight_cid) {
                for packet in ctaphid::encode_message(cid, 0x10, &resp) {
                    if s.dev.write_all(&uhid::input2_event(&packet)).is_err() {
                        return;
                    }
                }
                s.inflight_cid = None;
                did_work = true;
            }

            // 2. Drain any host reports; PING/errors are answered inside
            //    handle_report, a complete CTAP2 message surfaces once.
            match read_event(&mut s.dev, &mut buf) {
                Ok(Some(report)) => {
                    did_work = true;
                    for out in s.hid.handle_report(&report) {
                        if s.dev.write_all(&uhid::input2_event(&out)).is_err() {
                            return;
                        }
                    }
                    if let Some((cid, _cmd, payload)) = s.hid.take_message() {
                        s.inflight_cid = Some(cid);
                        last_keepalive = Instant::now();
                        surfaced = Some(payload);
                    }
                }
                Ok(None) => {}
                Err(_) => return,
            }

            // 3. Keep the in-flight request alive while the user decides.
            if s.inflight_cid.is_some() && last_keepalive.elapsed() >= KEEPALIVE_EVERY {
                if let Some(cid) = s.inflight_cid {
                    let keepalive = ctaphid::keepalive_processing(cid);
                    let _ = s.dev.write_all(&uhid::input2_event(&keepalive));
                }
                last_keepalive = Instant::now();
            }
        }

        // Emit outside the lock: Dart's handler must not re-enter the daemon
        // while we hold `shared`.
        if let Some(payload) = surfaced {
            on_request(payload);
        }
        if !did_work {
            std::thread::sleep(POLL_IDLE);
        }
    }
}

/// Read one uhid event; return the 64-byte host report from an OUTPUT event,
/// `None` when there is nothing to read yet (EAGAIN) or the event is not an
/// OUTPUT, `Err` on a real I/O failure.
fn read_event(dev: &mut std::fs::File, buf: &mut [u8]) -> Result<Option<[u8; 64]>, ()> {
    match dev.read(buf) {
        Ok(n) => match uhid::parse_output(&buf[..n]) {
            // hidraw prepends the report number (0); strip it when present or
            // the whole CTAPHID frame parses one byte shifted.
            Some(report) if report.len() >= 64 => {
                let mut r = [0u8; 64];
                match report.len() {
                    65 => r.copy_from_slice(&report[1..65]),
                    _ => r.copy_from_slice(&report[..64]),
                }
                Ok(Some(r))
            }
            _ => Ok(None),
        },
        Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
        Err(_) => Err(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::uhid::{test_find_our_hidraw as find_our_hidraw, test_wait_for as wait_for};
    use serial_test::serial;

    // F4: two Gabbro instances must not both create the virtual key -- the
    // browser would see two identical authenticators and consent could race.
    // The flock is taken BEFORE /dev/uhid is opened, so this needs no uhid
    // access and runs everywhere (the env override keeps it off the real
    // runtime dir).
    #[test]
    #[serial]
    fn a_second_instance_gets_a_clean_err_from_the_held_lock() {
        use std::os::fd::AsRawFd;

        let dir = std::env::temp_dir().join(format!("gabbro_flock_{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("temp runtime dir");
        std::env::set_var("XDG_RUNTIME_DIR", &dir);

        // First instance: hold the exclusive lock.
        let first = std::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(dir.join("gabbro-passkey.lock"))
            .expect("lock file");
        assert_eq!(
            unsafe { libc::flock(first.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) },
            0,
            "test setup: taking the lock"
        );

        // Second instance: must fail cleanly, before touching /dev/uhid.
        let result = open();
        stop(); // cleans up if open unexpectedly succeeded (red run)
        std::env::remove_var("XDG_RUNTIME_DIR");
        let _ = std::fs::remove_dir_all(&dir);

        let err = result.expect_err("a second instance must get Err, not a duplicate key");
        assert!(err.contains("instance"), "names the cause, got: {err}");
    }

    // The pump over the real kernel pipe, spoken through hidraw as a browser
    // would. Pins INPUT2 wrapping and the stripped report-number byte: miss
    // either and the device enumerates but never answers (Brave shows only
    // Cancel).
    #[test]
    #[ignore = "needs the dev udev rule on /dev/uhid; real hardware pipe"]
    fn real_uhid_pump_answers_init_via_hidraw() {
        use std::io::{Read, Write};
        use std::os::unix::fs::OpenOptionsExt;

        open().expect("device opens");
        start(|_| {}).expect("pump attaches");

        let hidraw = wait_for("our hidraw node to appear", find_our_hidraw);
        let mut host = wait_for("hidraw node to become accessible", || {
            std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .custom_flags(libc::O_NONBLOCK)
                .open(&hidraw)
                .ok()
        });

        // Browser writes INIT: report number 0 + the 64-byte report.
        let mut init = [0u8; 65];
        init[1..5].copy_from_slice(&0xffff_ffffu32.to_be_bytes());
        init[5] = 0x80 | 0x06;
        init[7] = 8;
        init[8..16].copy_from_slice(b"pumptest");
        host.write_all(&init).expect("host writes INIT via hidraw");

        let mut resp = [0u8; 64];
        wait_for("the INIT response on hidraw", || {
            match host.read(&mut resp) {
                Ok(n) if n >= 17 => Some(()),
                _ => None,
            }
        });
        stop();

        assert_eq!(&resp[0..4], &0xffff_ffffu32.to_be_bytes(), "broadcast CID");
        assert_eq!(resp[4], 0x80 | 0x06, "INIT response");
        assert_eq!(&resp[7..15], b"pumptest", "nonce echoed through the pump");
    }
}
