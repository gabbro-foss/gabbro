//! uhid transport for the Linux virtual FIDO2 authenticator.
//!
//! Registers a virtual HID device with the kernel via /dev/uhid so browsers
//! enumerate Gabbro exactly like a plugged-in security key. Struct layout
//! pinned against /usr/include/linux/uhid.h (UHID_CREATE2 = 11, packed).

/// Our fixed identity: pid.codes test VID/PID until a permanent PID is
/// registered. The YubiKey-unlock scan filters exactly these (item 19).
pub const VENDOR_ID: u32 = 0x1209;
pub const PRODUCT_ID: u32 = 0x0001;

const UHID_CREATE2: u32 = 11;
const BUS_USB: u16 = 0x03;
const DEVICE_NAME: &[u8] = b"Gabbro Passkey Authenticator";

/// The F1D0 report descriptor browsers scan for: usage page 0xF1D0, usage
/// 0x01, 64-byte IN and OUT reports (layout proven by tpm-fido).
const REPORT_DESCRIPTOR: &[u8] = &[
    0x06, 0xd0, 0xf1, // USAGE_PAGE (FIDO Alliance)
    0x09, 0x01, // USAGE (U2F HID Authenticator Device)
    0xa1, 0x01, // COLLECTION (Application)
    0x09, 0x20, // USAGE (Input Report Data)
    0x15, 0x00, // LOGICAL_MINIMUM (0)
    0x26, 0xff, 0x00, // LOGICAL_MAXIMUM (255)
    0x75, 0x08, // REPORT_SIZE (8)
    0x95, 0x40, // REPORT_COUNT (64)
    0x81, 0x02, // INPUT (Data,Var,Abs)
    0x09, 0x21, // USAGE (Output Report Data)
    0x15, 0x00, // LOGICAL_MINIMUM (0)
    0x26, 0xff, 0x00, // LOGICAL_MAXIMUM (255)
    0x75, 0x08, // REPORT_SIZE (8)
    0x95, 0x40, // REPORT_COUNT (64)
    0x91, 0x02, // OUTPUT (Data,Var,Abs)
    0xc0, // END_COLLECTION
];

/// The UHID_CREATE2 event announcing the device: written to /dev/uhid once
/// at daemon start. Packed uhid_event layout: type u32 | name[128] |
/// phys[64] | uniq[64] | rd_size u16 | bus u16 | vendor u32 | product u32 |
/// version u32 | country u32 | rd_data[4096].
pub fn create2_event() -> Vec<u8> {
    let mut ev = vec![0u8; 4 + 128 + 64 + 64 + 2 + 2 + 16 + 4096];
    ev[0..4].copy_from_slice(&UHID_CREATE2.to_ne_bytes());
    ev[4..4 + DEVICE_NAME.len()].copy_from_slice(DEVICE_NAME);
    ev[260..262].copy_from_slice(&(REPORT_DESCRIPTOR.len() as u16).to_ne_bytes());
    ev[262..264].copy_from_slice(&BUS_USB.to_ne_bytes());
    ev[264..268].copy_from_slice(&VENDOR_ID.to_ne_bytes());
    ev[268..272].copy_from_slice(&PRODUCT_ID.to_ne_bytes());
    // version and country stay zero.
    ev[280..280 + REPORT_DESCRIPTOR.len()].copy_from_slice(REPORT_DESCRIPTOR);
    ev
}

const UHID_OUTPUT: u32 = 6;
const UHID_INPUT2: u32 = 12;
const UHID_DATA_MAX: usize = 4096;

/// Wrap a 64-byte HID report as a UHID_INPUT2 event for /dev/uhid:
/// type u32 | size u16 | data[4096].
pub fn input2_event(report: &[u8; 64]) -> Vec<u8> {
    let mut ev = vec![0u8; 4 + 2 + UHID_DATA_MAX];
    ev[0..4].copy_from_slice(&UHID_INPUT2.to_ne_bytes());
    ev[4..6].copy_from_slice(&(report.len() as u16).to_ne_bytes());
    ev[6..6 + report.len()].copy_from_slice(report);
    ev
}

/// Extract the report bytes from a UHID_OUTPUT event the kernel delivers:
/// type u32 | data[4096] | size u16 | rtype u8. Returns None for any other
/// event type.
pub fn parse_output(event: &[u8]) -> Option<Vec<u8>> {
    if event.len() < 4 + UHID_DATA_MAX + 2 {
        return None;
    }
    let ty = u32::from_ne_bytes([event[0], event[1], event[2], event[3]]);
    if ty != UHID_OUTPUT {
        return None;
    }
    let size =
        u16::from_ne_bytes([event[4 + UHID_DATA_MAX], event[4 + UHID_DATA_MAX + 1]]) as usize;
    Some(event[4..4 + size.min(UHID_DATA_MAX)].to_vec())
}

/// Test helper (crate-wide): retry `f` every 10ms until it yields, or panic
/// with `what` after 5s - bounded waits only, a test can never hang on it.
#[cfg(test)]
pub(crate) fn test_wait_for<T>(what: &str, mut f: impl FnMut() -> Option<T>) -> T {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    loop {
        if let Some(v) = f() {
            return v;
        }
        if std::time::Instant::now() > deadline {
            panic!("timed out waiting for {what}");
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}

/// Test helper (crate-wide): the /dev/hidraw* node carrying our VID/PID.
#[cfg(test)]
pub(crate) fn test_find_our_hidraw() -> Option<std::path::PathBuf> {
    for entry in std::fs::read_dir("/sys/class/hidraw").ok()?.flatten() {
        let uevent = entry.path().join("device/uevent");
        if let Ok(s) = std::fs::read_to_string(&uevent) {
            if s.contains("00001209:00000001") {
                let mut p = std::path::PathBuf::from("/dev");
                p.push(entry.file_name());
                return Some(p);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    // The F1D0 report descriptor browsers scan for, byte-for-byte the layout
    // proven by tpm-fido: usage page 0xF1D0, usage 0x01, 64-byte IN and OUT
    // reports. Any deviation and Chromium/Firefox never list the device.
    const FIDO_REPORT_DESCRIPTOR: [u8; 34] = [
        0x06, 0xd0, 0xf1, // USAGE_PAGE (FIDO Alliance)
        0x09, 0x01, // USAGE (U2F HID Authenticator Device)
        0xa1, 0x01, // COLLECTION (Application)
        0x09, 0x20, // USAGE (Input Report Data)
        0x15, 0x00, // LOGICAL_MINIMUM (0)
        0x26, 0xff, 0x00, // LOGICAL_MAXIMUM (255)
        0x75, 0x08, // REPORT_SIZE (8)
        0x95, 0x40, // REPORT_COUNT (64)
        0x81, 0x02, // INPUT (Data,Var,Abs)
        0x09, 0x21, // USAGE (Output Report Data)
        0x15, 0x00, // LOGICAL_MINIMUM (0)
        0x26, 0xff, 0x00, // LOGICAL_MAXIMUM (255)
        0x75, 0x08, // REPORT_SIZE (8)
        0x95, 0x40, // REPORT_COUNT (64)
        0x91, 0x02, // OUTPUT (Data,Var,Abs)
        0xc0, // END_COLLECTION
    ];

    #[test]
    fn create2_event_announces_a_fido_device_under_our_identity() {
        // Packed uhid_event: type u32 | name[128] | phys[64] | uniq[64] |
        // rd_size u16 | bus u16 | vendor u32 | product u32 | version u32 |
        // country u32 | rd_data[4096].
        let ev = create2_event();

        assert_eq!(ev.len(), 4 + 128 + 64 + 64 + 2 + 2 + 16 + 4096);
        assert_eq!(
            u32::from_ne_bytes([ev[0], ev[1], ev[2], ev[3]]),
            11,
            "UHID_CREATE2"
        );
        assert!(ev[4..].starts_with(b"Gabbro"), "device name names us");
        assert_eq!(
            u16::from_ne_bytes([ev[260], ev[261]]),
            FIDO_REPORT_DESCRIPTOR.len() as u16,
            "rd_size"
        );
        assert_eq!(u16::from_ne_bytes([ev[262], ev[263]]), 0x03, "BUS_USB");
        assert_eq!(
            u32::from_ne_bytes([ev[264], ev[265], ev[266], ev[267]]),
            VENDOR_ID
        );
        assert_eq!(
            u32::from_ne_bytes([ev[268], ev[269], ev[270], ev[271]]),
            PRODUCT_ID
        );
        assert_eq!(
            &ev[280..280 + FIDO_REPORT_DESCRIPTOR.len()],
            &FIDO_REPORT_DESCRIPTOR,
            "the descriptor browsers scan for, byte-for-byte"
        );
    }

    const UHID_INPUT2: u32 = 12;
    const UHID_OUTPUT: u32 = 6;

    #[test]
    fn input2_wraps_a_report_for_the_kernel() {
        // uhid_input2_req: type u32 | size u16 | data[4096].
        let mut report = [0u8; 64];
        report[0..4].copy_from_slice(&[0xDE, 0xAD, 0xBE, 0xEF]);
        let ev = input2_event(&report);

        assert_eq!(ev.len(), 4 + 2 + 4096);
        assert_eq!(
            u32::from_ne_bytes([ev[0], ev[1], ev[2], ev[3]]),
            UHID_INPUT2
        );
        assert_eq!(u16::from_ne_bytes([ev[4], ev[5]]), 64, "size");
        assert_eq!(&ev[6..70], &report, "the report follows verbatim");
    }

    #[test]
    fn parse_output_extracts_the_host_report() {
        // uhid_output_req: type u32 | data[4096] | size u16 | rtype u8.
        let mut ev = vec![0u8; 4 + 4096 + 2 + 1];
        ev[0..4].copy_from_slice(&UHID_OUTPUT.to_ne_bytes());
        ev[4..68].copy_from_slice(&[0xAB; 64]);
        ev[4 + 4096..4 + 4096 + 2].copy_from_slice(&64u16.to_ne_bytes());

        let report = parse_output(&ev).expect("an OUTPUT event yields a report");
        assert_eq!(report, vec![0xAB; 64]);
    }

    #[test]
    fn parse_output_ignores_other_event_types() {
        // A START (type 3) event carries no host report.
        let mut ev = vec![0u8; 4 + 4096 + 2 + 1];
        ev[0..4].copy_from_slice(&3u32.to_ne_bytes());
        assert!(parse_output(&ev).is_none());
    }

    use super::{test_find_our_hidraw as find_our_hidraw, test_wait_for as wait_for};

    // Real-device loopback, both ends of the kernel pipe: create the device
    // via /dev/uhid (the daemon side), then talk to it through its hidraw
    // node exactly as a browser would (the host side). INIT goes in through
    // hidraw, surfaces here as a UHID_OUTPUT, our reply returns via INPUT2,
    // and the host reads the echoed nonce back from hidraw.
    #[test]
    #[ignore = "needs the dev udev rule on /dev/uhid; real hardware pipe"]
    fn real_uhid_loopback_init_roundtrips() {
        use std::io::{Read, Write};
        use std::os::unix::fs::OpenOptionsExt;
        let mut dev = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open("/dev/uhid")
            .expect("open /dev/uhid (is the dev udev rule in place?)");
        dev.write_all(&create2_event()).expect("create device");

        // Host side: the fido_id udev builtin tags the new node and logind
        // grants us access - the same path a browser relies on.
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
        init[8..16].copy_from_slice(b"loopback");
        host.write_all(&init).expect("host writes INIT via hidraw");

        // Daemon side: pump uhid events until the INIT report arrives. The
        // buffer holds a full uhid_event (4376 bytes): a short read buffer
        // risks EINVAL depending on kernel truncation semantics.
        let mut hid = crate::ctaphid::Ctaphid::new();
        let mut buf = [0u8; 4 + 128 + 64 + 64 + 2 + 2 + 16 + 4096];
        let report = wait_for("the OUTPUT event carrying INIT", || {
            match dev.read(&mut buf) {
                Ok(n) => parse_output(&buf[..n]),
                Err(_) => None, // EAGAIN: no event yet
            }
        });
        // hidraw prepends the report number; strip it when present.
        let mut r = [0u8; 64];
        match report.len() {
            65 => r.copy_from_slice(&report[1..65]),
            n if n >= 64 => r.copy_from_slice(&report[..64]),
            n => panic!("short OUTPUT report: {n} bytes"),
        }
        for reply in hid.handle_report(&r) {
            dev.write_all(&input2_event(&reply)).expect("write INPUT2");
        }

        // Host reads the INIT response back.
        let mut resp = [0u8; 64];
        wait_for("the INIT response on hidraw", || {
            match host.read(&mut resp) {
                Ok(n) if n >= 17 => Some(()),
                _ => None,
            }
        });
        assert_eq!(&resp[0..4], &0xffff_ffffu32.to_be_bytes(), "broadcast CID");
        assert_eq!(resp[4], 0x80 | 0x06, "INIT response");
        assert_eq!(&resp[7..15], b"loopback", "nonce echoed through the kernel");
        let cid = u32::from_be_bytes([resp[15], resp[16], resp[17], resp[18]]);
        assert_ne!(cid, 0, "a real channel was allocated");
    }
}
