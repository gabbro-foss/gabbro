//! Runtime for the Linux virtual FIDO2 authenticator (ADR-009).
//!
//! Rust owns the uhid device, the CTAPHID reassembly, and the KEEPALIVE timer
//! so none of that sits on the Dart event loop. The pump thread reads host
//! reports, answers PING/framing errors itself, and streams each complete
//! CTAP2 request up to Dart; while one waits on the user it sends KEEPALIVE so
//! the browser does not time out. Dart shows consent and calls `respond`.
//!
//! Byte plumbing is unit-tested in `uhid` and `ctaphid`; this thread/fd glue
//! is proven in the hardware matrix (no headless path to a real browser).

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
}

static DAEMON: Mutex<Option<Daemon>> = Mutex::new(None);

/// Open `/dev/uhid`, create the virtual device, and spawn the pump thread.
/// Each complete CTAP2 request is streamed to `on_request`. Idempotent-safe:
/// an already-running daemon is stopped first.
pub fn start(on_request: impl Fn(Vec<u8>) + Send + 'static) -> Result<(), String> {
    stop();

    let dev = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_NONBLOCK)
        .open("/dev/uhid")
        .map_err(|e| format!("open /dev/uhid: {e} (is the udev rule installed?)"))?;
    let mut dev = dev;
    dev.write_all(&uhid::create2_event())
        .map_err(|e| format!("create uhid device: {e}"))?;

    let shared = Arc::new(Mutex::new(Shared {
        dev,
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
    });
    Ok(())
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
pub fn stop() {
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
            if let (Some(resp), Some(cid)) = (s.pending_response.take(), s.inflight_cid) {
                for packet in ctaphid::encode_message(cid, 0x10, &resp) {
                    if s.dev.write_all(&packet).is_err() {
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
                        if s.dev.write_all(&out).is_err() {
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
                    let _ = s.dev.write_all(&ctaphid::keepalive_processing(cid));
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
            Some(report) if report.len() >= 64 => {
                let mut r = [0u8; 64];
                r.copy_from_slice(&report[..64]);
                Ok(Some(r))
            }
            _ => Ok(None),
        },
        Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
        Err(_) => Err(()),
    }
}
